#!/usr/bin/env bash
# Exercises the newBooking webhook receiver. Usage: test-requests.sh <base-url>
set -uo pipefail

BASE_URL="${1:?Usage: $0 <base-url>}"
failures=()

check() {
  local description="$1" actual="$2" expected="$3"
  if [ "$actual" == "$expected" ]; then
    echo "  ✓ $description"
  else
    echo "  ✗ $description: expected '$expected', got '$actual'"
    failures+=("$description")
  fi
}

post_webhook() {
  curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE_URL/new-booking" \
    -H 'Content-Type: application/json' --data-binary "$1"
}

test_new_booking() {
  echo "newBooking delivery"

  local status
  status=$(post_webhook '{
    "id": "1725ff48-ab45-4bb5-9d02-88745177dedb",
    "trip_id": "efdbb9d1-02c2-4bc3-afb7-6788d8782b1e",
    "passenger_name": "Jane Smith",
    "has_bicycle": true,
    "has_dog": false,
    "links": { "self": "http://localhost:8080/bookings/1725ff48-ab45-4bb5-9d02-88745177dedb" }
  }')
  check "booking payload accepted" "$status" 200

  status=$(post_webhook '{ "passenger_name": "No Id" }')
  check "payload without a booking id is not accepted" "$status" 404
}

test_new_booking

if [ ${#failures[@]} -gt 0 ]; then
  echo "${#failures[@]} check(s) failed:"
  printf '  - %s\n' "${failures[@]}"
  exit 1
fi
echo "All checks passed"
