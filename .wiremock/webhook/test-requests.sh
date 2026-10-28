#!/usr/bin/env bash
# Exercises the newBooking webhook receiver mock. Usage: test-requests.sh <base-url>
set -uo pipefail
BASE="${1:?base URL required}"
failures=()
post() { curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE/new-booking" -H 'Content-Type: application/json' --data-binary "$1"; }
check() { if [ "$2" == "$3" ]; then echo "  ok   $1"; else echo "  FAIL $1: expected '$3', got '$2'"; failures+=("$1"); fi; }
echo "newBooking delivery"
check "booking accepted" "$(post '{"id":"1725ff48-ab45-4bb5-9d02-88745177dedb","trip_id":"efdbb9d1-02c2-4bc3-afb7-6788d8782b1e","passenger_name":"John Doe","has_bicycle":true,"has_dog":true,"links":{"self":"http://localhost:8080/bookings/1725ff48-ab45-4bb5-9d02-88745177dedb"}}')" 200
check "non-booking rejected" "$(post '{"hello":"world"}')" 400
if [ ${#failures[@]} -gt 0 ]; then echo "${#failures[@]} check(s) failed: ${failures[*]}"; exit 1; fi
echo "All checks passed"
