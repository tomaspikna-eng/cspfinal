# CardPay readiness — Connect Sports Pro

CardPay is implemented but intentionally disabled until merchant onboarding is complete.

Required Supabase Edge secrets:
- `CARDPAY_ENABLED=true`
- `CARDPAY_MID=<merchant id>`
- `CARDPAY_HMAC_KEY_HEX=<128 hex chars / 64-byte security key>`
- `CARDPAY_APP_RETURN_URL=https://connectsportspro.com/cennik/`
- optional `CARDPAY_GATEWAY_URL` (defaults to the official CardPay endpoint)

Runtime:
1. Authenticated customer selects PRO / PRO+ / ULTRA and monthly or annual billing.
2. `cardpay-checkout` creates a server-side order and signs the CardPay request.
3. Browser POSTs the signed fields to CardPay.
4. `cardpay-return` verifies HMAC and ECDSA before any entitlement is changed.
5. A verified `RES=OK` activates/extends the CSP subscription and updates the plan idempotently.

Products are seeded inactive:
- PRO monthly 5.99 EUR / annual 59.90 EUR
- PRO+ monthly 9.99 EUR / annual 99.90 EUR
- ULTRA monthly 24.90 EUR / annual 249.00 EUR

Before launch:
- activate final rows in `csp_payment_products`;
- set Edge secrets;
- complete Tatra banka sandbox/acceptance tests;
- confirm expiry/downgrade lifecycle;
- for automatic recurring card charges use ComfortPay; the current CardPay layer is ready for initial purchase/manual renewal.

No merchant key is stored in GitHub or browser code.
