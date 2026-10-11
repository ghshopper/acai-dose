# Açaí Dose — orders, POS and dashboard

PHP + MySQL, runs on Hostinger shared hosting.

| Page | Who | URL |
|---|---|---|
| `index.html` | Customers: menu, car pickup, live tracking | `/` |
| `screen.html` | Staff: incoming orders (English) | `/screen` |
| `pos.html` | Staff: in-shop sales (English) | `/pos` |
| `dashboard.html` | Owner: sales, app commissions, expenses, profit | `/dashboard` |

Database settings are read from `acai-config.php` (or `config.php`) one level above `public_html`
(falls back to `api/config.php`). Copy `api/config.example.php` there and fill it in.
First run: open `/api/setup.php` to create tables and the owner account.
New columns are added automatically on the first request after an update.

## Loyalty card and Apple Wallet

- Every cup (or order — set in Dashboard → Settings) from a website order earns a stamp once staff mark it paid.
  Every 5 stamps (configurable) = one free cup, taken off the customer's next website order automatically.
- Customers see their card at `/card.html?c=…` (linked from the order tracking view and the "My card" button).
- Apple Wallet: upload the Pass Type ID certificate (.p12 + password) and Apple's WWDR G4 certificate
  in Dashboard → Settings. They are stored outside the web root in `acai-wallet/`, beside the config file.
  Apple updates passes through `/wallet/v1/...` (rewritten to `api/wallet.php`).
- Google Wallet: upload a Google Cloud service-account key (.json) and the Issuer ID in Dashboard → Settings.
  Android customers then see "Add to Google Wallet" (`api/gwallet.php`); stamps update through the Wallet REST API.
- Card artwork for both wallets is drawn by `tools/wallet_images.py`.

## Staff app (Sunmi)

`staff_app/` is a Flutter app with the orders screen and the POS, using the same API.
GitHub Actions builds it on every push to `staff_app/**`, signs it with `staff_app/keystore/acai-staff.jks`
and publishes `acai-dose-staff.apk` to the `app-latest` release. A background service rings for new
website orders until they are accepted, even when the app is closed. Build logs go to the `ci-logs` branch.
