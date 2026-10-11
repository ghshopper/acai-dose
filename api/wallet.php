<?php
declare(strict_types=1);
// Apple Wallet: the customer's pass download (?c=card) and Apple's pass web service (/wallet/v1/...).
require __DIR__ . '/lib.php';
require __DIR__ . '/loyalty.php';
require __DIR__ . '/wallet_lib.php';

function pass_out(array $c): void {
    $bin = wallet_build($c);
    header('Content-Type: application/vnd.apple.pkpass');
    header('Content-Disposition: attachment; filename="acaidose.pkpass"');
    header('Last-Modified: ' . gmdate('D, d M Y H:i:s', max(1, (int)$c['pass_updated'])) . ' GMT');
    header('Cache-Control: no-store');
    echo $bin; exit;
}
function apple_auth(array $c): void {
    $h = $_SERVER['HTTP_AUTHORIZATION'] ?? $_SERVER['REDIRECT_HTTP_AUTHORIZATION'] ?? '';
    if ($h === '' && function_exists('getallheaders')) foreach (getallheaders() as $k => $v) if (strcasecmp($k, 'Authorization') === 0) $h = $v;
    if (!hash_equals('ApplePass ' . $c['wallet_auth'], trim((string)$h))) { http_response_code(401); exit; }
}
function by_serial(string $s): ?array {
    if (!preg_match('/^[a-f0-9]{32}$/', $s)) return null;
    $c = q('SELECT * FROM customers WHERE card_token = ?', [$s])->fetch();
    return $c ?: null;
}

try {
    ensure_schema();

    // Customer taps "Add to Apple Wallet"
    if (isset($_GET['c'])) {
        rate_limit('wallet', 30, 600);
        $c = by_serial((string)$_GET['c']);
        if (!$c) { http_response_code(404); exit; }
        if ((int)$c['pass_updated'] === 0) q('UPDATE customers SET pass_updated = ? WHERE id = ?', [$c['pass_updated'] = time(), (int)$c['id']]);
        pass_out($c);
    }

    // Apple's web service: v1/devices/{device}/registrations/{passType}[/{serial}], v1/passes/{passType}/{serial}, v1/log
    $p = explode('/', trim((string)($_GET['p'] ?? ''), '/'));
    $m = $_SERVER['REQUEST_METHOD'];
    $type = setting('wallet_pass_type');

    if (($p[0] ?? '') !== 'v1') { http_response_code(404); exit; }

    if (($p[1] ?? '') === 'log') { error_log('acai wallet log: ' . substr((string)file_get_contents('php://input'), 0, 2000)); http_response_code(200); exit; }

    if (($p[1] ?? '') === 'passes' && count($p) === 4 && $m === 'GET') {
        if ($p[2] !== $type || !($c = by_serial($p[3]))) { http_response_code(404); exit; }
        apple_auth($c);
        $since = strtotime((string)($_SERVER['HTTP_IF_MODIFIED_SINCE'] ?? '')) ?: 0;
        if ($since && (int)$c['pass_updated'] <= $since) { http_response_code(304); exit; }
        pass_out($c);
    }

    if (($p[1] ?? '') === 'devices' && ($p[3] ?? '') === 'registrations' && ($p[4] ?? '') === $type) {
        $dev = (string)($p[2] ?? '');
        if (!preg_match('/^[A-Za-z0-9._-]{1,100}$/', $dev)) { http_response_code(400); exit; }

        if (count($p) === 5 && $m === 'GET') {   // which of my passes changed?
            $tag = (int)($_GET['passesUpdatedSince'] ?? 0);
            $rows = q('SELECT c.card_token, c.pass_updated FROM wallet_regs r JOIN customers c ON c.card_token = r.serial WHERE r.device_id = ? AND c.pass_updated > ?', [$dev, $tag])->fetchAll();
            if (!$rows) { http_response_code(204); exit; }
            header('Content-Type: application/json');
            echo json_encode(['serialNumbers' => array_column($rows, 'card_token'), 'lastUpdated' => (string)max(array_map('intval', array_column($rows, 'pass_updated')))]);
            exit;
        }
        if (count($p) === 6) {
            $c = by_serial($p[5]); if (!$c) { http_response_code(404); exit; }
            apple_auth($c);
            if ($m === 'POST') {
                $push = (string)(json_decode((string)file_get_contents('php://input'), true)['pushToken'] ?? '');
                if (!preg_match('/^[A-Za-z0-9]{10,200}$/', $push)) { http_response_code(400); exit; }
                if (q('SELECT 1 FROM wallet_devices WHERE device_id = ?', [$dev])->fetch()) q('UPDATE wallet_devices SET push_token = ?, updated_at = ? WHERE device_id = ?', [$push, now(), $dev]);
                else q('INSERT INTO wallet_devices (device_id, push_token, updated_at) VALUES (?,?,?)', [$dev, $push, now()]);
                if (q('SELECT 1 FROM wallet_regs WHERE device_id = ? AND serial = ?', [$dev, $c['card_token']])->fetch()) { http_response_code(200); exit; }
                q('INSERT INTO wallet_regs (device_id, serial, created_at) VALUES (?,?,?)', [$dev, $c['card_token'], now()]);
                http_response_code(201); exit;
            }
            if ($m === 'DELETE') {
                q('DELETE FROM wallet_regs WHERE device_id = ? AND serial = ?', [$dev, $c['card_token']]);
                http_response_code(200); exit;
            }
        }
    }
    http_response_code(404);
} catch (PDOException $e) {
    error_log('acai wallet: ' . $e->getMessage());
    http_response_code(500);
}
