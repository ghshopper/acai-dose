<?php
declare(strict_types=1);
date_default_timezone_set('Asia/Muscat');
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

function q(string $sql, array $p = []): PDOStatement { $s = db()->prepare($sql); $s->execute($p); return $s; }
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
    session_name('acai_sid');
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
    try { q('SELECT source, car_plate, token, commission FROM orders LIMIT 0'); }
    catch (Throwable $e) { require_once __DIR__ . '/schema.php'; create_schema(); }
}
