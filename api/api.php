<?php
declare(strict_types=1);
require __DIR__ . '/lib.php';

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
function insert_order(array $f): int {
    $day = date('Y-m-d');
    $pdo = db(); $pdo->beginTransaction();
    try {
        $row = q('SELECT last_no FROM day_counters WHERE day = ?' . (is_mysql() ? ' FOR UPDATE' : ''), [$day])->fetch();
        if ($row) { $no = (int)$row['last_no'] + 1; q('UPDATE day_counters SET last_no = ? WHERE day = ?', [$no, $day]); }
        else { $no = 1; q('INSERT INTO day_counters (day, last_no) VALUES (?, 1)', [$day]); }
        $f += ['order_no' => $no, 'day' => $day, 'created_at' => now(), 'updated_at' => now()];
        $cols = array_keys($f);
        q('INSERT INTO orders (' . implode(',', $cols) . ') VALUES (' . implode(',', array_fill(0, count($cols), '?')) . ')', array_values($f));
        $pdo->commit();
    } catch (Throwable $e) { $pdo->rollBack(); throw $e; }
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
    $token = bin2hex(random_bytes(16));
    $no = insert_order([
        'source' => 'web', 'customer_name' => $name, 'phone' => $phone, 'car_plate' => $car, 'car_desc' => $carDesc ?: null,
        'pickup_time' => $pickup, 'notes' => $notes ?: null, 'items' => json_encode($lines, JSON_UNESCAPED_UNICODE),
        'total' => $total, 'status' => 'new', 'token' => $token,
    ]);
    out(['order_no' => $no, 'ref' => order_ref(date('Y-m-d'), $no), 'total' => $total, 'token' => $token]);

case 'track':     // customer polls their own order by secret token
    $t = (string)($_GET['t'] ?? '');
    if (!preg_match('/^[a-f0-9]{32}$/', $t)) fail('not_found', 404);
    $o = q('SELECT order_no, status, total, pickup_time, car_plate, arrived_at, day FROM orders WHERE token = ?', [$t])->fetch();
    if (!$o) fail('not_found', 404);
    out(['order_no' => (int)$o['order_no'], 'ref' => order_ref($o['day'], (int)$o['order_no']), 'status' => $o['status'], 'total' => (float)$o['total'], 'pickup_time' => $o['pickup_time'],
         'car_plate' => $o['car_plate'], 'arrived' => (bool)$o['arrived_at'], 'today' => $o['day'] === date('Y-m-d')]);

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
    out(array_map('order_row', $rows));

case 'order_status':
    $post(); need('staff');
    $st = $in['status'] ?? '';
    if (!in_array($st, STATUSES, true)) fail('bad_status');
    $pay = in_array($in['payment'] ?? null, ['cash', 'card'], true) ? $in['payment'] : null;
    if ($st === 'done' && $pay) q('UPDATE orders SET status = ?, payment = ?, updated_at = ? WHERE id = ?', [$st, $pay, now(), (int)($in['id'] ?? 0)]);
    else q('UPDATE orders SET status = ?, updated_at = ? WHERE id = ?', [$st, now(), (int)($in['id'] ?? 0)]);
    out(['ok' => true]);

// ---------------- staff: POS ----------------
case 'pos_sale':
    $post(); $u = need('staff');
    $pay = $in['payment'] ?? '';
    if (!in_array($pay, ['cash', 'card'], true)) fail('bad_payment');
    [$lines, $total] = price_items($in['items'] ?? null);
    $no = insert_order([
        'source' => 'pos', 'customer_name' => 'Walk-in', 'phone' => '', 'items' => json_encode($lines, JSON_UNESCAPED_UNICODE),
        'total' => $total, 'status' => 'done', 'payment' => $pay, 'created_by' => (int)$u['id'],
    ]);
    out(['order_no' => $no, 'ref' => order_ref(date('Y-m-d'), $no), 'total' => $total]);

case 'pos_today':
    need('staff');
    $rows = q("SELECT o.id, o.order_no, o.day, o.created_at, o.items, o.total, o.status, o.payment, o.source, u.username AS by_user
               FROM orders o LEFT JOIN users u ON u.id = o.created_by
               WHERE o.day = ? AND o.source = 'pos' ORDER BY o.id DESC", [date('Y-m-d')])->fetchAll();
    out(array_map('order_row', $rows));

case 'pos_void':
    $post(); $u = need('staff');
    $o = q("SELECT id, created_at, created_by FROM orders WHERE id = ? AND source = 'pos' AND status = 'done'", [(int)($in['id'] ?? 0)])->fetch();
    if (!$o) fail('not_found', 404);
    if ($u['role'] !== 'owner' && ((int)$o['created_by'] !== (int)$u['id'] || strtotime($o['created_at']) < time() - 15 * 60)) fail('void_window');
    q("UPDATE orders SET status = 'cancelled', updated_at = ? WHERE id = ?", [now(), (int)$o['id']]);
    out(['ok' => true]);

// ---------------- owner: dashboard ----------------
case 'range':
    need('owner');
    $from = valid_date($_GET['from'] ?? ''); $to = valid_date($_GET['to'] ?? '');
    $orders = q('SELECT id, order_no, day, created_at, customer_name, phone, car_plate, items, total, status, source, payment FROM orders WHERE day BETWEEN ? AND ? ORDER BY id DESC', [$from, $to])->fetchAll();
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

case 'settings':
    need('owner');
    $c = []; foreach (q('SELECT * FROM channel_commissions')->fetchAll() as $r) $c[$r['channel']] = (float)$r['pct'];
    $p = array_map(fn($r) => ['id' => (int)$r['id'], 'name_ar' => $r['name_ar'], 'price' => (float)$r['price'], 'active' => (int)$r['active']],
        q('SELECT * FROM products ORDER BY sort, id')->fetchAll());
    $u = array_map(fn($r) => ['id' => (int)$r['id'], 'username' => $r['username'], 'role' => $r['role'], 'active' => (int)$r['active']],
        q('SELECT id, username, role, active FROM users ORDER BY id')->fetchAll());
    out(['commissions' => $c, 'products' => $p, 'users' => $u]);

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
