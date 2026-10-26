# Train Travel Microservices — demo gateway

A Spring Boot (Kotlin) gateway implementing the [Train Travel API](train-travel-openapi.yaml), backed by
**four invented external microservices — all of them mocked in WireMock Cloud** — with a bundled
SolidJS UI that consumes the API end-to-end, including real OAuth login against the mocked Google IdP:

| Downstream | Flavour | WireMock Cloud mock API | Techniques showcased |
|---|---|---|---|
| European Rail Reference Data | REST | `Train Travel Stations Service` (`wm-train-travel-stations`) | CSV data-driven stubs (`data-exists`), pagination |
| European Rail Timetable | REST | `Train Travel Trips Service` (`wm-train-travel-trips`) | CSV data-driven + date-stamped response templating |
| Rail Reservations | REST | `Train Travel Bookings Service` (`wm-train-travel-bookings`) | Stateful stubs: KV store, per-user state contexts (`X-User-Id`), `require-state` matching |
| PayRail | **SOAP 1.1** | `Train Travel Payments Service` (`wm-train-travel-payments`) | Unstructured mock, body-matched SOAP stubs, masked-card templating |
| Stripe | REST + hosted page | Stripe API template | Stateful Checkout Sessions API, **hosted Checkout page test double** |
| Mock Google IdP | OAuth2 | Google OAuth2 template | Auth-code flow, JWKS, **RS256 ID tokens validated by the gateway** |
| Webhook receiver | REST sink | `Train Travel Webhook Receiver` (`wm-train-travel-webhook`) | Open-URL stub, request journal as webhook evidence |

Full design specs: [`docs/train-travel-microservices/`](docs/train-travel-microservices/). The API
contracts for the invented downstream services live in [`contracts/`](contracts/) (OpenAPI
descriptions + the PayRail WSDL) — enough to generate a mock estate from scratch — and the
hand-authored stub mappings deployed in WireMock Cloud live in [`stubs/`](stubs/).

## Prerequisites

- Java 21+ (the Gradle wrapper needs Java 24 or lower to *run*; compilation targets a Java 21 toolchain)
- The WireMock Cloud mock estate above, created in your own WireMock Cloud account (the OpenAPI
  descriptions in [`contracts/`](contracts/) and the stub mappings in [`stubs/`](stubs/) are enough to
  recreate it). The mock URLs in this repo are `<…-mock-id>` placeholders: replace them with your mock
  API IDs in [`application.yml`](src/main/resources/application.yml),
  [`ui/src/lib/auth.ts`](ui/src/lib/auth.ts) and the
  [Postman environment](postman/train-travel.postman_environment.json).
- Node 20+ with [pnpm](https://pnpm.io) — only if you want the UI and/or the browser E2E

## Run it (gateway)

```bash
./gradlew bootRun
```

The gateway starts on `http://localhost:8080`. All downstream base URLs are config properties —
see [`src/main/resources/application.yml`](src/main/resources/application.yml).

> **Note on the IdP:** the gateway validates Google ID tokens against the mock IdP at
> `https://<google-idp-mock-id>.wiremockapi.cloud`, and the IdP stamps the token's `iss` from whatever base URL issued it.
> Get your tokens from that exact URL (as the script below does) or adjust
> `spring.security.oauth2.resourceserver.jwt.issuer-uri` to match. The token's `aud` must also be the
> app's client ID (`train-travel-demo`, set by `…jwt.audiences`).

## The UI app

A SolidJS + Vite single-page app ([`ui/`](ui/), originally
[wiremock-inc/Train-travel-demo-UI](https://github.com/wiremock-inc/Train-travel-demo-UI)) that talks to
the gateway through the APIMatic-generated `@wiremock-inc/apimatic-sdkgen-demo` SDK, vendored as
built JavaScript in [`ui/vendor/`](ui/vendor/apimatic-sdkgen-demo).

### Run it

With the gateway already running on `localhost:8080`:

```bash
cd ui
pnpm install
pnpm dev          # http://localhost:3000
```

The app defaults to `http://localhost:8080` for its API host; the navbar's "Override API host" input
points it elsewhere, and **Reset** returns to the default.

> The vendored SDK carries two local fixes (see the commit history for the reasons: an https-only base
> URI and a `cvc`-required response schema both conflict with the API spec). pnpm copies it into
> `node_modules` on `install`, so after editing it run `pnpm install --force`, then **restart
> `pnpm dev`** — Vite's dependency cache only re-optimizes at startup.

### Using the app

1. **Log in** (navbar, top right). The browser redirects to the mock Google sign-in page — enter any
   email, click *Continue* — and you're back, logged in with a Google ID token stored in `localStorage`
   (sessions survive refreshes; **Log out** clears the token).
2. **Book a trip**: pick two stations (e.g. Berlin Hauptbahnhof → München Hauptbahnhof) and a future
   date; the trips table lists available connections. Click **Book** on one, fill in the passenger
   name, optionally tick bicycle/dog, and submit.
3. **Pay**: on the payment page, any card number is approved by the PayRail mock — except
   `4000 0000 0000 0002`, which is declined: the error panel shows the gateway's actual decline
   reason (*"Payment was declined by the payment provider (card_declined)"*) and the booking stays
   payable, so you can succeed with `4242 4242 4242 4242` (or anything else) straight after.
   Or click **Pay with Stripe**: the gateway creates a Stripe Checkout session and the browser is
   sent to the (mocked) Stripe-hosted page. **Pay** returns you to the payment page, where the
   gateway verifies the session with Stripe and confirms the booking; **Cancel** returns you with
   the booking still payable.
4. **My bookings** lists your (and only your) bookings — delete to release a hold.

Every UI click exercises the same mocked stack as the curl walkthrough below: stations/trips from the
CSV data-driven mocks, bookings from the per-user stateful mock, payments through the PayRail SOAP
mock, and the login JWT comes from the same mocked Google IdP.

## Browser E2E

[`e2e/journey.mjs`](e2e/journey.mjs) drives a real Chrome (via `puppeteer-core`) through the whole
journey: log in via the mock IdP → find trips → book → declined card → approved payment →
book again → Stripe hosted Checkout (cancel, then pay) → My bookings → delete → log out.

```bash
cd e2e
pnpm install
node journey.mjs
```

The browser window is **visible by default** — you can watch the whole journey play out in a real
Chrome. Pass `--headless` to run without a window (e.g. in CI).

Requires the gateway on `:8080`, the UI dev server on `:3000`, and Chrome installed at the standard
location. Chrome is launched with `--no-sandbox` (an automated instance alongside your normal Chrome
can't bootstrap its own sandbox). Expect `=== JOURNEY PASSED ===` and exactly one ≥400 response —
the deliberately declined payment.

## The demo walkthrough (curl)

Every step below is copy-pasteable. The auth flow is fully scriptable — the mock IdP's login is just a
form POST, so no browser is needed (open `https://<google-idp-mock-id>.wiremockapi.cloud/o/oauth2/v2/auth?...` in a
browser if you want the Google-styled page experience).

### 0. Log in (authorization code flow, scripted)

```bash
AUTH=https://<google-idp-mock-id>.wiremockapi.cloud
API=http://localhost:8080

# "Log in" as demo@example.com - the mock returns a 302 carrying the auth code
LOCATION=$(curl -s -o /dev/null -D - -X POST "$AUTH/login" \
  --data-urlencode "clientId=train-travel-demo" \
  --data-urlencode "email=demo@example.com" \
  --data-urlencode "scopes=openid email" \
  --data-urlencode "state=demo-state" \
  --data-urlencode "redirectUri=http://localhost:9090/callback" \
  | grep -i '^location:' | tr -d '\r')
CODE=$(echo "$LOCATION" | sed -E 's/.*[?&]code=([^&]+).*/\1/')

# Exchange the code for tokens - as with real Google the access token is opaque, so the bearer is
# the ID token: an RS256 JWT with iss, aud, sub and email
TOKEN=$(curl -s -X POST "$AUTH/token" \
  --data-urlencode "grant_type=authorization_code" \
  --data-urlencode "code=$CODE" | jq -r .id_token)
```

### 1. Find stations

```bash
curl -s "$API/stations?search=Milano" -H "Authorization: Bearer $TOKEN" | jq .
curl -s "$API/stations?country=DE" -H "Authorization: Bearer $TOKEN" | jq '.data[].name'
curl -s "$API/stations?coordinates=48.85,2.35" -H "Authorization: Bearer $TOKEN" | jq '.data[0]'  # sorted by distance from Paris
```

### 2. Find trips (Berlin → München)

```bash
BERLIN=$(curl -s "$API/stations?search=Berlin" -H "Authorization: Bearer $TOKEN" | jq -r '.data[0].id')
# non-ASCII search terms need URL-encoding -- Postman and browsers do this automatically
MUNICH=$(curl -s --get "$API/stations" --data-urlencode "search=München" -H "Authorization: Bearer $TOKEN" | jq -r '.data[0].id')

curl -s "$API/trips?origin=$BERLIN&destination=$MUNICH&date=$(date -u +%Y-%m-%d)" \
  -H "Authorization: Bearer $TOKEN" | jq .
```

### 3. Create a booking (the webhook fires)

```bash
TRIP=$(curl -s "$API/trips?origin=$BERLIN&destination=$MUNICH&date=$(date -u +%Y-%m-%d)" \
  -H "Authorization: Bearer $TOKEN" | jq -r '.data[0].id')

BOOKING=$(curl -s -X POST "$API/bookings" -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"trip_id\": \"$TRIP\", \"passenger_name\": \"Jane Smith\", \"has_bicycle\": true, \"has_dog\": false}")
echo "$BOOKING" | jq .
BOOKING_ID=$(echo "$BOOKING" | jq -r .id)
```

**Webhook evidence:** open the `Train Travel Webhook Receiver` mock API in the WireMock Cloud UI and look at
its request journal — the `newBooking` payload is sitting there.

### 4. Pay for the booking (SOAP saga)

```bash
# Approved (4242...) - the booking becomes CONFIRMED and survives its 1-hour expiry
curl -s -X POST "$API/bookings/$BOOKING_ID/payment" -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"amount": 89.90, "currency": "eur",
       "source": {"object": "card", "name": "J. Doe", "number": "4242424242424242",
                  "cvc": "123", "exp_month": 12, "exp_year": 2027,
                  "address_country": "gb", "address_post_code": "N12 9XX"}}' | jq .
```

Declined card (`4000000000000002`) → `400` with `problem+json`, booking stays `HELD` and can be paid again:

```bash
curl -s -X POST "$API/bookings/$BOOKING_ID/payment" -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"amount": 89.90, "currency": "eur",
       "source": {"object": "card", "name": "J. Doe", "number": "4000000000000002",
                  "cvc": "123", "exp_month": 12, "exp_year": 2027, "address_country": "gb"}}' | jq .
```

Bank accounts work too (`"object": "bank_account"`, with `sort_code` etc.) and are always approved.

### 5. Manage bookings

```bash
curl -s "$API/bookings" -H "Authorization: Bearer $TOKEN" | jq .          # your bookings only
curl -s "$API/bookings/$BOOKING_ID" -H "Authorization: Bearer $TOKEN" | jq .
curl -s -X DELETE "$API/bookings/$BOOKING_ID" -H "Authorization: Bearer $TOKEN" -o /dev/null -w '%{http_code}\n'   # 204
```

### Failure flows to demo

| Flow | How |
|---|---|
| 401 | Drop the `Authorization` header |
| 401 wrong audience | Log in with a different `clientId` and use that token |
| 400 past date | `date=2020-01-01` on `/trips` |
| 400 unknown station | made-up UUID for `origin` on `/trips` |
| 400 already paid | pay a CONFIRMED booking again |
| 404 expiry | create a booking, don't pay, wait an hour (or edit the state's `expiresAt` in WireMock Cloud) — unpaid holds vanish; paid ones don't |
| 500 chaos | toggle a random-failure chaos setting on any domain mock in the WireMock Cloud UI, call the matching endpoint, toggle it off |
| user isolation | get a token with a different `email`, then try to `GET` the first user's booking → 404 |

## Postman

Import both files from [`postman/`](postman/):

1. `train-travel.postman_environment.json` (select it)
2. `train-travel.postman_collection.json`

The collection's first two requests script the same login → token exchange (capturing `id_token`
automatically); every later request sends it as a bearer token. Run the collection top to bottom to walk
the whole journey.

## CI with Jenkins

The [`Jenkinsfile`](Jenkinsfile) runs the Postman collection against the gateway in CI. The
[WireMock Cloud Jenkins plugin](https://github.com/wiremock-inc/wiremock-cloud-jenkins-plugin) creates a WireMock Cloud
environment for each build from [`.wiremock/`](.wiremock/), renders the environment's mock URLs into the gateway's
config with [`ci/application.yml.hbs`](ci/application.yml.hbs), and deletes the environment afterwards.
[`ci/postman.sh`](ci/postman.sh) starts the gateway and runs the collection with newman.

To try it, boot Jenkins in Docker with the plugin installed and a `train-travel` job that builds the Jenkinsfile:

```bash
cp jenkins/.env.example jenkins/.env   # and set WIREMOCK_API_TOKEN
jenkins/up.sh                          # http://localhost:8080, admin / admin
jenkins/down.sh
```

The script downloads the plugin's latest GitHub release with `gh`, so `gh` must be logged in with access to
wiremock-inc. The job clones the current branch from GitHub, so push it first. See [`jenkins/up.sh`](jenkins/up.sh)
for the other settings, including installing a local plugin build or CLI JAR.

## Resetting the demo

Bookings accumulate in the bookings mock's per-user state contexts. In WireMock Cloud open
`Train Travel Bookings Service` → **Reset state**, or via MCP: `reset_state` on the bookings mock. The webhook
receiver's journal can be cleared with `reset_request_journal` on the webhook mock.

## Project layout

```
src/main/kotlin/com/wiremock/traintravel/
  config/      AppProperties, SecurityConfig (JWT resource server), RestClientFactory, SoapClientConfig
  common/      Problem (RFC 7807), exception mapping, UUID v5 derivation, pagination helpers
  stations/    stations   → Stations Service (CSV data-driven mock)
  trips/       trips      → Trips Service (CSV data-driven mock)
  bookings/    bookings   → Bookings Service (stateful mock, per-user X-User-Id state)
  payments/    payment saga → PayRail SOAP gateway (unstructured mock)
  webhook/     newBooking outbound webhook → Webhook Receiver mock
contracts/                           downstream API contracts: OpenAPI descriptions + PayRail WSDL/XSD
stubs/                               hand-authored WireMock stub sets for the deployed mocks
ui/                                  SolidJS UI (Vite, :3000) - OAuth login, booking and payment flows
e2e/                                 Puppeteer browser journey against the running stack
docs/train-travel-microservices/     full specification documents
postman/                             collection + environment
.wiremock/                           mock definitions the Jenkins plugin builds each CI environment from
ci/                                  scripts and the config template the Jenkinsfile uses
jenkins/                             Docker Jenkins with the WireMock Cloud plugin, for trying the Jenkinsfile
```

## License

Licensed under the [Apache License, Version 2.0](LICENSE), except for the `ui/` directory, which retains
its original [MIT license](ui/LICENSE).
