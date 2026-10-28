#!/usr/bin/env bash
# Exercises the PayRail ProcessPayment operation (SOAP 1.1). Usage: test-requests.sh <base-url>
set -uo pipefail

BASE_URL="${1:?Usage: $0 <base-url>}"
ENDPOINT="$BASE_URL/payrail/v1"
failures=()
status=""
body=""

process_payment() {
  local payment_method="$1"
  local envelope
  envelope=$(cat <<XML
<?xml version="1.0" encoding="UTF-8"?>
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:ns2="http://payrail.example.com/v1">
  <soapenv:Body>
    <ns2:processPaymentRequest>
      <ns2:merchantId>TRAINTRAVEL-EU</ns2:merchantId>
      <ns2:merchantReference>1725ff48-ab45-4bb5-9d02-88745177dedb</ns2:merchantReference>
      <ns2:amount>89.90</ns2:amount>
      <ns2:currencyCode>EUR</ns2:currencyCode>
      $payment_method
    </ns2:processPaymentRequest>
  </soapenv:Body>
</soapenv:Envelope>
XML
)
  local out
  out=$(curl -s -X POST "$ENDPOINT" \
    -H 'Content-Type: text/xml; charset=utf-8' \
    -H 'SOAPAction: "processPayment"' \
    --data-binary "$envelope" -w '\n%{http_code}')
  status="${out##*$'\n'}"
  body="${out%$'\n'*}"
}

card() {
  echo "<ns2:paymentMethod><ns2:card><ns2:cardholderName>J. Doe</ns2:cardholderName><ns2:cardNumber>$1</ns2:cardNumber><ns2:expiryMonth>12</ns2:expiryMonth><ns2:expiryYear>2027</ns2:expiryYear><ns2:securityCode>123</ns2:securityCode></ns2:card></ns2:paymentMethod>"
}

xpath() {
  echo "$body" | xmllint --xpath "string($1)" - 2>/dev/null
}

check() {
  local description="$1" actual="$2" expected="$3"
  if [ "$actual" == "$expected" ]; then
    echo "  ✓ $description"
  else
    echo "  ✗ $description: expected '$expected', got '$actual'"
    failures+=("$description")
  fi
}

response_field() {
  xpath "//*[local-name()='processPaymentResponse']/*[local-name()='$1']"
}

fault_field() {
  xpath "//*[local-name()='Fault']/$1"
}

test_card_payments() {
  echo "Card payments"

  process_payment "$(card 4242424242424242)"
  check "approved card: status" "$status" 200
  check "approved card: response code" "$(response_field responseCode)" APPROVED
  check "approved card: masked number" "$(response_field maskedCardNumber)" "************4242"
  local transaction_id
  transaction_id="$(response_field transactionId)"
  check "approved card: has a transaction id" "$([ -n "$transaction_id" ] && echo yes)" yes

  process_payment "$(card 4000000000000002)"
  check "declined card: status" "$status" 200
  check "declined card: response code" "$(response_field responseCode)" DECLINED
  check "declined card: reason" "$(response_field declineReason)" "Card declined"
  check "declined card: new transaction id" "$([ "$(response_field transactionId)" != "$transaction_id" ] && echo yes)" yes

  process_payment "$(card 4000000000009995)"
  check "insufficient funds: response code" "$(response_field responseCode)" DECLINED
  check "insufficient funds: reason" "$(response_field declineReason)" "Insufficient funds"

  process_payment "$(card 5555555555554444)"
  check "other card: status" "$status" 200
  check "other card: response code" "$(response_field responseCode)" APPROVED

  process_payment "$(card 4000000000000119)"
  check "processing error: status" "$status" 500
  check "processing error: fault string" "$(fault_field faultstring)" "PROCESSING_ERROR: The card issuer could not be reached"
  check "processing error: fault code" "$(xpath "//*[local-name()='PayRailFault']/*[local-name()='faultCode']")" PROCESSING_ERROR
}

test_bank_account_payments() {
  echo "Bank account payments"

  process_payment "<ns2:paymentMethod><ns2:bankAccount><ns2:accountName>Jane Smith</ns2:accountName><ns2:accountNumber>12345678</ns2:accountNumber><ns2:sortCode>123456</ns2:sortCode><ns2:accountType>individual</ns2:accountType><ns2:bankName>Example Bank</ns2:bankName><ns2:countryCode>GB</ns2:countryCode></ns2:bankAccount></ns2:paymentMethod>"
  check "bank account: status" "$status" 200
  check "bank account: response code" "$(response_field responseCode)" APPROVED
}

test_validation() {
  echo "Validation"

  process_payment ""
  check "no payment method: status" "$status" 500
  check "no payment method: fault string" "$(fault_field faultstring)" "VALIDATION_ERROR: paymentMethod is required"
}

test_card_payments
test_bank_account_payments
test_validation

if [ ${#failures[@]} -gt 0 ]; then
  echo "${#failures[@]} check(s) failed:"
  printf '  - %s\n' "${failures[@]}"
  exit 1
fi
echo "All checks passed"
