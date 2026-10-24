<?php
declare(strict_types=1);
date_default_timezone_set('Asia/Muscat');
// Which shop this request belongs to. Karak Dose lives under /karak/ on the same site and keeps its own
// tables (same names with a kd_ prefix), so menus, sales, staff and customers never mix.
define('BIZ', (preg_match('~^/karak(/|$)~', (string)parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH)) || getenv('ACAI_TEST_BIZ') === 'karak') ? 'karak' : 'acai');
define('SHOP_PHONE', BIZ === 'karak' ? '+96898558386' : '+96872612311');   // shop number: WhatsApp button default, wallet cards
const BIZ_TABLES = 'users|products|orders|day_counters|channel_commissions|channel_sales|expenses|hits|ingredients|recipe_items|purchases|stock_counts|toppings|customers|settings|wallet_devices|wallet_regs';
/** Points table names in a statement at this shop's tables. */
function tp(string $sql): string {
    if (BIZ === 'acai') return $sql;
    $t = BIZ_TABLES;
    $sql = preg_replace("/\b(FROM|JOIN|INTO|UPDATE|TABLE|EXISTS|ON)(\s+)($t)\b/i", '$1$2kd_$3', $sql);
    $sql = preg_replace("/\btable_info\(($t)\)/", 'table_info(kd_$1)', $sql);
    return preg_replace('/\bINDEX\s+(\w+)\s+ON\b/i', 'INDEX kd_$1 ON', $sql);
}
function xq(string $sql): void { db()->exec(tp($sql)); }
// Database settings live outside the website folder (survives updates), with api/config.php as a fallback.
$__base = dirname(__DIR__, 3);
$__cfg = is_file("$__base/acai-config.php") ? "$__base/acai-config.php" : (is_file("$__base/config.php") ? "$__base/config.php" : __DIR__ . '/config.php');
require $__cfg;

function db(): PDO {
    static $pdo = null;
    if ($pdo) return $pdo;
    if (getenv('ACAI_TEST_DSN')) {                      // local tests only
        $pdo = new PDO(getenv('ACAI_TEST_DSN'));
    } else {
        $pdo = new PDO('mysql:host=' . DB_HOST . ';dbname=' . DB_NAME . ';charset=utf8mb4', DB_USER, DB_PASS);
    }
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    $pdo->setAttribute(PDO::ATTR_DEFAULT_FETCH_MODE, PDO::FETCH_ASSOC);
    $pdo->setAttribute(PDO::ATTR_EMULATE_PREPARES, false);
    return $pdo;
}
function is_mysql(): bool { return db()->getAttribute(PDO::ATTR_DRIVER_NAME) === 'mysql'; }

function q(string $sql, array $p = []): PDOStatement { $s = db()->prepare(tp($sql)); $s->execute($p); return $s; }
function now(): string { return date('Y-m-d H:i:s'); }

function out($data, int $code = 200): never {
    http_response_code($code);
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store');
    echo json_encode($data, JSON_UNESCAPED_UNICODE);
    exit;
}
function fail(string $msg, int $code = 400): never { out(['error' => $msg], $code); }

function body(): array {
    $raw = file_get_contents('php://input') ?: '';
    $j = json_decode($raw, true);
    return is_array($j) ? $j : [];
}

function start_session(): void {
    if (session_status() === PHP_SESSION_ACTIVE) return;
    session_name(BIZ === 'karak' ? 'kd_sid' : 'acai_sid');
    session_set_cookie_params([
        'lifetime' => 60 * 60 * 24 * 30, 'path' => '/', 'secure' => !empty($_SERVER['HTTPS']),
        'httponly' => true, 'samesite' => 'Strict',
    ]);
    ini_set('session.gc_maxlifetime', (string)(60 * 60 * 24 * 30));
    session_start();
}

function user(): ?array {
    start_session();
    if (empty($_SESSION['uid'])) return null;
    $u = q('SELECT id, username, role, active FROM users WHERE id = ?', [$_SESSION['uid']])->fetch();
    if (!$u || !(int)$u['active']) { $_SESSION = []; return null; }
    return $u;
}
/** The signed-in user, without starting a session for visitors who have none. */
function user_if_any(): ?array {
    return isset($_COOKIE[BIZ === 'karak' ? 'kd_sid' : 'acai_sid']) ? user() : null;
}
function need(string $role): array {
    $u = user();
    if (!$u) fail('login_required', 401);
    if ($role === 'owner' && $u['role'] !== 'owner') fail('forbidden', 403);
    return $u;
}

function client_ip(): string { return substr($_SERVER['REMOTE_ADDR'] ?? '0', 0, 45); }

/** Simple fixed-window limiter backed by the database. */
function rate_limit(string $bucket, int $max, int $windowSec): void {
    $since = date('Y-m-d H:i:s', time() - $windowSec);
    $key = $bucket . ':' . client_ip();
    q('DELETE FROM hits WHERE at < ?', [date('Y-m-d H:i:s', time() - 86400)]);
    $n = (int)q('SELECT COUNT(*) c FROM hits WHERE k = ? AND at >= ?', [$key, $since])->fetch()['c'];
    if ($n >= $max) fail('too_many', 429);
    q('INSERT INTO hits (k, at) VALUES (?, ?)', [$key, now()]);
}

function money($n): float { return round((float)$n, 3); }
function clean(?string $s, int $max): string { return mb_substr(trim((string)$s), 0, $max); }

/** Adds new columns on first request after an update, so re-running setup is not needed. */
function ensure_schema(): void {
    try { q('SELECT source, car_plate, token, commission, n_orders FROM orders LIMIT 0'); q('SELECT id, card_token, pass_updated, gwallet, stamp_adj FROM customers LIMIT 0'); q('SELECT free_cups FROM orders LIMIT 0'); q('SELECT k FROM settings LIMIT 0'); q('SELECT serial FROM wallet_regs LIMIT 0'); q('SELECT id FROM stock_counts LIMIT 0');
          q('SELECT cat, size, soldout FROM products LIMIT 0');
          $flags = BIZ === 'karak' ? ['karak_menu', 'open_item', 'karak_flavours'] : ['mini_prices_set', 'bowls_added', 'costing_added', 'open_item'];
          foreach ($flags as $f) if (!q('SELECT 1 FROM settings WHERE k = ?', [$f])->fetch()) throw new RuntimeException("$f missing"); }
    catch (Throwable $e) { require_once __DIR__ . '/schema.php'; create_schema(); }
}

/** Oman mobile in +968XXXXXXXX form, or '' when it isn't one. */
function norm_phone($p): string {
    $d = preg_replace('/\D/', '', (string)$p);
    if (strlen($d) === 11 && str_starts_with($d, '968')) $d = substr($d, 3);
    if (strlen($d) === 12 && str_starts_with($d, '00968')) $d = substr($d, 5);
    return preg_match('/^[279]\d{7}$/', $d) ? '+968' . $d : '';
}

/** Adds or refreshes the customer for this phone; empty values never overwrite saved ones. */
function save_customer(string $phone, ?string $name, ?string $car = null, ?string $carDesc = null, ?bool $offers = null, ?string $at = null): void {
    $phone = norm_phone($phone); if ($phone === '') return;
    $at = $at ?: now();
    $c = q('SELECT id FROM customers WHERE phone = ?', [$phone])->fetch();
    if (!$c) {
        q('INSERT INTO customers (phone, name, car_plate, car_desc, offers, created_at, updated_at, card_token, wallet_auth) VALUES (?,?,?,?,?,?,?,?,?)',
          [$phone, (string)($name ?? ''), $car ?: null, $carDesc ?: null, $offers ? 1 : 0, $at, $at, bin2hex(random_bytes(16)), bin2hex(random_bytes(16))]);
        return;
    }
    $set = ['updated_at = ?']; $v = [$at];
    if ($name !== null && $name !== '' && !in_array($name, ['Walk-in', 'Imported'], true)) { $set[] = 'name = ?'; $v[] = $name; }
    if ($car) { $set[] = 'car_plate = ?'; $v[] = $car; }
    if ($carDesc) { $set[] = 'car_desc = ?'; $v[] = $carDesc; }
    if ($offers !== null) { $set[] = 'offers = ?'; $v[] = $offers ? 1 : 0; }
    $v[] = (int)$c['id'];
    q('UPDATE customers SET ' . implode(', ', $set) . ' WHERE id = ?', $v);
}
