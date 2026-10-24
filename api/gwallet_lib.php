<?php
declare(strict_types=1);
// Google Wallet loyalty card. The owner uploads a Google Cloud service-account key (JSON) and the
// Issuer ID once from the dashboard. Cards are created and updated through the Google Wallet REST API.

require_once __DIR__ . '/wallet_lib.php';   // wallet_dir(), wallet_site()

// Overridable only for local tests.
define('GW_API', getenv('ACAI_GW_API') ?: 'https://walletobjects.googleapis.com/walletobjects/v1');
define('GW_TOKEN_URL', getenv('ACAI_GW_TOKEN_URL') ?: 'https://oauth2.googleapis.com/token');

function gw_key(): ?array {
    $f = wallet_dir() . '/google-key.json';
    if (!is_file($f)) return null;
    $k = json_decode((string)file_get_contents($f), true);
    return is_array($k) && !empty($k['client_email']) && !empty($k['private_key']) ? $k : null;
}
function gw_ready(): bool { return setting('gw_issuer') !== '' && gw_key() !== null && function_exists('curl_init'); }
function gw_class_id(): string { return setting('gw_issuer') . '.acaidose_loyalty'; }
function gw_object_id(string $card): string { return setting('gw_issuer') . '.card_' . $card; }
function gw_status(): array {
    $k = gw_key();
    return ['ready' => gw_ready(), 'issuer' => setting('gw_issuer'), 'account' => $k['client_email'] ?? '', 'error' => setting('gw_error')];
}

function b64url(string $s): string { return rtrim(strtr(base64_encode($s), '+/', '-_'), '='); }
function gw_jwt(array $claims): string {
    $k = gw_key(); if (!$k) fail('gw_off', 503);
    $h = b64url(json_encode(['alg' => 'RS256', 'typ' => 'JWT']));
    $p = b64url(json_encode($claims, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE));
    $sig = '';
    if (!openssl_sign("$h.$p", $sig, $k['private_key'], OPENSSL_ALGO_SHA256)) fail('gw_key_bad', 500);
    return "$h.$p." . b64url($sig);
}

/** OAuth access token for the Wallet API, cached until shortly before it expires. */
function gw_token(): string {
    $t = setting('gw_token'); $exp = (int)setting('gw_token_exp', '0');
    if ($t !== '' && $exp > time() + 120) return $t;
    $k = gw_key(); if (!$k) fail('gw_off', 503);
    $now = time();
    $assert = gw_jwt(['iss' => $k['client_email'], 'scope' => 'https://www.googleapis.com/auth/wallet_object.issuer',
                      'aud' => 'https://oauth2.googleapis.com/token', 'iat' => $now, 'exp' => $now + 3600]);
    [$code, $body] = gw_http('POST', GW_TOKEN_URL,
        http_build_query(['grant_type' => 'urn:ietf:params:oauth:grant-type:jwt-bearer', 'assertion' => $assert]), 'application/x-www-form-urlencoded', false);
    $j = json_decode($body, true);
    if ($code !== 200 || empty($j['access_token'])) { set_setting('gw_error', 'token: ' . substr($body, 0, 300)); fail('gw_auth_failed', 502); }
    set_setting('gw_token', $j['access_token']); set_setting('gw_token_exp', (string)($now + (int)($j['expires_in'] ?? 3600)));
    return $j['access_token'];
}

/** [status, body]. Never throws on network errors (status 0). */
function gw_http(string $method, string $url, ?string $body = null, string $type = 'application/json', bool $auth = true): array {
    $ch = curl_init($url);
    $h = ['Content-Type: ' . $type];
    if ($auth) $h[] = 'Authorization: Bearer ' . gw_token();
    curl_setopt_array($ch, [CURLOPT_CUSTOMREQUEST => $method, CURLOPT_RETURNTRANSFER => true, CURLOPT_HTTPHEADER => $h,
                            CURLOPT_CONNECTTIMEOUT => 5, CURLOPT_TIMEOUT => 10]);
    if ($body !== null) curl_setopt($ch, CURLOPT_POSTFIELDS, $body);
    $out = curl_exec($ch);
    $code = (int)curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
    curl_close($ch);
    return [$code, is_string($out) ? $out : ''];
}

function gw_text(string $ar): array { return ['defaultValue' => ['language' => 'ar', 'value' => $ar]]; }
function gw_img(string $file, string $alt): array {
    return ['sourceUri' => ['uri' => wallet_site() . '/assets/wallet/' . $file], 'contentDescription' => gw_text($alt)];
}

function gw_class(): array {
    return [
        'id' => gw_class_id(),
        'issuerName' => 'Açaí Dose',
        'programName' => 'بطاقة أساي دوز',
        'programLogo' => gw_img('g-logo.png', 'Açaí Dose'),
        'hexBackgroundColor' => '#470D43',
        'reviewStatus' => 'UNDER_REVIEW',
        'countryCode' => 'OM',
        'multipleDevicesAndHoldersAllowedStatus' => 'ONE_USER_ALL_DEVICES',
    ];
}

/** The customer's card as a Google loyalty object (same data as the Apple pass). */
function gw_object(array $c): array {
    $st = loyalty_state($c['phone']);
    $hero = $st['need'] >= 3 && $st['need'] <= 10 ? 'g-hero-' . $st['need'] . '-' . ($st['free'] > 0 ? 'free' : $st['stamps']) . '.png' : 'g-hero-plain.png';
    $left = $st['free'] > 0 ? ($st['free'] > 1 ? $st['free'] . ' أكواب مجانية جاهزة' : 'كوب مجاني جاهز لك!')
        : ($st['need'] - $st['stamps']) . ($st['unit'] === 'cup' ? ' أكواب' : ' طلبات') . ' وتاخذ كوب مجاني';
    $site = wallet_site();
    return [
        'id' => gw_object_id($c['card_token']),
        'classId' => gw_class_id(),
        'state' => 'ACTIVE',
        'accountId' => '•••• ' . substr($c['phone'], -4),
        'accountName' => trim((string)$c['name']) !== '' ? (string)$c['name'] : 'عميل أساي دوز',
        'hexBackgroundColor' => '#470D43',
        'loyaltyPoints' => ['label' => 'الأختام', 'balance' => ['string' => $st['stamps'] . '/' . $st['need']]],
        'secondaryLoyaltyPoints' => ['label' => 'كوب مجاني', 'balance' => ['int' => $st['free']]],
        'heroImage' => gw_img($hero, 'الأختام'),
        'barcode' => ['type' => 'QR_CODE', 'value' => $site . '/card.html?c=' . $c['card_token'], 'alternateText' => '•••• ' . substr($c['phone'], -4)],
        'textModulesData' => [
            ['id' => 'left', 'header' => $st['free'] > 0 ? 'مبروك' : 'باقي لك', 'body' => $left],
            ['id' => 'how', 'header' => 'كيف تشتغل البطاقة', 'body' => 'كل ' . ($st['unit'] === 'cup' ? 'كوب' : 'طلب') . ' من موقعنا = ختم. كل ' . $st['need'] . ' أختام = كوب مجاني ينخصم تلقائياً في طلبك الجاي.'],
        ],
        'linksModuleData' => ['uris' => [['uri' => $site . '/', 'description' => 'اطلب من موقعنا', 'id' => 'order'], ['uri' => 'tel:' . SHOP_PHONE, 'description' => 'اتصل بنا 7261 2311', 'id' => 'call']]],
    ];
}

/** Creates or refreshes the class; called when the owner saves the key. */
function gw_sync_class(): void {
    $cls = gw_class();
    [$code, $body] = gw_http('GET', GW_API . '/loyaltyClass/' . rawurlencode($cls['id']));
    if ($code === 404) [$code, $body] = gw_http('POST', GW_API . '/loyaltyClass', json_encode($cls, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES));
    elseif ($code === 200) [$code, $body] = gw_http('PATCH', GW_API . '/loyaltyClass/' . rawurlencode($cls['id']), json_encode($cls, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES));
    if ($code < 200 || $code >= 300) { set_setting('gw_error', 'class: ' . substr($body, 0, 300)); fail('gw_class_failed', 502); }
    set_setting('gw_error', '');
}

/** "Add to Google Wallet" link for one customer (makes the card at Google first if needed). */
function gw_save_url(array $c): string {
    $obj = gw_object($c);
    [$code] = gw_http('GET', GW_API . '/loyaltyObject/' . rawurlencode($obj['id']));
    if ($code === 404) {
        [$code, $body] = gw_http('POST', GW_API . '/loyaltyObject', json_encode($obj, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES));
        if ($code < 200 || $code >= 300) { set_setting('gw_error', 'object: ' . substr($body, 0, 300)); fail('gw_object_failed', 502); }
    } elseif ($code === 200) {
        gw_http('PATCH', GW_API . '/loyaltyObject/' . rawurlencode($obj['id']), json_encode($obj, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES));
    }
    q('UPDATE customers SET gwallet = 1 WHERE id = ?', [(int)$c['id']]);
    $k = gw_key();
    $jwt = gw_jwt(['iss' => $k['client_email'], 'aud' => 'google', 'typ' => 'savetowallet', 'iat' => time(),
                   'origins' => [wallet_site()], 'payload' => ['loyaltyObjects' => [['id' => $obj['id']]]]]);
    return 'https://pay.google.com/gp/v/save/' . $jwt;
}

/** Pushes new stamps to the customer's Google card, if they have one. Never throws. */
function gw_update(string $card): void {
    try {
        if (!gw_ready()) return;
        $c = q('SELECT * FROM customers WHERE card_token = ? AND gwallet = 1', [$card])->fetch();
        if (!$c) return;
        $obj = gw_object($c);
        gw_http('PATCH', GW_API . '/loyaltyObject/' . rawurlencode($obj['id']), json_encode($obj, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES));
    } catch (Throwable $e) { error_log('acai gwallet update: ' . $e->getMessage()); }
}

/** After a design or rule change: every card already in a wallet fetches its new version. */
function refresh_all_cards(): void {
    q('UPDATE customers SET pass_updated = ?', [time()]);
    foreach (q('SELECT DISTINCT serial FROM wallet_regs')->fetchAll() as $r) wallet_push($r['serial']);
    foreach (q('SELECT card_token FROM customers WHERE gwallet = 1')->fetchAll() as $r) gw_update($r['card_token']);
}

/** Owner uploads the service-account key and Issuer ID. */
function gw_install(string $json, string $issuer): array {
    $k = json_decode($json, true);
    if (!is_array($k) || ($k['type'] ?? '') !== 'service_account' || empty($k['client_email']) || empty($k['private_key'])) fail('gw_bad_key');
    if (!openssl_pkey_get_private($k['private_key'])) fail('gw_bad_key');
    if (!preg_match('/^\d{10,25}$/', $issuer)) fail('gw_bad_issuer');
    $f = wallet_dir() . '/google-key.json'; file_put_contents($f, $json); @chmod($f, 0600);
    set_setting('gw_issuer', $issuer); set_setting('gw_token', ''); set_setting('gw_token_exp', '0');
    gw_sync_class();
    return gw_status();
}
