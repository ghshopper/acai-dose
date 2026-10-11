<?php
declare(strict_types=1);
// "Add to Google Wallet": makes the customer's card at Google and sends them to Google's save page.
require __DIR__ . '/lib.php';
require __DIR__ . '/loyalty.php';
require __DIR__ . '/gwallet_lib.php';

try {
    ensure_schema();
    rate_limit('gwallet', 30, 600);
    $card = (string)($_GET['c'] ?? '');
    $c = preg_match('/^[a-f0-9]{32}$/', $card) ? q('SELECT * FROM customers WHERE card_token = ?', [$card])->fetch() : null;
    if (!$c || !gw_ready()) { http_response_code(404); exit('Card not found'); }
    header('Location: ' . gw_save_url($c), true, 302);
} catch (Throwable $e) {
    error_log('acai gwallet: ' . $e->getMessage());
    http_response_code(502);
    echo 'Google Wallet is not available right now. Please try again later.';
}
