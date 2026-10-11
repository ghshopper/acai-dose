<?php
declare(strict_types=1);
// Apple Wallet loyalty pass: building, signing and pushing updates.
// The owner uploads the Pass Type ID certificate once from the dashboard; it is kept outside public_html.

function wallet_dir(): string {
    $d = getenv('ACAI_WALLET_DIR') ?: dirname(__DIR__, 3) . '/acai-wallet';
    if (!is_dir($d)) @mkdir($d, 0700, true);
    return $d;
}
function wallet_site(): string {
    $h = $_SERVER['HTTP_HOST'] ?? '';
    return 'https://' . (preg_match('/^[a-z0-9.-]+$/i', $h) && $h !== '' && !str_starts_with($h, '127.') && $h !== 'localhost' ? $h : 'order.acaiee.com');
}
function wallet_ready(): bool {
    $d = wallet_dir();
    return extension_loaded('openssl') && class_exists('ZipArchive')
        && setting('wallet_pass_type') !== '' && setting('wallet_team') !== ''
        && is_file("$d/cert.pem") && is_file("$d/key.pem") && is_file("$d/wwdr.pem");
}
function wallet_status(): array {
    $d = wallet_dir(); $exp = null;
    if (is_file("$d/cert.pem")) { $x = openssl_x509_parse((string)file_get_contents("$d/cert.pem")); $exp = $x ? date('Y-m-d', $x['validTo_time_t']) : null; }
    return ['ready' => wallet_ready(), 'pass_type' => setting('wallet_pass_type'), 'team' => setting('wallet_team'), 'expires' => $exp,
            'has_zip' => class_exists('ZipArchive'), 'has_openssl' => extension_loaded('openssl')];
}

/** Saves the Pass Type ID certificate (.p12 + password) and Apple's WWDR certificate (.cer). */
function wallet_install(string $p12, string $pass, string $wwdr): array {
    $certs = [];
    if (!openssl_pkcs12_read($p12, $certs, $pass)) fail('p12_unreadable');
    $key = ''; openssl_pkey_export($certs['pkey'], $key);
    return wallet_save($certs['cert'], $key, $wwdr);
}

function to_pem(string $der): string {
    return str_contains($der, '-----BEGIN CERTIFICATE-----') ? $der
        : "-----BEGIN CERTIFICATE-----\n" . chunk_split(base64_encode($der), 64, "\n") . "-----END CERTIFICATE-----\n";
}

/** Step 1 without a Mac: the server makes the private key and the request file to upload to Apple. */
function wallet_csr(): string {
    $key = openssl_pkey_new(['private_key_bits' => 2048, 'private_key_type' => OPENSSL_KEYTYPE_RSA]);
    $csr = openssl_csr_new(['commonName' => 'Acai Dose', 'countryName' => 'OM', 'stateOrProvinceName' => 'Muscat', 'organizationName' => 'Acai Dose'], $key, ['digest_alg' => 'sha256']);
    if (!$key || !$csr) fail('csr_failed', 500);
    $pem = ''; openssl_pkey_export($key, $pem);
    $f = wallet_dir() . '/key-pending.pem'; file_put_contents($f, $pem); @chmod($f, 0600);
    $out = ''; openssl_csr_export($csr, $out);
    return $out;
}

/** Step 2: the pass.cer Apple gave back for that request, plus Apple's WWDR G4 certificate. */
function wallet_install_cer(string $cer, string $wwdr): array {
    $f = wallet_dir() . '/key-pending.pem';
    if (!is_file($f)) fail('no_pending_key');
    $cert = to_pem($cer); $key = (string)file_get_contents($f);
    if (!openssl_x509_parse($cert)) fail('bad_cer');
    if (!openssl_x509_check_private_key($cert, $key)) fail('cer_mismatch');
    $st = wallet_save($cert, $key, $wwdr);
    @unlink($f);
    return $st;
}

function wallet_save(string $cert, string $key, string $wwdr): array {
    $x = openssl_x509_parse($cert);
    $uid = $x['subject']['UID'] ?? ''; $team = $x['subject']['OU'] ?? '';
    if (!str_starts_with($uid, 'pass.') || $team === '') fail('not_pass_cert');
    $wwdr = to_pem($wwdr);
    if (!openssl_x509_parse($wwdr)) fail('bad_wwdr');
    $certs = ['cert' => $cert];
    $d = wallet_dir();
    foreach (['cert.pem' => $certs['cert'], 'key.pem' => $key, 'wwdr.pem' => $wwdr, 'apns.pem' => $certs['cert'] . "\n" . $key] as $f => $v) {
        file_put_contents("$d/$f", $v); @chmod("$d/$f", 0600);
    }
    set_setting('wallet_pass_type', $uid); set_setting('wallet_team', $team);
    return wallet_status();
}

/** Shop location: iPhones show the card on the lock screen when the customer is nearby. */
function wallet_locations(): array {
    $lat = setting('shop_lat'); $lng = setting('shop_lng');
    if (!is_numeric($lat) || !is_numeric($lng)) return [];
    $txt = setting('nearby_text') ?: 'قريب من أساي دوز! اطلب من الموقع واستلم من سيارتك';
    return [['latitude' => (float)$lat, 'longitude' => (float)$lng, 'relevantText' => $txt]];
}

/** pass.json for one customer. */
function wallet_pass_json(array $c): array {
    $st = loyalty_state($c['phone']);
    $site = wallet_site();
    $name = trim((string)$c['name']) !== '' ? (string)$c['name'] : 'عميل أساي دوز';
    $how = $st['unit'] === 'cup'
        ? "كل كوب تطلبه من موقعنا = ختم. كل {$st['need']} أختام = كوب مجاني ينخصم تلقائياً في طلبك الجاي."
        : "كل طلب من موقعنا = ختم. كل {$st['need']} أختام = كوب مجاني ينخصم تلقائياً في طلبك الجاي.";
    return array_filter([
        'formatVersion' => 1,
        'passTypeIdentifier' => setting('wallet_pass_type'),
        'teamIdentifier' => setting('wallet_team'),
        'serialNumber' => $c['card_token'],
        'authenticationToken' => $c['wallet_auth'],
        'webServiceURL' => $site . '/wallet/',
        'organizationName' => 'Açaí Dose',
        'description' => 'Açaí Dose loyalty card',
        'backgroundColor' => 'rgb(71,13,67)',
        'foregroundColor' => 'rgb(250,243,224)',
        'labelColor' => 'rgb(227,154,46)',
        'sharingProhibited' => true,
        'storeCard' => [
            'headerFields' => [['key' => 'stamps', 'label' => 'الأختام', 'value' => $st['stamps'] . '/' . $st['need'], 'textAlignment' => 'PKTextAlignmentRight',
                                'changeMessage' => 'انضاف ختم في بطاقة أساي دوز! صار عندك %@']],
            'secondaryFields' => [
                $st['free'] > 0
                    ? ['key' => 'left', 'label' => 'كوب مجاني', 'value' => $st['free'] > 1 ? $st['free'] . ' أكواب جاهزة' : 'جاهز لك!', 'changeMessage' => 'عندك كوب مجاني من أساي دوز! ينخصم في طلبك الجاي']
                    : ['key' => 'left', 'label' => 'باقي للمجاني', 'value' => ($st['need'] - $st['stamps']) . ($st['unit'] === 'cup' ? ' أكواب' : ' طلبات')],
                ['key' => 'name', 'label' => 'الاسم', 'value' => $name, 'textAlignment' => 'PKTextAlignmentRight'],
            ],
            'backFields' => [
                ['key' => 'how', 'label' => 'كيف تشتغل البطاقة', 'value' => $how],
                ['key' => 'order', 'label' => 'اطلب من موقعنا', 'value' => $site . '/', 'attributedValue' => "<a href='$site/'>order.acaiee.com</a>"],
                ['key' => 'where', 'label' => 'الاستلام', 'value' => 'القرم ٢٩، مسقط'],
                ['key' => 'phone', 'label' => 'مربوطة برقم', 'value' => '•••• ' . substr($c['phone'], -4)],
            ],
        ],
        'locations' => wallet_locations(),
        'barcodes' => [['format' => 'PKBarcodeFormatQR', 'message' => $site . '/card.html?c=' . $c['card_token'], 'messageEncoding' => 'iso-8859-1', 'altText' => '•••• ' . substr($c['phone'], -4)]],
    ], fn($v) => $v !== []);
}

/** Builds and signs the .pkpass file for one customer; returns its bytes. */
function wallet_build(array $c): string {
    if (!wallet_ready()) fail('wallet_off', 503);
    $st = loyalty_state($c['phone']);
    $img = dirname(__DIR__) . '/assets/wallet';
    $strip = $st['need'] === 5 ? ($st['free'] > 0 ? 'strip-free' : 'strip-' . $st['stamps']) : 'strip-plain';
    $files = ['pass.json' => json_encode(wallet_pass_json($c), JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES)];
    foreach (['icon.png', 'icon@2x.png', 'icon@3x.png', 'logo.png', 'logo@2x.png', 'logo@3x.png'] as $f) $files[$f] = file_get_contents("$img/$f");
    foreach (['' => '', '@2x' => '@2x', '@3x' => '@3x'] as $s) $files["strip$s.png"] = file_get_contents("$img/$strip$s.png");
    $manifest = []; foreach ($files as $n => $b) $manifest[$n] = sha1($b);
    $files['manifest.json'] = json_encode($manifest, JSON_UNESCAPED_SLASHES);
    $files['signature'] = wallet_sign($files['manifest.json']);

    $tmp = tempnam(sys_get_temp_dir(), 'pk');
    $z = new ZipArchive(); $z->open($tmp, ZipArchive::OVERWRITE);
    foreach ($files as $n => $b) $z->addFromString($n, $b);
    $z->close();
    $out = (string)file_get_contents($tmp); @unlink($tmp);
    return $out;
}

/** Detached PKCS#7 signature (DER) of the manifest, as Apple requires. */
function wallet_sign(string $manifest): string {
    $d = wallet_dir();
    $in = tempnam(sys_get_temp_dir(), 'mf'); $out = tempnam(sys_get_temp_dir(), 'sg');
    file_put_contents($in, $manifest);
    $ok = openssl_pkcs7_sign($in, $out, 'file://' . "$d/cert.pem", ['file://' . "$d/key.pem", ''], [], PKCS7_BINARY | PKCS7_DETACHED, "$d/wwdr.pem");
    $smime = (string)file_get_contents($out); @unlink($in); @unlink($out);
    if (!$ok) fail('sign_failed', 500);
    // Take the base64 body of the smime.p7s part
    $p = strpos($smime, 'smime.p7s'); if ($p === false) fail('sign_failed', 500);
    $body = substr($smime, $p);
    $body = preg_split("/\r?\n\r?\n/", $body, 2)[1] ?? '';
    $body = preg_split("/\r?\n------/", $body, 2)[0];
    $der = base64_decode(preg_replace('/\s+/', '', $body), true);
    if ($der === false || $der === '') fail('sign_failed', 500);
    return $der;
}

/** Tells every iPhone holding this card to fetch the new version (Apple push). Never throws. */
function wallet_push(string $serial): void {
    try {
        if (!wallet_ready() || !function_exists('curl_init')) return;
        $rows = q('SELECT d.device_id, d.push_token FROM wallet_regs r JOIN wallet_devices d ON d.device_id = r.device_id WHERE r.serial = ?', [$serial])->fetchAll();
        $topic = setting('wallet_pass_type'); $pem = wallet_dir() . '/apns.pem';
        foreach ($rows as $r) {
            $ch = curl_init('https://api.push.apple.com/3/device/' . rawurlencode($r['push_token']));
            curl_setopt_array($ch, [
                CURLOPT_POST => true, CURLOPT_POSTFIELDS => '{}', CURLOPT_RETURNTRANSFER => true,
                CURLOPT_HTTP_VERSION => CURL_HTTP_VERSION_2_0, CURLOPT_SSLCERT => $pem,
                CURLOPT_HTTPHEADER => ['apns-topic: ' . $topic],
                CURLOPT_CONNECTTIMEOUT => 4, CURLOPT_TIMEOUT => 6,
            ]);
            curl_exec($ch);
            $code = (int)curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
            curl_close($ch);
            if ($code === 410) q('DELETE FROM wallet_regs WHERE device_id = ? AND serial = ?', [$r['device_id'], $serial]);
        }
    } catch (Throwable $e) { error_log('acai wallet push: ' . $e->getMessage()); }
}
