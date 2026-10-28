/**
 * OAuth login against the mocked Google IdP (WireMock Cloud).
 *
 * The SDK's own authorization-code helpers hard-code the spec's placeholder auth
 * server (https://example.com/oauth), so this module implements the browser flow
 * directly: build the authorize URL, redirect the whole window, then exchange the
 * returned code at the token endpoint. As with real Google, the access token is
 * opaque, so the app authenticates to the gateway with the ID token: an RS256 JWT
 * the gateway validates locally against the IdP's JWKS.
 */

const IDP_BASE_URL = 'https://4654yr.wiremockapi.cloud';
const CLIENT_ID = 'train-travel-demo';
const SCOPES = 'openid email';
const STATE_STORAGE_KEY = 'traintravel.oauth_state';
const TOKEN_STORAGE_KEY = 'traintravel.id_token';

export const REDIRECT_PATH = '/callback';

const redirectUri = () => `${window.location.origin}${REDIRECT_PATH}`;

/** Authorize URL with a per-session state we verify in the callback. */
export const buildLoginUrl = (): string => {
  const state = crypto.randomUUID();
  sessionStorage.setItem(STATE_STORAGE_KEY, state);
  const params = new URLSearchParams({
    response_type: 'code',
    client_id: CLIENT_ID,
    redirect_uri: redirectUri(),
    scope: SCOPES,
    state,
  });
  return `${IDP_BASE_URL}/o/oauth2/v2/auth?${params.toString()}`;
};

/** Kicks off login by navigating the window to the mock Google sign-in page. */
export const login = () => {
  window.location.href = buildLoginUrl();
};

/** Guards against stale/cross-session authorization codes. */
export const verifyState = (state: string | undefined): boolean =>
  !!state && state === sessionStorage.getItem(STATE_STORAGE_KEY);

/** Exchanges the authorization code for the ID token (JWT). */
export const exchangeCodeForToken = async (code: string): Promise<string> => {
  const response = await fetch(`${IDP_BASE_URL}/token`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'authorization_code',
      code,
      redirect_uri: redirectUri(),
    }),
  });
  if (!response.ok) {
    throw new Error(`token endpoint returned ${response.status}`);
  }
  const json = await response.json();
  if (!json.id_token) {
    throw new Error('token response contained no ID token');
  }
  return json.id_token as string;
};

export const loadToken = (): string | null =>
  localStorage.getItem(TOKEN_STORAGE_KEY);

export const saveToken = (token: string) =>
  localStorage.setItem(TOKEN_STORAGE_KEY, token);

export const clearToken = () => localStorage.removeItem(TOKEN_STORAGE_KEY);