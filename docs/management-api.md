# Açaí Dose & Karak Dose — Management System Integration API

This guide is for the developer connecting the management system to the sales system of both shops. It covers two channels that carry the same data:

1. **Pull (REST API):** your system reads sales, expenses and daily summaries with a secret key.
2. **Push (Webhooks):** we POST every change (sale, cancellation, expense…) to your URL as it happens, signed with HMAC-SHA256.

Use both: webhooks for real time, and the event feed (`ext_events`) to catch up anything missed.

## Basics

| | Açaí Dose | Karak Dose |
|---|---|---|
| Base URL | `https://order.acaiee.com/api/api.php` | `https://order.acaiee.com/karak/api/api.php` |
| `shop` value | `acai_dose` | `karak_dose` |

- Each shop has **its own key, webhook URL and signing secret**. The owner generates them in the owner app: More → ربط نظام الإدارة (switch shop to set up the other one).
- The action goes in the query string: `?a=ext_orders&from=2026-11-01&to=2026-11-07`
- Auth header: `X-Api-Key: dose_…` (or `Authorization: Bearer dose_…`). Never put the key in the URL.
- Currency OMR, 3 decimals. Times are Asia/Muscat (UTC+4), format `YYYY-MM-DD HH:MM:SS`. Dates `YYYY-MM-DD`.
- Errors: JSON `{"error":"code"}` with an HTTP status. `401 bad_key`, `429 too_many` (after repeated bad keys), `400 range_too_long`.
- All endpoints are read-only (GET).

## Endpoints

### `ext_ping`
Checks the key. → `{"ok":true,"shop":"acai_dose","time":"…","timezone":"Asia/Muscat","currency":"OMR"}`

### `ext_events` — change feed (recommended for sync)
`?a=ext_events&after=<last event_id you processed>&limit=200` (limit max 1000)

Returns events in order, the same objects the webhook sends:
```json
{"shop":"acai_dose","events":[{"event_id":41,"shop":"acai_dose","type":"order.created","created_at":"2026-11-08 15:22:05","data":{…}}],
 "next_after":41,"more":false}
```
Save `next_after` and call again while `more` is true. Events are kept for 60 days and only from the moment the link was switched on. For older history use the endpoints below.

### `ext_orders` — orders with items
`?a=ext_orders&from=YYYY-MM-DD&to=YYYY-MM-DD&after=<id>&limit=500` (range up to 370 days; page with `after` = `next_after`)

### `ext_app_sales` — delivery-app daily totals entered by the owner
Same parameters. Some app sales are entered as one total per day instead of per order.

### `ext_expenses`
Same parameters.

### `ext_summary` — day-by-day numbers + period totals
`?a=ext_summary&from=…&to=…` (range up to 92 days) → `{"days":[DaySummary…],"totals":{…}}`

### `ext_flush`
Only needed if you want a cron job to push waiting webhooks; normally not used.

## Objects

**Order**
```json
{"id":1520,"ref":"0811-07","date":"2026-11-08","created_at":"2026-11-08 09:14:02","updated_at":"2026-11-08 09:14:02",
 "source":"pos","status":"done","counts_in_sales":true,
 "payment":"talabat","payment_name":"Talabat",
 "total":6.6,"commission":1.32,"net":5.28,"discount":0,"free_cups":0,"orders":1,
 "items":[{"product_id":3,"name_en":"Açaí Smoothie","name_ar":"آساي سموذي","qty":2,"unit_price":3.3,"line_total":6.6}]}
```
- `source`: `pos` (till), `web` (online order page), `curb` (taken at the car).
- `status`: `new`, `preparing`, `ready`, `done`, `cancelled`. Use `counts_in_sales` (false only when cancelled).
- `payment`: `cash`, `card`, `talabat`, `tmdone`, `snoonu`, `khedmah`, or `null` for an online order not handed over yet.
- `commission`: the delivery app's cut, fixed at sale time. `net = total − commission`.
- `discount` / `free_cups`: loyalty free cup used on this order.
- `orders`: more than 1 only for old sales imported from Excel as daily totals.
- Items may have `note` (e.g. "less sugar") and `custom: true` (an item the cashier typed by hand).
- `id` is unique per shop. `ref` is the number printed on the receipt and resets daily.

**AppSale**
```json
{"id":88,"date":"2026-11-07","channel":"talabat","channel_name":"Talabat","gross":42.5,"commission_pct":20,"commission":8.5,"net":34,"orders":13,"note":"","created_at":"…"}
```

**Expense**
```json
{"id":301,"date":"2026-11-08","category":"إيجار","amount":250,"one_off":false,"note":"","created_at":"…","paid_from":"bank","entered_at":"owner"}
```
- `paid_from`: `cash` (paid from the shop's till) or `bank` (from the company account).
- `entered_at`: `pos` (staff at the till; note starts with `POS · <staff name>`) or `owner`.
`one_off` is true for equipment, fit-out and décor (categories containing معدات / أجهزة / تأسيس / ديكور). Everything else is running cost. Category names are Arabic and set by the owner.

**DaySummary**
```json
{"date":"2026-11-07","orders":24,"cancelled":1,"sales":61.2,"by_payment":{"cash":20.1,"card":25.6,"talabat":15.5},
 "commission":3.1,"net_sales":58.1,"expenses_total":12,"expenses_running":12,"expenses_one_off":0,
 "expenses":{"مواد خام (آساي وفواكه)":12},"net":46.1}
```
`by_payment` may include `unpaid` (online orders not handed over).

## Webhooks

The owner enters your HTTPS URL in the app. A signing secret (`whsec_…`) is shown once; keep it on your side.

**Request:** `POST` to your URL with JSON body = one event envelope:
```json
{"event_id":41,"shop":"karak_dose","type":"expense.created","created_at":"2026-11-08 15:22:05","data":{…Expense…}}
```
Headers:
```
Content-Type: application/json
X-Dose-Event: expense.created
X-Dose-Event-Id: 41
X-Dose-Shop: karak_dose
X-Dose-Timestamp: 1794137525
X-Dose-Signature: sha256=<hex>
```

**Event types**

| type | data | when |
|---|---|---|
| `order.created` | Order | new sale at the till, online order, car order |
| `order.updated` | Order (full, latest) | status change, paid, cancelled / voided |
| `app_sale.created` | AppSale | owner entered an app daily total |
| `app_sale.deleted` | AppSale (as it was) | owner deleted it |
| `expense.created` | Expense | new expense (including stock purchases saved as expenses) |
| `expense.updated` | Expense (latest) | owner edited date / category / amount |
| `expense.deleted` | Expense (as it was) | owner deleted it |
| `day.closed` | DaySummary | once per day after midnight, for the previous day |
| `sales.reset` | `{"all":bool,"from":date,"to":date,"expenses":bool}` | owner wiped sales (and maybe expenses) for a period; delete them on your side |
| `ping` | `{"message":"test"}` | the owner pressed "test" in the app (`event_id` 0) |

**Verify the signature** (required): HMAC-SHA256 over `timestamp + "." + raw body` with the secret, compare to the header. Reject if the timestamp is more than 5 minutes old.
```php
$body = file_get_contents('php://input');
$ts   = $_SERVER['HTTP_X_DOSE_TIMESTAMP'] ?? '';
$sig  = 'sha256=' . hash_hmac('sha256', $ts . '.' . $body, getenv('DOSE_WEBHOOK_SECRET'));
if (!hash_equals($sig, $_SERVER['HTTP_X_DOSE_SIGNATURE'] ?? '') || abs(time() - (int)$ts) > 300) { http_response_code(401); exit; }
$e = json_decode($body, true);
// upsert by ($e['shop'], $e['data']['id']); skip if event_id already processed
http_response_code(200);
```
```python
import hmac, hashlib, time
sig = 'sha256=' + hmac.new(secret.encode(), ts.encode() + b'.' + raw_body, hashlib.sha256).hexdigest()
ok = hmac.compare_digest(sig, request.headers['X-Dose-Signature']) and abs(time.time() - int(ts)) < 300
```
```js
// Node (Express with raw body)
const sig = 'sha256=' + crypto.createHmac('sha256', SECRET).update(ts + '.' + rawBody).digest('hex');
const got = req.get('X-Dose-Signature') || '';
if (sig.length !== got.length || !crypto.timingSafeEqual(Buffer.from(sig), Buffer.from(got))) return res.sendStatus(401);
```

**Delivery rules**
- Answer `2xx` within 5 seconds. Do heavy work after replying.
- Anything else, or no answer, is retried with back-off (1 min, 2, 4 … up to every 6 hours), up to 30 tries.
- Events are sent **in order**. A failing event holds back the ones after it until it succeeds.
- Delivery is **at least once**: the same `event_id` can arrive twice. De-duplicate by `(shop, event_id)`.
- Treat records as **upserts** keyed by `(shop, data.id)`. `*.updated` always carries the full latest record.
- If you were down for long, read `ext_events?after=<last id>` to catch up.

## Suggested setup

1. Owner generates a key and enters your webhook URL (per shop), then sends you: base URL, key, secret.
2. Initial load: `ext_orders`, `ext_app_sales`, `ext_expenses` for the history you need, or `ext_summary` if daily totals are enough.
3. From then on: webhooks in real time, plus a call to `ext_events` every few minutes (or hourly) as a safety net.
4. Map `shop` to the branch / cost centre in your system, and `payment` / `channel` to your accounts.

Questions about the data go to the owner.
