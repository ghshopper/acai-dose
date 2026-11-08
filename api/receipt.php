<?php
declare(strict_types=1);
// Invoice photos for expenses: kept outside the website folder, read by Claude (Anthropic API) to fill the expense form.
// The API key goes in the same config file as the database settings:  define('ANTHROPIC_API_KEY', 'sk-ant-...');
// Without a key the photo is still saved with the expense and staff type the details themselves.

const RECEIPT_MAX_BYTES = 6 * 1024 * 1024;
const RECEIPT_MODEL = 'claude-haiku-4-5-20251001';

/** Folder for this shop's invoice photos (outside public_html when possible). */
function receipt_dir(): string {
    $outside = dirname(__DIR__, 3) . '/acai-receipts';
    $base = (is_dir($outside) || @mkdir($outside, 0750, true)) && is_writable($outside) ? $outside : dirname(__DIR__) . '/receipts';
    if (!is_dir($base)) @mkdir($base, 0750, true);
    if (str_starts_with($base, dirname(__DIR__)) && !is_file("$base/.htaccess")) @file_put_contents("$base/.htaccess", "Require all denied\n");
    $dir = $base . '/' . BIZ;
    if (!is_dir($dir)) @mkdir($dir, 0750, true);
    return $dir;
}
function receipt_name_ok($n): bool { return is_string($n) && (bool)preg_match('/^[a-f0-9]{32}\.(jpg|png|webp)$/', $n); }
function receipt_path(string $n): string { return receipt_dir() . '/' . $n; }

/** Saves a base64 photo (data URL or plain base64); returns its file name. */
function receipt_save(string $b64): string {
    if (str_contains($b64, ',')) $b64 = substr($b64, strpos($b64, ',') + 1);
    $raw = base64_decode($b64, true);
    if ($raw === false || strlen($raw) < 1000 || strlen($raw) > RECEIPT_MAX_BYTES) fail('bad_image');
    $info = @getimagesizefromstring($raw);
    $ext = ['image/jpeg' => 'jpg', 'image/png' => 'png', 'image/webp' => 'webp'][$info['mime'] ?? ''] ?? null;
    if (!$ext) fail('bad_image');
    $name = bin2hex(random_bytes(16)) . '.' . $ext;
    if (@file_put_contents(receipt_path($name), $raw) === false) fail('server_error', 500);
    return $name;
}

function ai_key(): string {
    if (defined('ANTHROPIC_API_KEY')) return (string)constant('ANTHROPIC_API_KEY');
    return (string)(getenv('ANTHROPIC_API_KEY') ?: '');
}

/** Asks Claude to read the invoice; returns the fields it found, or null when it could not. */
function ai_read_receipt(string $name): ?array {
    $key = ai_key();
    if ($key === '' || !function_exists('curl_init')) return null;
    $path = receipt_path($name);
    $mime = ['jpg' => 'image/jpeg', 'png' => 'image/png', 'webp' => 'image/webp'][pathinfo($name, PATHINFO_EXTENSION)];
    $cats = [];
    foreach (pos_expense_cats() as $k => $v) $cats[] = "$k = {$v[0]}";
    $prompt = "This is a photo of a purchase invoice or receipt from a small café in Oman (" . (BIZ === 'karak' ? 'karak tea and sandwiches' : 'açaí bowls and smoothies') . "). "
        . "Read it and answer with ONE JSON object only, no other text:\n"
        . '{"date":"YYYY-MM-DD or null","vendor":"shop/supplier name or null","invoice_no":"string or null","total":number or null,"vat":number or null,'
        . '"currency":"OMR unless clearly another","category":"one key from the list","summary":"short English list of what was bought, max 70 characters","readable":true or false}' . "\n"
        . "total = the final amount paid, including VAT, in rials with 3 decimals (Omani invoices show baisa: 1 OMR = 1000 baisa). "
        . "Dates on Omani invoices are usually day/month/year. Category keys: " . implode('; ', $cats) . ". "
        . "If the photo is not an invoice or you cannot read the total, set readable to false.";
    $body = json_encode([
        'model' => RECEIPT_MODEL, 'max_tokens' => 400,
        'messages' => [['role' => 'user', 'content' => [
            ['type' => 'image', 'source' => ['type' => 'base64', 'media_type' => $mime, 'data' => base64_encode((string)file_get_contents($path))]],
            ['type' => 'text', 'text' => $prompt],
        ]]],
    ]);
    $c = curl_init('https://api.anthropic.com/v1/messages');
    curl_setopt_array($c, [CURLOPT_POST => true, CURLOPT_POSTFIELDS => $body, CURLOPT_RETURNTRANSFER => true, CURLOPT_TIMEOUT => 40, CURLOPT_CONNECTTIMEOUT => 8,
        CURLOPT_HTTPHEADER => ['Content-Type: application/json', 'x-api-key: ' . $key, 'anthropic-version: 2023-06-01']]);
    $res = curl_exec($c); $code = (int)curl_getinfo($c, CURLINFO_HTTP_CODE); curl_close($c);
    if (!is_string($res) || $code !== 200) { error_log("receipt ai: HTTP $code"); return null; }
    $j = json_decode($res, true);
    $text = '';
    foreach ($j['content'] ?? [] as $part) if (($part['type'] ?? '') === 'text') $text .= $part['text'];
    if (!preg_match('/\{.*\}/s', $text, $m)) return null;
    $r = json_decode($m[0], true);
    if (!is_array($r)) return null;
    $cats = pos_expense_cats();
    $date = is_string($r['date'] ?? null) && preg_match('/^\d{4}-\d{2}-\d{2}$/', $r['date']) ? $r['date'] : null;
    if ($date && ($date > date('Y-m-d') || $date < date('Y-m-d', strtotime('-60 days')))) $date = null;
    $total = is_numeric($r['total'] ?? null) ? round((float)$r['total'], 3) : null;
    if ($total !== null && ($total <= 0 || $total > 500)) $total = null;
    return [
        'readable' => (bool)($r['readable'] ?? $total !== null),
        'date' => $date,
        'vendor' => mb_substr(trim((string)($r['vendor'] ?? '')), 0, 40),
        'invoice_no' => mb_substr(trim((string)($r['invoice_no'] ?? '')), 0, 20),
        'total' => $total,
        'vat' => is_numeric($r['vat'] ?? null) ? round((float)$r['vat'], 3) : null,
        'currency' => mb_substr((string)($r['currency'] ?? 'OMR'), 0, 5),
        'cat' => isset($cats[$r['category'] ?? '']) ? $r['category'] : 'other',
        'summary' => mb_substr(trim((string)($r['summary'] ?? '')), 0, 70),
    ];
}
