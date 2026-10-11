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
