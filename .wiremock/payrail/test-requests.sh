#!/usr/bin/env bash
# Exercises the PayRail SOAP mock: approvals, declines and faults. Usage: test-requests.sh <base-url>
set -uo pipefail
BASE="${1:?base URL required}"
failures=()

process_payment() { # $1 = paymentMethod XML, $2 = amount
  curl -s -w '\n%{http_code}' -X POST "$BASE/payrail/v1" \
    -H 'Content-Type: text/xml; charset=utf-8' -H 'SOAPAction: "processPayment"' \
    --data-binary "<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<SOAP-ENV:Envelope xmlns:SOAP-ENV=\"http://schemas.xmlsoap.org/soap/envelope/\">
  <SOAP-ENV:Body>
    <ns2:processPaymentRequest xmlns:ns2=\"http://payrail.example.com/v1\">
      <ns2:merchantId>TRAINTRAVEL-EU</ns2:merchantId>
      <ns2:merchantReference>1725ff48-ab45-4bb5-9d02-88745177dedb</ns2:merchantReference>
      <ns2:amount>$2</ns2:amount>
      <ns2:currencyCode>EUR</ns2:currencyCode>
      $1
    </ns2:processPaymentRequest>
  </SOAP-ENV:Body>
</SOAP-ENV:Envelope>"
}
card() { echo "<ns2:paymentMethod><ns2:card><ns2:cardholderName>J. Doe</ns2:cardholderName><ns2:cardNumber>$1</ns2:cardNumber><ns2:expiryMonth>12</ns2:expiryMonth><ns2:expiryYear>2027</ns2:expiryYear><ns2:securityCode>123</ns2:securityCode></ns2:card></ns2:paymentMethod>"; }
x() { echo "$1" | xmllint --xpath "string($2)" - 2>/dev/null; }
check() { # name, actual, expected
  if [ "$2" == "$3" ]; then echo "  ok   $1"; else echo "  FAIL $1: expected '$3', got '$2'"; failures+=("$1"); fi
}
call() { out="$(process_payment "$1" "$2")"; status="${out##*$'\n'}"; body="${out%$'\n'*}"; }
R="//*[local-name()='processPaymentResponse']"

cardPayments() {
  echo "card payments"
  call "$(card 4242424242424242)" 89.90
  check "approved status" "$status" 200
  check "approved code" "$(x "$body" "$R/*[local-name()='responseCode']")" APPROVED
  check "approved amount echoed" "$(x "$body" "$R/*[local-name()='authorisedAmount']")" 89.90
  check "card masked" "$(x "$body" "$R/*[local-name()='maskedCardNumber']")" "************4242"
  txn="$(x "$body" "$R/*[local-name()='transactionId']")"
  [[ "$txn" == TXN-* ]] && echo "  ok   transaction id $txn" || { echo "  FAIL transaction id '$txn'"; failures+=("txn"); }

  call "$(card 4000000000000002)" 89.90
  check "declined code" "$(x "$body" "$R/*[local-name()='responseCode']")" DECLINED
  check "declined reason" "$(x "$body" "$R/*[local-name()='declineReason']")" "Card declined by issuer"

  call "$(card 4000000000009995)" 120.00
  check "insufficient funds reason" "$(x "$body" "$R/*[local-name()='declineReason']")" "Insufficient funds"

  call "$(card 4000000000000119)" 50.00
  check "processing fault status" "$status" 500
  check "processing fault code" "$(x "$body" "//*[local-name()='PayRailFault']/*[local-name()='faultCode']")" PROCESSING_ERROR
}

bankPayments() {
  echo "bank account payments"
  call "<ns2:paymentMethod><ns2:bankAccount><ns2:accountName>Jane Smith</ns2:accountName><ns2:accountNumber>41926819</ns2:accountNumber><ns2:sortCode>200000</ns2:sortCode><ns2:accountType>individual</ns2:accountType><ns2:bankName>Starling Bank</ns2:bankName><ns2:countryCode>GB</ns2:countryCode></ns2:bankAccount></ns2:paymentMethod>" 45.00
  check "bank approved" "$(x "$body" "$R/*[local-name()='responseCode']")" APPROVED
  check "account masked" "$(x "$body" "$R/*[local-name()='maskedAccountNumber']")" "******6819"
}

validation() {
  echo "validation"
  call "" 10.00
  check "validation fault status" "$status" 500
  check "validation faultstring" "$(x "$body" "//*[local-name()='Fault']/faultstring" | cut -d: -f1)" VALIDATION
}

cardPayments; bankPayments; validation
if [ ${#failures[@]} -gt 0 ]; then echo "${#failures[@]} check(s) failed: ${failures[*]}"; exit 1; fi
echo "All checks passed"
