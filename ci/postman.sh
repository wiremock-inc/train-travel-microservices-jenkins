#!/usr/bin/env bash
# Starts the gateway against the build's WireMock environment and runs the Postman collection with newman.
# Run by the Jenkinsfile inside wiremockEnvironment, which renders config/application.yml and sets the
# WIREMOCK_<SERVICE>_URL variables.
set -euo pipefail

# Not 8080, which Jenkins itself is on in the Docker setup
GATEWAY_PORT="${GATEWAY_PORT:-8180}"

echo "--- config/application.yml (rendered by the WireMock CLI)"
cat config/application.yml

jar="$(ls build/libs/*.jar | grep -v -- '-plain' | head -1)"
java -jar "$jar" --server.port="$GATEWAY_PORT" > build/gateway.log 2>&1 &
gateway=$!
trap 'kill "$gateway" 2>/dev/null || true' EXIT

# Waits until the gateway answers HTTP (any status)
for i in $(seq 1 120); do
  if [ "$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:$GATEWAY_PORT/")" != "000" ]; then
    break
  fi
  if ! kill -0 "$gateway" 2>/dev/null || [ "$i" = 120 ]; then
    echo "The gateway didn't start. Last lines of build/gateway.log:" >&2
    tail -40 build/gateway.log >&2
    exit 1
  fi
  sleep 1
done
echo "Gateway is up on :$GATEWAY_PORT"

newman run postman/train-travel.postman_collection.json \
  -e postman/train-travel.postman_environment.json \
  --env-var "base_url=http://localhost:$GATEWAY_PORT" \
  --env-var "auth_base=$WIREMOCK_GOOGLE_IDP_URL" \
  --reporters cli,junit --reporter-junit-export build/newman/results.xml \
  --color off
