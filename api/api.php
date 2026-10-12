<?php
declare(strict_types=1);
require __DIR__ . '/lib.php';
require __DIR__ . '/loyalty.php';

header('X-Content-Type-Options: nosniff');
header('Referrer-Policy: same-origin');

$a = $_GET['a'] ?? '';
$method = $_SERVER['REQUEST_METHOD'];
// State-changing calls must be JSON POSTs (blocks cross-site form posts).
if ($method === 'POST' && stripos($_SERVER['CONTENT_TYPE'] ?? '', 'application/json') !== 0) fail('bad_request');
$in = $method === 'POST' ? body() : [];
$post = fn() => $method === 'POST' || fail('method', 405);

const CHANNELS = ['talabat', 'snoonu', 'khedmah'];
const STATUSES = ['new', 'preparing', 'ready', 'done', 'cancelled'];
const PAYMENTS = ['cash', 'card', 'talabat', 'snoonu', 'khedmah'];

function valid_date($d): string {
    if (!is_string($d) || !preg_match('/^\d{4}-\d{2}-\d{2}$/', $d) || !strtotime($d)) fail('bad_date');
    return $d;
}
/** Display number: day + month + daily sequence, e.g. 11 Oct order 7 -> 1110-07 */
function order_ref(string $day, int $no): string { return date('dm', strtotime($day)) . '-' . str_pad((string)$no, 2, '0', STR_PAD_LEFT); }
function order_row(array $o): array {
    $o['id'] = (int)$o['id']; $o['order_no'] = (int)$o['order_no'];
    $o['ref'] = order_ref($o['day'] ?? date('Y-m-d'), $o['order_no']);
    $o['total'] = (float)$o['total']; $o['items'] = json_decode($o['items'], true) ?: [];
    if (array_key_exists('commission', $o)) $o['commission'] = (float)($o['commission'] ?? 0);
    if (array_key_exists('free_cups', $o)) { $o['free_cups'] = (int)$o['free_cups']; $o['discount'] = (float)($o['discount'] ?? 0); }
    if (array_key_exists('n_orders', $o)) $o['n_orders'] = $o['n_orders'] === null ? null : (int)$o['n_orders'];
    unset($o['token']);
    return $o;
}
/** Validates [{product_id, qty}] against the menu; returns [lines, total]. */
function price_items($items): array {
    if (!is_array($items) || !count($items) || count($items) > 15) fail('invalid_items');
    $lines = []; $total = 0.0;
    foreach ($items as $it) {
        $pid = (int)($it['product_id'] ?? 0); $qty = (int)($it['qty'] ?? 0);
        if ($qty < 1 || $qty > 50) fail('invalid_qty');
        $p = q('SELECT id, name_ar, name_en, price FROM products WHERE id = ? AND active = 1', [$pid])->fetch();
        if (!$p) fail('invalid_product');
        $lines[] = ['product_id' => (int)$p['id'], 'name_ar' => $p['name_ar'], 'name_en' => $p['name_en'], 'price' => (float)$p['price'], 'qty' => $qty];
        $total += (float)$p['price'] * $qty;
    }
    return [$lines, money($total)];
}
/** Inserts an order with the next daily number; returns that number. */
function insert_order(array $f, ?string $day = null): int {
    $day = $day ?: date('Y-m-d');
    $pdo = db(); $own = !$pdo->inTransaction(); if ($own) $pdo->beginTransaction();
    try {
        $row = q('SELECT last_no FROM day_counters WHERE day = ?' . (is_mysql() ? ' FOR UPDATE' : ''), [$day])->fetch();
        if ($row) { $no = (int)$row['last_no'] + 1; q('UPDATE day_counters SET last_no = ? WHERE day = ?', [$no, $day]); }
        else { $no = 1; q('INSERT INTO day_counters (day, last_no) VALUES (?, 1)', [$day]); }
        $f += ['order_no' => $no, 'day' => $day, 'created_at' => now(), 'updated_at' => now()];
        $cols = array_keys($f);
        q('INSERT INTO orders (' . implode(',', $cols) . ') VALUES (' . implode(',', array_fill(0, count($cols), '?')) . ')', array_values($f));
        if ($own) $pdo->commit();
    } catch (Throwable $e) { if ($own) $pdo->rollBack(); throw $e; }
    return $no;
}

try {
ensure_schema();
switch ($a) {

// ---------------- public ----------------
case 'menu':
    out(array_map(fn($p) => ['id' => (int)$p['id'], 'name_ar' => $p['name_ar'], 'name_en' => $p['name_en'],
        'img' => $p['img'], 'price' => (float)$p['price']],
        q('SELECT * FROM products WHERE active = 1 ORDER BY sort, id')->fetchAll()));

case 'shop_info':    // public: how customers can reach the shop
    out(['whatsapp' => setting('shop_whatsapp')]);

case 'place_order':
    $post();
    rate_limit('order', 15, 600);
    $name = clean($in['name'] ?? '', 60);
    $phone = preg_replace('/[^0-9+]/', '', (string)($in['phone'] ?? ''));
    $car = clean($in['car_plate'] ?? '', 20);
    $carDesc = clean($in['car_desc'] ?? '', 40);
    $pickup = clean($in['pickup'] ?? '', 10);
    $notes = clean($in['notes'] ?? '', 300);
    if (mb_strlen($name) < 2) fail('invalid_name');
    if (!preg_match('/^\+968[279]\d{7}$/', $phone)) fail('invalid_phone');
    if (mb_strlen($car) < 1) fail('invalid_car');
    if ($pickup !== 'ASAP' && !preg_match('/^([01]\d|2[0-3]):[0-5]\d$/', $pickup)) fail('invalid_pickup');
    if ((int)date('G') < 7) fail('closed');
    [$lines, $total] = price_items($in['items'] ?? null);
    // Loyalty: a free cup waiting on this phone is taken off the dearest cup in the order
    $free = 0; $discount = 0.0;
    $ls = loyalty_state($phone);
    if ($ls['on'] && $ls['free'] > 0) {
        $free = 1; $discount = max(array_map(fn($l) => $l['price'], $lines)); $total = money($total - $discount);
    }
    $token = bin2hex(random_bytes(16));
    $no = insert_order([
        'source' => 'web', 'customer_name' => $name, 'phone' => $phone, 'car_plate' => $car, 'car_desc' => $carDesc ?: null,
        'pickup_time' => $pickup, 'notes' => $notes ?: null, 'items' => json_encode($lines, JSON_UNESCAPED_UNICODE),
        'total' => $total, 'status' => 'new', 'token' => $token, 'free_cups' => $free, 'discount' => money($discount),
    ]);
    save_customer($phone, $name, $car, $carDesc, isset($in['offers']) ? !empty($in['offers']) : null);
    if ($free) loyalty_changed($phone);
    $card = q('SELECT card_token FROM customers WHERE phone = ?', [$phone])->fetch();
    out(['order_no' => $no, 'ref' => order_ref(date('Y-m-d'), $no), 'total' => $total, 'token' => $token,
         'free_cups' => $free, 'discount' => money($discount), 'card' => $card['card_token'] ?? null]);

case 'track':     // customer polls their own order by secret token
    $t = (string)($_GET['t'] ?? '');
    if (!preg_match('/^[a-f0-9]{32}$/', $t)) fail('not_found', 404);
    $o = q('SELECT order_no, status, total, pickup_time, car_plate, arrived_at, day, phone, free_cups, discount FROM orders WHERE token = ?', [$t])->fetch();
    if (!$o) fail('not_found', 404);
    $c = q('SELECT * FROM customers WHERE phone = ?', [$o['phone']])->fetch();
    require_once __DIR__ . '/gwallet_lib.php';
    out(['order_no' => (int)$o['order_no'], 'ref' => order_ref($o['day'], (int)$o['order_no']), 'status' => $o['status'], 'total' => (float)$o['total'], 'pickup_time' => $o['pickup_time'],
         'car_plate' => $o['car_plate'], 'arrived' => (bool)$o['arrived_at'], 'today' => $o['day'] === date('Y-m-d'),
         'free_cups' => (int)$o['free_cups'], 'discount' => (float)$o['discount'], 'loyalty' => $c ? card_info($c) + ['wallet' => wallet_ready(), 'gwallet' => gw_ready()] : null]);

case 'card':      // customer's loyalty card, by its secret link
    $c = (string)($_GET['c'] ?? '');
    if (!preg_match('/^[a-f0-9]{32}$/', $c)) fail('not_found', 404);
    $row = q('SELECT * FROM customers WHERE card_token = ?', [$c])->fetch();
    if (!$row) fail('not_found', 404);
    require_once __DIR__ . '/gwallet_lib.php';
    out(card_info($row) + ['wallet' => wallet_ready(), 'gwallet' => gw_ready()]);

case 'arrived':   // customer taps "I've arrived"
    $post();
    rate_limit('arrived', 20, 600);
    $t = (string)($in['t'] ?? '');
    if (!preg_match('/^[a-f0-9]{32}$/', $t)) fail('not_found', 404);
    q("UPDATE orders SET arrived_at = ?, updated_at = ? WHERE token = ? AND arrived_at IS NULL AND status IN ('new','preparing','ready')", [now(), now(), $t]);
    out(['ok' => true]);

// ---------------- auth ----------------
case 'login':
    $post();
    rate_limit('login', 10, 900);
    $u = q('SELECT * FROM users WHERE username = ? AND active = 1', [clean($in['username'] ?? '', 60)])->fetch();
    if (!$u || !password_verify((string)($in['password'] ?? ''), $u['pass_hash'])) fail('bad_login', 401);
    start_session(); session_regenerate_id(true); $_SESSION['uid'] = (int)$u['id'];
    out(['username' => $u['username'], 'role' => $u['role']]);

case 'logout':
    $post(); start_session(); $_SESSION = []; session_destroy(); out(['ok' => true]);

case 'me':
    $u = user(); out($u ? ['username' => $u['username'], 'role' => $u['role']] : null);

// ---------------- staff: orders screen ----------------
case 'active_orders':
    need('staff');
    $since = date('Y-m-d H:i:s', time() - 36 * 3600);
    $rows = q("SELECT * FROM orders WHERE source = 'web' AND status IN ('new','preparing','ready') AND created_at >= ? ORDER BY id", [$since])->fetchAll();
    out(array_map(fn($o) => order_row($o) + ['track' => $o['token']], $rows));   // staff can send the customer their tracking link

case 'web_today':   // staff phones: today's website orders that are finished (handed over or cancelled)
    need('staff');
    $rows = q("SELECT * FROM orders WHERE source = 'web' AND day = ? AND status IN ('done','cancelled') ORDER BY updated_at DESC, id DESC", [date('Y-m-d')])->fetchAll();
    out(array_map(fn($o) => order_row($o) + ['track' => $o['token']], $rows));

case 'order_status':
    $post(); need('staff');
    $st = $in['status'] ?? '';
    if (!in_array($st, STATUSES, true)) fail('bad_status');
    $pay = in_array($in['payment'] ?? null, ['cash', 'card'], true) ? $in['payment'] : null;
    $oid = (int)($in['id'] ?? 0);
    if ($st === 'done' && $pay) q('UPDATE orders SET status = ?, payment = ?, updated_at = ? WHERE id = ?', [$st, $pay, now(), $oid]);
    else q('UPDATE orders SET status = ?, updated_at = ? WHERE id = ?', [$st, now(), $oid]);
    // Paid or cancelled website orders change the customer's stamps
    if ($st === 'done' || $st === 'cancelled') {
        $o = q("SELECT phone FROM orders WHERE id = ?", [$oid])->fetch();
        if ($o) loyalty_changed((string)$o['phone']);
    }
    out(['ok' => true]);

// ---------------- staff: POS ----------------
case 'pos_sale':
    $post(); $u = need('staff');
    $pay = $in['payment'] ?? '';
    if (!in_array($pay, PAYMENTS, true)) fail('bad_payment');
    [$lines, $total] = price_items($in['items'] ?? null);
    // App orders: snapshot today's commission so later rate changes don't rewrite history
    $commission = 0.0;
    if (in_array($pay, CHANNELS, true)) {
        $pct = (float)(q('SELECT pct FROM channel_commissions WHERE channel = ?', [$pay])->fetch()['pct'] ?? 0);
        $commission = money($total * $pct / 100);
    }
    // Optional customer mobile (shop sales only): earns loyalty stamps and can use a free cup
    $cphone = ''; $free = 0; $discount = 0.0;
    if (!empty($in['phone']) && in_array($pay, ['cash', 'card'], true)) {
        $cphone = norm_phone($in['phone']); if ($cphone === '') fail('invalid_phone');
        if (!empty($in['use_free'])) {
            $ls = loyalty_state($cphone);
            if (!$ls['on'] || $ls['free'] < 1) fail('no_free_cup');
            $free = 1; $discount = max(array_map(fn($l) => $l['price'], $lines)); $total = money($total - $discount);
        }
    }
    $no = insert_order([
        'source' => 'pos', 'customer_name' => in_array($pay, CHANNELS, true) ? ucfirst($pay) : 'Walk-in', 'phone' => $cphone,
        'items' => json_encode($lines, JSON_UNESCAPED_UNICODE), 'total' => $total, 'status' => 'done', 'payment' => $pay,
        'commission' => $commission, 'created_by' => (int)$u['id'], 'free_cups' => $free, 'discount' => money($discount),
    ]);
    $loy = null;
    if ($cphone !== '') { save_customer($cphone, clean((string)($in['name'] ?? ''), 60)); loyalty_changed($cphone); $loy = loyalty_state($cphone); }
    out(['order_no' => $no, 'ref' => order_ref(date('Y-m-d'), $no), 'total' => $total, 'free_cups' => $free, 'loyalty' => $loy]);

case 'pos_customer':  // staff: loyalty status for a mobile typed at the till
    need('staff');
    $ph = norm_phone($_GET['phone'] ?? ''); if ($ph === '') fail('invalid_phone');
    $c = q('SELECT name FROM customers WHERE phone = ?', [$ph])->fetch();
    out(['found' => (bool)$c, 'name' => $c['name'] ?? ''] + loyalty_state($ph));

case 'pos_today':
    need('staff');
    $rows = q("SELECT o.id, o.order_no, o.day, o.created_at, o.items, o.total, o.status, o.payment, o.commission, o.source, o.phone, o.free_cups, o.discount, u.username AS by_user
               FROM orders o LEFT JOIN users u ON u.id = o.created_by
               WHERE o.day = ? AND o.source = 'pos' ORDER BY o.id DESC", [date('Y-m-d')])->fetchAll();
    out(array_map('order_row', $rows));

case 'pos_void':
    $post(); $u = need('staff');
    $o = q("SELECT id, created_at, created_by FROM orders WHERE id = ? AND source = 'pos' AND status = 'done'", [(int)($in['id'] ?? 0)])->fetch();
    if (!$o) fail('not_found', 404);
    if ($u['role'] !== 'owner' && ((int)$o['created_by'] !== (int)$u['id'] || strtotime($o['created_at']) < time() - 15 * 60)) fail('void_window');
    q("UPDATE orders SET status = 'cancelled', updated_at = ? WHERE id = ?", [now(), (int)$o['id']]);
    $ph = q('SELECT phone FROM orders WHERE id = ?', [(int)$o['id']])->fetch()['phone'] ?? '';
    if ($ph !== '') loyalty_changed((string)$ph);
    out(['ok' => true]);

// ---------------- owner: dashboard ----------------
case 'range':
    need('owner');
    $from = valid_date($_GET['from'] ?? ''); $to = valid_date($_GET['to'] ?? '');
    $orders = q('SELECT id, order_no, day, created_at, customer_name, phone, car_plate, items, total, status, source, payment, commission, n_orders, free_cups, discount FROM orders WHERE day BETWEEN ? AND ? ORDER BY id DESC', [$from, $to])->fetchAll();
    $apps = q('SELECT * FROM channel_sales WHERE sale_date BETWEEN ? AND ? ORDER BY sale_date DESC, id DESC', [$from, $to])->fetchAll();
    $exps = q('SELECT * FROM expenses WHERE expense_date BETWEEN ? AND ? ORDER BY expense_date DESC, id DESC', [$from, $to])->fetchAll();
    foreach ($apps as &$r) { foreach (['gross', 'commission', 'commission_pct'] as $k) $r[$k] = (float)$r[$k]; $r['id'] = (int)$r['id']; $r['orders_count'] = $r['orders_count'] === null ? null : (int)$r['orders_count']; }
    foreach ($exps as &$r) { $r['amount'] = (float)$r['amount']; $r['id'] = (int)$r['id']; }
    out(['orders' => array_map('order_row', $orders), 'apps' => $apps, 'exps' => $exps]);

case 'add_sale':
    $post(); need('owner');
    $ch = $in['channel'] ?? ''; if (!in_array($ch, CHANNELS, true)) fail('bad_channel');
    $gross = (float)($in['gross'] ?? -1); if ($gross < 0) fail('bad_amount');
    $pct = (float)($in['commission_pct'] ?? 0); if ($pct < 0 || $pct > 100) fail('bad_pct');
    $cnt = isset($in['orders_count']) && $in['orders_count'] !== null && $in['orders_count'] !== '' ? max(0, (int)$in['orders_count']) : null;
    q('INSERT INTO channel_sales (sale_date, channel, gross, commission_pct, commission, orders_count, note, created_at) VALUES (?,?,?,?,?,?,?,?)',
      [valid_date($in['sale_date'] ?? ''), $ch, money($gross), $pct, money($gross * $pct / 100), $cnt, clean($in['note'] ?? '', 120) ?: null, now()]);
    out(['ok' => true]);

case 'add_expense':
    $post(); need('owner');
    $amt = (float)($in['amount'] ?? -1); if ($amt < 0) fail('bad_amount');
    $cat = clean($in['category'] ?? '', 60); if ($cat === '') fail('bad_category');
    q('INSERT INTO expenses (expense_date, category, amount, note, created_at) VALUES (?,?,?,?,?)',
      [valid_date($in['expense_date'] ?? ''), $cat, money($amt), clean($in['note'] ?? '', 120) ?: null, now()]);
    out(['ok' => true]);

case 'delete':
    $post(); need('owner');
    $t = ['sale' => 'channel_sales', 'expense' => 'expenses'][$in['type'] ?? ''] ?? fail('bad_type');
    q("DELETE FROM $t WHERE id = ?", [(int)($in['id'] ?? 0)]);
    out(['ok' => true]);

case 'reset_sales':   // owner wipes sales to start fresh (menu, prices, staff and settings stay)
    $post(); $u = need('owner');
    rate_limit('login', 10, 900);
    $row = q('SELECT pass_hash FROM users WHERE id = ?', [(int)$u['id']])->fetch();
    if (!$row || !password_verify((string)($in['password'] ?? ''), $row['pass_hash'])) fail('bad_password');
    if (($in['confirm'] ?? '') !== 'RESET') fail('bad_confirm');
    $pdo = db(); $pdo->beginTransaction();
    try {
        if (!empty($in['all'])) {
            foreach (['orders', 'day_counters', 'channel_sales'] as $t) q("DELETE FROM $t");
            if (!empty($in['expenses'])) q('DELETE FROM expenses');
        } else {
            $f = valid_date($in['from'] ?? ''); $t2 = valid_date($in['to'] ?? '');
            if ($f > $t2) [$f, $t2] = [$t2, $f];
            q('DELETE FROM orders WHERE day BETWEEN ? AND ?', [$f, $t2]);
            q('DELETE FROM day_counters WHERE day BETWEEN ? AND ?', [$f, $t2]);
            q('DELETE FROM channel_sales WHERE sale_date BETWEEN ? AND ?', [$f, $t2]);
            if (!empty($in['expenses'])) q('DELETE FROM expenses WHERE expense_date BETWEEN ? AND ?', [$f, $t2]);
        }
        $pdo->commit();
    } catch (Throwable $e) { $pdo->rollBack(); throw $e; }
    out(['ok' => true]);

case 'import_sales':  // owner loads old sales from the Excel template, all rows or none
    $post(); need('owner');
    $rows = $in['rows'] ?? null;
    if (!is_array($rows) || !count($rows) || count($rows) > 3000) fail('bad_rows');
    $pct = []; foreach (q('SELECT channel, pct FROM channel_commissions')->fetchAll() as $r) $pct[$r['channel']] = (float)$r['pct'];
    $prods = q('SELECT id, name_ar, name_en, price FROM products')->fetchAll();
    $today = date('Y-m-d'); $prepared = [];
    foreach (array_values($rows) as $i => $r) {
        $line = $i + 1;
        $d = $r['date'] ?? '';
        if (!is_string($d) || !preg_match('/^\d{4}-\d{2}-\d{2}$/', $d) || !strtotime($d) || $d > $today || $d < '2020-01-01') fail("row_$line:bad_date");
        $pay = $r['payment'] ?? ''; if (!in_array($pay, PAYMENTS, true)) fail("row_$line:bad_payment");
        $amt = (float)($r['amount'] ?? 0); if ($amt <= 0 || $amt > 100000) fail("row_$line:bad_amount");
        $n = isset($r['orders']) && $r['orders'] !== '' && $r['orders'] !== null ? (int)$r['orders'] : 1;
        if ($n < 1 || $n > 10000) fail("row_$line:bad_orders");
        $items = [];
        if (!empty($r['product_id'])) {
            $p = null; foreach ($prods as $x) if ((int)$x['id'] === (int)$r['product_id']) $p = $x;
            if (!$p) fail("row_$line:bad_product");
            $qty = (int)($r['qty'] ?? 0); if ($qty < 1 || $qty > 100000) fail("row_$line:bad_qty");
            $items[] = ['product_id' => (int)$p['id'], 'name_ar' => $p['name_ar'], 'name_en' => $p['name_en'], 'price' => (float)$p['price'], 'qty' => $qty];
        }
        $c = isset($r['commission_pct']) && $r['commission_pct'] !== '' && $r['commission_pct'] !== null ? (float)$r['commission_pct'] : ($pct[$pay] ?? 0);
        if ($c < 0 || $c > 100) fail("row_$line:bad_pct");
        $prepared[] = [$d, [
            'source' => 'pos', 'customer_name' => 'Imported', 'phone' => '', 'notes' => clean($r['note'] ?? '', 300) ?: null,
            'items' => json_encode($items, JSON_UNESCAPED_UNICODE), 'total' => money($amt), 'status' => 'done', 'payment' => $pay,
            'commission' => in_array($pay, CHANNELS, true) ? money($amt * $c / 100) : 0, 'n_orders' => $n,
            'created_at' => $d . ' 12:00:00', 'updated_at' => now(),
        ]];
    }
    $pdo = db(); $pdo->beginTransaction();
    try { foreach ($prepared as [$d, $f]) insert_order($f, $d); $pdo->commit(); }
    catch (Throwable $e) { $pdo->rollBack(); throw $e; }
    out(['ok' => true, 'count' => count($prepared)]);

case 'customers':     // owner: everyone who ordered with a phone number, with their totals
    need('owner');
    $rows = q("SELECT c.id, c.phone, c.name, c.car_plate, c.car_desc, c.offers, c.note, c.created_at, c.card_token,
                      COUNT(o.id) AS orders, COALESCE(SUM(o.total), 0) AS spent, MAX(o.created_at) AS last_at, MIN(o.created_at) AS first_at
               FROM customers c LEFT JOIN orders o ON o.phone = c.phone AND o.status <> 'cancelled'
               GROUP BY c.id, c.phone, c.name, c.car_plate, c.car_desc, c.offers, c.note, c.created_at, c.card_token
               ORDER BY last_at DESC")->fetchAll();
    foreach ($rows as &$r) {
        $r['id'] = (int)$r['id']; $r['orders'] = (int)$r['orders']; $r['spent'] = (float)$r['spent']; $r['offers'] = (int)$r['offers'];
        $ls = loyalty_state($r['phone']); $r['stamps'] = $ls['stamps']; $r['free'] = $ls['free']; $r['free_used'] = $ls['used']; $r['need'] = $ls['need'];
    }
    out($rows);

case 'customer_update':
    $post(); need('owner');
    $id = (int)($in['id'] ?? 0);
    if (array_key_exists('name', $in)) q('UPDATE customers SET name = ? WHERE id = ?', [clean((string)$in['name'], 60), $id]);
    if (array_key_exists('note', $in)) q('UPDATE customers SET note = ? WHERE id = ?', [clean((string)$in['note'], 200) ?: null, $id]);
    if (array_key_exists('offers', $in)) q('UPDATE customers SET offers = ? WHERE id = ?', [$in['offers'] ? 1 : 0, $id]);
    out(['ok' => true]);

case 'customer_stamps':  // owner adds or takes away stamps by hand (e.g. a cup bought before the card existed)
    $post(); need('owner');
    $c = q('SELECT id, phone, stamp_adj FROM customers WHERE id = ?', [(int)($in['id'] ?? 0)])->fetch() ?: fail('not_found', 404);
    $delta = (int)($in['delta'] ?? 0); if ($delta === 0 || abs($delta) > 30) fail('bad_delta');
    $ls = loyalty_state($c['phone']);
    if ($ls['earned'] + $delta < $ls['used'] * $ls['need']) fail('no_stamps');   // never below what free cups already used
    q('UPDATE customers SET stamp_adj = stamp_adj + ? WHERE id = ?', [$delta, (int)$c['id']]);
    loyalty_changed($c['phone']);
    out(loyalty_state($c['phone']));

case 'customer_add':    // owner adds a customer by mobile (gets a loyalty card straight away)
    $post(); need('owner');
    $ph = norm_phone($in['phone'] ?? ''); if ($ph === '') fail('invalid_phone');
    if (q('SELECT 1 FROM customers WHERE phone = ?', [$ph])->fetch()) fail('customer_exists');
    save_customer($ph, clean((string)($in['name'] ?? ''), 60), null, null, !empty($in['offers']));
    out(['ok' => true]);

case 'customer_orders':  // owner: one customer's order history
    need('owner');
    $ph = norm_phone($_GET['phone'] ?? ''); if ($ph === '') fail('invalid_phone');
    $rows = q('SELECT id, order_no, day, created_at, items, total, status, source, payment, free_cups, discount FROM orders WHERE phone = ? ORDER BY id DESC LIMIT 60', [$ph])->fetchAll();
    out(array_map('order_row', $rows));

case 'settings':
    need('owner');
    $c = []; foreach (q('SELECT * FROM channel_commissions')->fetchAll() as $r) $c[$r['channel']] = (float)$r['pct'];
    $p = array_map(fn($r) => ['id' => (int)$r['id'], 'name_ar' => $r['name_ar'], 'price' => (float)$r['price'], 'active' => (int)$r['active']],
        q('SELECT * FROM products ORDER BY sort, id')->fetchAll());
    $u = array_map(fn($r) => ['id' => (int)$r['id'], 'username' => $r['username'], 'role' => $r['role'], 'active' => (int)$r['active']],
        q('SELECT id, username, role, active FROM users ORDER BY id')->fetchAll());
    require_once __DIR__ . '/gwallet_lib.php';
    out(['commissions' => $c, 'products' => $p, 'users' => $u, 'loyalty' => loyalty_cfg(), 'wallet' => wallet_status(), 'gwallet' => gw_status(),
         'whatsapp' => setting('shop_whatsapp'),
         'location' => ['coords' => setting('shop_lat') !== '' ? setting('shop_lat') . ', ' . setting('shop_lng') : '', 'text' => setting('nearby_text')]]);

case 'gw_setup':      // owner: Google Wallet service-account key + Issuer ID
    $post(); need('owner');
    require_once __DIR__ . '/gwallet_lib.php';
    out(gw_install((string)($in['key'] ?? ''), trim((string)($in['issuer'] ?? ''))));

case 'wallet_setup':  // owner uploads the Apple Pass Type ID certificate once
    $post(); need('owner');
    require_once __DIR__ . '/wallet_lib.php';
    $p12 = base64_decode((string)($in['p12'] ?? ''), true); $wwdr = base64_decode((string)($in['wwdr'] ?? ''), true);
    if (!$p12 || !$wwdr) fail('missing_files');
    out(wallet_install($p12, (string)($in['password'] ?? ''), $wwdr));

case 'wallet_csr':    // owner: request file to upload to Apple (no Mac needed)
    $post(); need('owner');
    require_once __DIR__ . '/wallet_lib.php';
    out(['csr' => wallet_csr()]);

case 'wallet_cer':    // owner: the certificate Apple issued for that request
    $post(); need('owner');
    require_once __DIR__ . '/wallet_lib.php';
    $cer = base64_decode((string)($in['cer'] ?? ''), true); $wwdr = base64_decode((string)($in['wwdr'] ?? ''), true);
    if (!$cer || !$wwdr) fail('missing_files');
    out(wallet_install_cer($cer, $wwdr));

case 'save_contact':  // owner: WhatsApp number shown to customers on the order page
    $post(); need('owner');
    $raw = trim((string)($in['whatsapp'] ?? ''));
    $ph = $raw === '' ? '' : norm_phone($raw);
    if ($raw !== '' && $ph === '') fail('invalid_phone');
    set_setting('shop_whatsapp', $ph);
    out(['ok' => true, 'whatsapp' => $ph]);

case 'save_location':  // owner: shop coordinates for the "you're nearby" lock-screen card
    $post(); need('owner');
    require_once __DIR__ . '/gwallet_lib.php';
    $raw = trim((string)($in['coords'] ?? ''));
    if ($raw === '') { set_setting('shop_lat', ''); set_setting('shop_lng', ''); }
    else {
        if (!preg_match('/^\s*(-?\d{1,2}(?:\.\d+)?)\s*,\s*(-?\d{1,3}(?:\.\d+)?)\s*$/', $raw, $m) || abs((float)$m[1]) > 90 || abs((float)$m[2]) > 180) fail('bad_coords');
        set_setting('shop_lat', $m[1]); set_setting('shop_lng', $m[2]);
    }
    set_setting('nearby_text', clean((string)($in['text'] ?? ''), 120));
    refresh_all_cards();   // cards already in wallets pick up the location
    out(['ok' => true]);

case 'save_loyalty':
    $post(); need('owner');
    $need = (int)($in['need'] ?? 5); if ($need < 2 || $need > 30) fail('bad_need');
    set_setting('loyalty_on', !empty($in['on']) ? '1' : '0');
    set_setting('loyalty_need', (string)$need);
    set_setting('loyalty_unit', ($in['unit'] ?? '') === 'order' ? 'order' : 'cup');
    require_once __DIR__ . '/gwallet_lib.php';
    refresh_all_cards();   // cards already in wallets show the new rule
    out(['ok' => true]);

case 'save_commissions':
    $post(); need('owner');
    foreach (CHANNELS as $ch) {
        $v = (float)($in[$ch] ?? 0); if ($v < 0 || $v > 100) fail('bad_pct');
        q('UPDATE channel_commissions SET pct = ? WHERE channel = ?', [$v, $ch]);
    }
    out(['ok' => true]);

case 'save_product':
    $post(); need('owner');
    $price = (float)($in['price'] ?? -1); if ($price < 0) fail('bad_amount');
    q('UPDATE products SET price = ?, active = ? WHERE id = ?', [money($price), !empty($in['active']) ? 1 : 0, (int)($in['id'] ?? 0)]);
    out(['ok' => true]);

case 'add_user':
    $post(); need('owner');
    $un = clean($in['username'] ?? '', 60); $pw = (string)($in['password'] ?? '');
    if (!preg_match('/^[A-Za-z0-9_.-]{3,60}$/', $un)) fail('bad_username');
    if (strlen($pw) < 6) fail('short_password');
    if (q('SELECT 1 FROM users WHERE username = ?', [$un])->fetch()) fail('username_taken');
    q('INSERT INTO users (username, pass_hash, role, active, created_at) VALUES (?,?,?,1,?)', [$un, password_hash($pw, PASSWORD_DEFAULT), 'staff', now()]);
    out(['ok' => true]);

case 'user_update':
    $post(); $me = need('owner');
    $id = (int)($in['id'] ?? 0);
    if ($id === (int)$me['id']) fail('cannot_change_self');
    if (isset($in['password'])) {
        if (strlen((string)$in['password']) < 6) fail('short_password');
        q('UPDATE users SET pass_hash = ? WHERE id = ?', [password_hash((string)$in['password'], PASSWORD_DEFAULT), $id]);
    }
    if (isset($in['active'])) q('UPDATE users SET active = ? WHERE id = ?', [$in['active'] ? 1 : 0, $id]);
    out(['ok' => true]);

default:
    fail('unknown_action', 404);
}
} catch (PDOException $e) {
    error_log('acai api: ' . $e->getMessage());
    fail('server_error', 500);
}
