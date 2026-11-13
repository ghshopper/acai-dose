<?php
declare(strict_types=1);
// Invoice photos for expenses: kept outside the website folder, read by Claude (Anthropic API) to fill the expense form.
// The owner pastes the API key in the dashboard (Settings → invoice reading); one key serves both shops.
// (A define('ANTHROPIC_API_KEY', ...) in the config file also works.) Without a key the photo is still saved and staff type the details.

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
    if ($e = getenv('ANTHROPIC_API_KEY')) return (string)$e;
    // Kept in Açaí Dose's settings table (no kd_ prefix) so Karak Dose uses the same key
    $s = db()->prepare("SELECT v FROM settings WHERE k = 'ai_key'"); $s->execute();
    return (string)($s->fetchColumn() ?: '');
}
function ai_key_set(string $v): void {
    $pdo = db();
    $pdo->prepare("DELETE FROM settings WHERE k = 'ai_key'")->execute();
    if ($v !== '') $pdo->prepare("INSERT INTO settings (k, v) VALUES ('ai_key', ?)")->execute([$v]);
}
/** Checks a key with Anthropic before saving it. */
function ai_key_works(string $key): bool {
    if (!function_exists('curl_init')) return true;
    $c = curl_init('https://api.anthropic.com/v1/models?limit=1');
    curl_setopt_array($c, [CURLOPT_RETURNTRANSFER => true, CURLOPT_TIMEOUT => 15, CURLOPT_HTTPHEADER => ['x-api-key: ' . $key, 'anthropic-version: 2023-06-01']]);
    curl_exec($c); $code = (int)curl_getinfo($c, CURLINFO_HTTP_CODE); curl_close($c);
    return $code === 200;
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

// ---------- invoices split into items ----------
const INVOICE_MODEL = 'claude-sonnet-5-5';

/** What each invoice line is: key => [Arabic name (also the expense category), English name]. One list for both shops. */
function item_groups(): array {
    return [
        'milk' => ['حليب', 'Milk'], 'dairy' => ['أجبان وألبان', 'Cheese & dairy'], 'tea' => ['شاي', 'Tea'],
        'spices' => ['هيل وبهارات', 'Cardamom & spices'], 'sugar' => ['سكر وعسل', 'Sugar & honey'], 'coffee' => ['قهوة وكاكاو', 'Coffee & cocoa'],
        'eggs' => ['بيض', 'Eggs'], 'bread' => ['خبز ومعجنات', 'Bread & pastries'], 'flour' => ['طحين', 'Flour'], 'oil' => ['زيوت', 'Oil'],
        'sauces' => ['صلصات وأجبان دهن', 'Sauces & spreads'], 'meat' => ['لحوم ودجاج', 'Meat & chicken'], 'veg' => ['خضار', 'Vegetables'],
        'acai' => ['أساي', 'Açaí'], 'fruit' => ['فواكه', 'Fruit'], 'toppings' => ['توبينق ومكسرات', 'Toppings & nuts'], 'protein' => ['بروتين', 'Protein'],
        'soft_drinks' => ['مشروبات غازية وعصائر', 'Soft drinks & juice'], 'water' => ['ماء وثلج', 'Water & ice'], 'snacks' => ['سناكات ونودلز', 'Snacks & noodles'],
        'packaging' => ['أكواب وتغليف', 'Cups & packaging'], 'cleaning' => ['مواد تنظيف', 'Cleaning'], 'gas' => ['غاز', 'Gas'],
        'equipment' => ['معدات وأجهزة (مرة وحدة)', 'Equipment'], 'other' => ['أخرى', 'Other'],
    ];
}

/** Asks Claude for every line of the invoice and what each one is. */
function ai_read_invoice(string $name): ?array {
    $key = ai_key();
    if ($key === '' || !function_exists('curl_init')) return null;
    $path = receipt_path($name);
    if (!is_file($path)) return null;
    $mime = ['jpg' => 'image/jpeg', 'png' => 'image/png', 'webp' => 'image/webp'][pathinfo($name, PATHINFO_EXTENSION)];
    $groups = [];
    foreach (item_groups() as $k => $v) $groups[] = "$k ({$v[1]})";
    $prompt = "Photo of a purchase invoice or receipt from a small café in Oman (karak tea, sandwiches, açaí bowls, smoothies). Read EVERY line item.\n"
        . "Answer with ONE JSON object only:\n"
        . '{"readable":true,"vendor":"supplier/shop","invoice_no":"…","date":"YYYY-MM-DD","total":0.000,"vat":0.000,'
        . '"items":[{"name":"as printed, English if both","name_ar":"short Arabic name","qty":1,"unit":"e.g. carton 24x300ml","amount":0.000,"group":"key"}]}' . "\n"
        . "Rules: amounts in Omani rials with 3 decimals (1 OMR = 1000 baisa). amount = what that line cost in total, INCLUDING its VAT when the invoice shows VAT per line or a VAT rate code (5% items). "
        . "total = the final amount paid. Dates are usually day/month/year. Skip loyalty points, payment lines and change. "
        . "group = one key from: " . implode(', ', $groups) . ". "
        . "Kinza, 7UP, Mountain Dew, cola and juice are soft_drinks; Nutella, cream cheese spread and hot sauce are sauces; Nescafé is coffee; cardamom is spices; Indomie and chips are snacks; cups, lids, bags are packaging. "
        . "If it is not an invoice or the lines cannot be read, set readable to false.";
    $body = json_encode([
        'model' => INVOICE_MODEL, 'max_tokens' => 4000,
        'messages' => [['role' => 'user', 'content' => [
            ['type' => 'image', 'source' => ['type' => 'base64', 'media_type' => $mime, 'data' => base64_encode((string)file_get_contents($path))]],
            ['type' => 'text', 'text' => $prompt],
        ]]],
    ]);
    $c = curl_init('https://api.anthropic.com/v1/messages');
    curl_setopt_array($c, [CURLOPT_POST => true, CURLOPT_POSTFIELDS => $body, CURLOPT_RETURNTRANSFER => true, CURLOPT_TIMEOUT => 120, CURLOPT_CONNECTTIMEOUT => 10,
        CURLOPT_HTTPHEADER => ['Content-Type: application/json', 'x-api-key: ' . $key, 'anthropic-version: 2023-06-01']]);
    $res = curl_exec($c); $code = (int)curl_getinfo($c, CURLINFO_HTTP_CODE); curl_close($c);
    if (!is_string($res) || $code !== 200) { error_log("invoice ai: HTTP $code"); return ['error' => "ai_http_$code"]; }
    $text = '';
    foreach ((json_decode($res, true)['content'] ?? []) as $p) if (($p['type'] ?? '') === 'text') $text .= $p['text'];
    if (!preg_match('/\{.*\}/s', $text, $m) || !is_array($r = json_decode($m[0], true))) return ['error' => 'ai_unreadable'];
    $groups = item_groups(); $items = [];
    foreach ($r['items'] ?? [] as $it) {
        $amt = is_numeric($it['amount'] ?? null) ? round((float)$it['amount'], 3) : 0;
        if ($amt <= 0) continue;
        $items[] = ['name' => mb_substr(trim((string)($it['name'] ?? '')), 0, 120), 'name_ar' => mb_substr(trim((string)($it['name_ar'] ?? '')), 0, 80),
                    'qty' => is_numeric($it['qty'] ?? null) ? (float)$it['qty'] : 1, 'unit' => mb_substr(trim((string)($it['unit'] ?? '')), 0, 40),
                    'amount' => $amt, 'group' => isset($groups[$it['group'] ?? '']) ? $it['group'] : 'other'];
    }
    $date = is_string($r['date'] ?? null) && preg_match('/^\d{4}-\d{2}-\d{2}$/', $r['date']) ? $r['date'] : null;
    if ($date && ($date > date('Y-m-d') || $date < date('Y-m-d', strtotime('-120 days')))) $date = null;
    $total = is_numeric($r['total'] ?? null) ? round((float)$r['total'], 3) : null;
    return ['readable' => (bool)($r['readable'] ?? true) && $items, 'vendor' => mb_substr(trim((string)($r['vendor'] ?? '')), 0, 60),
            'invoice_no' => mb_substr(trim((string)($r['invoice_no'] ?? '')), 0, 30), 'date' => $date, 'total' => $total,
            'vat' => is_numeric($r['vat'] ?? null) ? round((float)$r['vat'], 3) : null, 'items' => $items];
}

/** Makes the invoice's lines add up to its total (lines without VAT, rounding), then one expense per group. */
function invoice_rebuild(int $id): void {
    $inv = q('SELECT * FROM invoices WHERE id = ?', [$id])->fetch(); if (!$inv) return;
    foreach (q('SELECT id FROM expenses WHERE invoice_id = ?', [$id])->fetchAll() as $e) {
        $old = ext_on() ? ext_row('expense', (int)$e['id']) : null;
        q('DELETE FROM expenses WHERE id = ?', [(int)$e['id']]);
        if ($old) ext_emit('expense', (int)$e['id'], 'deleted', $old);
    }
    $items = q('SELECT * FROM invoice_items WHERE invoice_id = ? ORDER BY id', [$id])->fetchAll();
    if (!$items || $inv['status'] === 'dup') return;   // a repeat of an earlier invoice is not counted
    $sum = array_sum(array_map(fn($i) => (float)$i['amount'], $items));
    $total = (float)($inv['total'] ?? 0) > 0 ? (float)$inv['total'] : $sum;
    $scale = $sum > 0 ? $total / $sum : 1;
    $by = []; $groups = item_groups();
    foreach ($items as $i) $by[$i['grp']] = ($by[$i['grp']] ?? 0) + (float)$i['amount'] * $scale;
    $by = array_map(fn($v) => round($v, 3), $by);
    arsort($by);
    $diff = round($total - array_sum($by), 3);
    if ($diff != 0.0) $by[array_key_first($by)] = round($by[array_key_first($by)] + $diff, 3);
    $day = $inv['invoice_date'] ?: substr((string)$inv['created_at'], 0, 10);
    foreach ($by as $g => $amt) {
        if ($amt <= 0) continue;
        $n = count(array_filter($items, fn($i) => $i['grp'] === $g));
        $note = trim(($inv['vendor'] ? $inv['vendor'] . ' · ' : '') . "فاتورة" . ($inv['invoice_no'] ? ' ' . $inv['invoice_no'] : '') . " · $n صنف");
        q('INSERT INTO expenses (expense_date, category, amount, note, created_at, created_by, paid_from, receipt, invoice_id) VALUES (?,?,?,?,?,?,?,?,?)',
          [$day, $groups[$g][0] ?? 'أخرى', money($amt), clean($note, 120), now(), $inv['uploaded_by'], $inv['paid_from'], $inv['receipt'], $id]);
        ext_emit('expense', (int)db()->lastInsertId(), 'created');
    }
}

/** Reads waiting invoices (after the response has gone out). */
function invoice_jobs(int $max = 3): void {
    if (ai_key() === '') return;
    // A reading cut off half-way (the hosting stopped it) goes back in the queue
    q("UPDATE invoices SET status = 'pending' WHERE status = 'reading' AND processed_at < ?", [date('Y-m-d H:i:s', time() - 600)]);
    foreach (q("SELECT * FROM invoices WHERE status = 'pending' ORDER BY id LIMIT " . $max)->fetchAll() as $inv) {
        if (q("UPDATE invoices SET status = 'reading', processed_at = ? WHERE id = ? AND status = 'pending'", [now(), (int)$inv['id']])->rowCount() !== 1) continue;
        $r = ai_read_invoice((string)$inv['receipt']);
        if (!$r || isset($r['error']) || empty($r['readable'])) {
            $err = $r['error'] ?? 'unreadable';
            // A failed call (network, overloaded) tries again later; an unreadable photo waits for the owner
            $again = str_starts_with($err, 'ai_http_') && (int)$inv['tries'] < 3;
            q('UPDATE invoices SET status = ?, error = ?, tries = tries + 1 WHERE id = ?', [$again ? 'pending' : 'review', $err, (int)$inv['id']]);
            continue;
        }
        $pdo = db(); $pdo->beginTransaction();
        try {
            q('DELETE FROM invoice_items WHERE invoice_id = ?', [(int)$inv['id']]);
            foreach ($r['items'] as $it)
                q('INSERT INTO invoice_items (invoice_id, name, name_ar, qty, unit, amount, grp) VALUES (?,?,?,?,?,?,?)',
                  [(int)$inv['id'], $it['name'], $it['name_ar'], $it['qty'], $it['unit'], money($it['amount']), $it['group']]);
            $dupOf = invoice_find_repeat((int)$inv['id'], $r);
            q("UPDATE invoices SET status = ?, dup_of = ?, vendor = ?, invoice_no = ?, invoice_date = ?, total = ?, vat = ?, error = NULL, processed_at = ? WHERE id = ?",
              [$dupOf ? 'dup' : 'done', $dupOf, $r['vendor'] ?: null, $r['invoice_no'] ?: null, $r['date'], $r['total'] !== null ? money($r['total']) : null, $r['vat'] !== null ? money($r['vat']) : null, now(), (int)$inv['id']]);
            invoice_rebuild((int)$inv['id']);
            $pdo->commit();
        } catch (Throwable $e) {
            $pdo->rollBack();
            q("UPDATE invoices SET status = 'review', error = ? WHERE id = ?", [mb_substr($e->getMessage(), 0, 150), (int)$inv['id']]);
        }
    }
}

/** An earlier invoice this one repeats: same shop and invoice number, or same shop, date and total (another photo of the same paper). */
function invoice_find_repeat(int $id, array $r): ?int {
    $norm = fn($s) => preg_replace('/[^a-z0-9\x{0600}-\x{06FF}]/u', '', mb_strtolower((string)$s));
    $v = $norm($r['vendor'] ?? ''); $no = $norm($r['invoice_no'] ?? '');
    foreach (q("SELECT id, vendor, invoice_no, invoice_date, total FROM invoices WHERE id <> ? AND status IN ('done','dup') AND dup_of IS NULL", [$id])->fetchAll() as $o) {
        $ov = $norm($o['vendor']); $sameShop = $v !== '' && $ov !== '' && (str_contains($ov, $v) || str_contains($v, $ov));
        if ($no !== '' && $norm($o['invoice_no']) === $no && ($sameShop || $v === '')) return (int)$o['id'];
        if ($sameShop && $r['date'] && $o['invoice_date'] === $r['date'] && $r['total'] !== null && abs((float)$o['total'] - (float)$r['total']) < 0.0005) return (int)$o['id'];
    }
    return null;
}

function invoice_out(array $i, bool $items = false): array {
    $o = ['id' => (int)$i['id'], 'status' => $i['status'], 'vendor' => (string)($i['vendor'] ?? ''), 'invoice_no' => (string)($i['invoice_no'] ?? ''),
          'date' => $i['invoice_date'], 'total' => $i['total'] !== null ? (float)$i['total'] : null, 'vat' => $i['vat'] !== null ? (float)$i['vat'] : null,
          'paid_from' => $i['paid_from'], 'dup_of' => isset($i['dup_of']) ? (int)$i['dup_of'] ?: null : null, 'note' => (string)($i['note'] ?? ''), 'by_user' => (string)($i['by_user'] ?? ''), 'created_at' => $i['created_at'], 'error' => $i['error']];
    if ($items) {
        $g = item_groups();
        $o['items'] = array_map(fn($r) => ['id' => (int)$r['id'], 'name' => $r['name'], 'name_ar' => $r['name_ar'], 'qty' => (float)$r['qty'], 'unit' => (string)$r['unit'],
            'amount' => (float)$r['amount'], 'group' => $r['grp'], 'group_ar' => $g[$r['grp']][0] ?? $r['grp']], q('SELECT * FROM invoice_items WHERE invoice_id = ? ORDER BY id', [(int)$i['id']])->fetchAll());
        $en = []; foreach ($g as $v) $en[$v[0]] = $v[1];
        $o['split'] = array_map(fn($e) => ['category' => $e['category'], 'en' => $en[$e['category']] ?? $e['category'], 'amount' => (float)$e['amount']], q('SELECT category, amount FROM expenses WHERE invoice_id = ? ORDER BY amount DESC', [(int)$i['id']])->fetchAll());
    }
    return $o;
}
