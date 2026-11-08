<?php
declare(strict_types=1);
// Link to the owner's management system.
//  • Pull: a read-only API opened with a secret key (X-Api-Key header): orders, delivery-app sales, expenses,
//    daily summaries, and an event feed (every create / change / delete, in order) to stay in sync.
//  • Push: every event is also POSTed to the management system's webhook URL, signed with HMAC-SHA256,
//    retried with back-off until it answers 2xx. Same event ids in both, so the receiver can de-duplicate.
// Each shop (Açaí Dose, Karak Dose) has its own key, webhook and events.

const EXT_KEEP_DAYS = 60;          // events kept this long for the pull feed
const EXT_MAX_TRIES = 30;          // webhook gives up on an event after this many failed tries

function ext_shop(): string { return BIZ === 'karak' ? 'karak_dose' : 'acai_dose'; }
function ext_on(): bool { return setting('ext_on', '0') === '1'; }
function ext_one_off(string $cat): bool { return (bool)preg_match('/معدات|أجهزة|تأسيس|ديكور/u', $cat); }
function ext_pay_name(?string $p): string {
    if ($p === 'cash') return 'Cash';
    if ($p === 'card') return 'Card';
    return CHANNEL_NAMES[$p ?? ''][0] ?? '';
}

function ext_order(array $o): array {
    $items = [];
    foreach (json_decode((string)$o['items'], true) ?: [] as $l) {
        $q = (int)($l['qty'] ?? 0); $p = (float)($l['price'] ?? 0);
        $it = ['product_id' => (int)($l['product_id'] ?? 0), 'name_en' => (string)($l['name_en'] ?? ''), 'name_ar' => (string)($l['name_ar'] ?? ''),
               'qty' => $q, 'unit_price' => money($p), 'line_total' => money($p * $q)];
        if (!empty($l['note'])) $it['note'] = (string)$l['note'];
        if (!empty($l['custom'])) $it['custom'] = true;
        $items[] = $it;
    }
    $total = (float)$o['total']; $comm = (float)($o['commission'] ?? 0);
    return [
        'id' => (int)$o['id'], 'ref' => order_ref((string)$o['day'], (int)$o['order_no']), 'date' => (string)$o['day'],
        'created_at' => (string)$o['created_at'], 'updated_at' => (string)$o['updated_at'],
        'source' => (string)($o['source'] ?? 'web'),            // pos = till, web = order page, curb = taken at the car
        'status' => (string)$o['status'],                       // new | preparing | ready | done | cancelled
        'counts_in_sales' => $o['status'] !== 'cancelled',
        'payment' => $o['payment'] ?? null, 'payment_name' => ext_pay_name($o['payment'] ?? null),
        'total' => money($total), 'commission' => money($comm), 'net' => money($total - $comm),
        'discount' => money($o['discount'] ?? 0), 'free_cups' => (int)($o['free_cups'] ?? 0),
        'orders' => $o['n_orders'] === null ? 1 : (int)$o['n_orders'],   // >1 only for lines imported from the Excel template
        'items' => $items,
    ];
}
function ext_app_sale(array $r): array {
    return ['id' => (int)$r['id'], 'date' => (string)$r['sale_date'], 'channel' => (string)$r['channel'], 'channel_name' => ext_pay_name($r['channel']),
            'gross' => money($r['gross']), 'commission_pct' => (float)$r['commission_pct'], 'commission' => money($r['commission']),
            'net' => money((float)$r['gross'] - (float)$r['commission']), 'orders' => $r['orders_count'] === null ? null : (int)$r['orders_count'],
            'note' => (string)($r['note'] ?? ''), 'created_at' => (string)$r['created_at']];
}
function ext_expense(array $r): array {
    return ['id' => (int)$r['id'], 'date' => (string)$r['expense_date'], 'category' => (string)$r['category'], 'amount' => money($r['amount']),
            'one_off' => ext_one_off((string)$r['category']), 'note' => (string)($r['note'] ?? ''), 'created_at' => (string)$r['created_at'],
            'paid_from' => (string)($r['paid_from'] ?? 'bank'), 'entered_at' => ($r['created_by'] ?? null) !== null ? 'pos' : 'owner'];
}
function ext_row(string $kind, int $id): ?array {
    if ($kind === 'order') { $r = q('SELECT * FROM orders WHERE id = ?', [$id])->fetch(); return $r ? ext_order($r) : null; }
    if ($kind === 'app_sale') { $r = q('SELECT * FROM channel_sales WHERE id = ?', [$id])->fetch(); return $r ? ext_app_sale($r) : null; }
    if ($kind === 'expense') { $r = q('SELECT * FROM expenses WHERE id = ?', [$id])->fetch(); return $r ? ext_expense($r) : null; }
    return null;
}

/** Records an event (order.created, expense.deleted, …) for the feed and the webhook. */
function ext_emit(string $kind, int $id, string $action, ?array $data = null): void {
    if (!ext_on()) return;
    if ($data === null) $data = $action === 'deleted' ? ['id' => $id] : ext_row($kind, $id);
    if ($data === null) return;
    q('INSERT INTO ext_events (kind, ref_id, action, data, created_at, tries) VALUES (?,?,?,?,?,0)',
      [$kind, $id, $action, json_encode($data, JSON_UNESCAPED_UNICODE), now()]);
    $GLOBALS['ext_new'] = true;
}

/** One day in numbers: sales by payment, commissions, expenses by category, net. */
function ext_day(string $day): array {
    $pay = []; $sales = 0.0; $comm = 0.0; $n = 0; $cancelled = 0;
    foreach (q('SELECT total, payment, commission, n_orders, status FROM orders WHERE day = ?', [$day])->fetchAll() as $o) {
        if ($o['status'] === 'cancelled') { $cancelled++; continue; }
        $t = (float)$o['total']; $sales += $t; $comm += (float)($o['commission'] ?? 0); $n += $o['n_orders'] === null ? 1 : (int)$o['n_orders'];
        $k = (string)($o['payment'] ?? '') ?: 'unpaid';
        $pay[$k] = ($pay[$k] ?? 0) + $t;
    }
    foreach (q('SELECT channel, gross, commission, orders_count FROM channel_sales WHERE sale_date = ?', [$day])->fetchAll() as $r) {
        $sales += (float)$r['gross']; $comm += (float)$r['commission']; $n += (int)($r['orders_count'] ?? 0);
        $pay[$r['channel']] = ($pay[$r['channel']] ?? 0) + (float)$r['gross'];
    }
    $exp = []; $expT = 0.0; $once = 0.0;
    foreach (q('SELECT category, SUM(amount) s FROM expenses WHERE expense_date = ? GROUP BY category', [$day])->fetchAll() as $r) {
        $exp[$r['category']] = money($r['s']); $expT += (float)$r['s']; if (ext_one_off($r['category'])) $once += (float)$r['s'];
    }
    return ['date' => $day, 'orders' => $n, 'cancelled' => $cancelled, 'sales' => money($sales), 'by_payment' => $pay ? array_map('money', $pay) : new stdClass(),
            'commission' => money($comm), 'net_sales' => money($sales - $comm),
            'expenses_total' => money($expT), 'expenses_running' => money($expT - $once), 'expenses_one_off' => money($once), 'expenses' => $exp ?: new stdClass(),
            'net' => money($sales - $comm - $expT)];
}

/** After midnight: a day.closed event with yesterday's numbers (and any missed days, up to a week). */
function ext_close_days(): void {
    if (!ext_on()) return;
    $y = date('Y-m-d', strtotime('-1 day'));
    $done = setting('ext_day_done', '');
    if ($done >= $y) return;
    set_setting('ext_day_done', $y);   // claim first so two requests don't both send
    $from = max($done === '' ? $y : date('Y-m-d', strtotime($done . ' +1 day')), date('Y-m-d', strtotime('-7 day')));
    for ($d = $from; $d <= $y; $d = date('Y-m-d', strtotime($d . ' +1 day'))) ext_emit('day', (int)str_replace('-', '', $d), 'closed', ext_day($d));
}

function ext_envelope(array $e): array {
    return ['event_id' => (int)$e['id'], 'shop' => ext_shop(), 'type' => $e['kind'] . '.' . $e['action'],
            'created_at' => (string)$e['created_at'], 'data' => json_decode((string)$e['data'], true)];
}

/** POSTs a signed JSON body; returns [http code (0 = no answer), error text]. */
function ext_post(string $url, string $secret, string $type, int $id, string $body, int $timeout): array {
    $ts = (string)time();
    $headers = ['Content-Type: application/json', 'User-Agent: Dose-Webhooks/1', "X-Dose-Event: $type", "X-Dose-Event-Id: $id",
                'X-Dose-Shop: ' . ext_shop(), "X-Dose-Timestamp: $ts", 'X-Dose-Signature: sha256=' . hash_hmac('sha256', "$ts.$body", $secret)];
    if (function_exists('curl_init')) {
        $c = curl_init($url);
        curl_setopt_array($c, [CURLOPT_POST => true, CURLOPT_POSTFIELDS => $body, CURLOPT_HTTPHEADER => $headers, CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT => $timeout, CURLOPT_CONNECTTIMEOUT => min(3, $timeout), CURLOPT_FOLLOWLOCATION => false,
            CURLOPT_PROTOCOLS => CURLPROTO_HTTPS]);
        curl_exec($c);
        $code = (int)curl_getinfo($c, CURLINFO_HTTP_CODE); $err = curl_error($c);
        curl_close($c);
        return [$code, $err];
    }
    $ctx = stream_context_create(['http' => ['method' => 'POST', 'header' => implode("\r\n", $headers), 'content' => $body, 'timeout' => $timeout, 'ignore_errors' => true, 'follow_location' => 0]]);
    $r = @file_get_contents($url, false, $ctx);
    $code = 0;
    foreach ($http_response_header ?? [] as $h) if (preg_match('~^HTTP/\S+\s+(\d{3})~', $h, $m)) $code = (int)$m[1];
    return [$code, $r === false && !$code ? 'no answer' : ''];
}

/** Sends waiting events to the webhook, oldest first; stops at the first failure so order is kept. */
function ext_flush(int $max = 25, int $timeout = 5): array {
    $url = setting('ext_hook_url', ''); $secret = setting('ext_hook_secret', '');
    if ($url === '' || $secret === '') return ['sent' => 0, 'skipped' => 'no_webhook'];
    // One sender at a time
    if (!q("SELECT 1 FROM settings WHERE k = 'ext_lock'")->fetch()) q("INSERT INTO settings (k, v) VALUES ('ext_lock', '0')");
    $until = time() + $max * ($timeout + 1) + 5;
    if (q("UPDATE settings SET v = ? WHERE k = 'ext_lock' AND CAST(v AS " . (is_mysql() ? 'UNSIGNED' : 'INTEGER') . ') < ?', [(string)$until, time()])->rowCount() !== 1)
        return ['sent' => 0, 'skipped' => 'busy'];
    $sent = 0; $failed = null;
    try {
        $rows = q('SELECT * FROM ext_events WHERE pushed_at IS NULL AND tries < ? AND (next_try IS NULL OR next_try <= ?) ORDER BY id LIMIT ' . (int)$max, [EXT_MAX_TRIES, now()])->fetchAll();
        foreach ($rows as $e) {
            $env = ext_envelope($e);
            [$code, $err] = ext_post($url, $secret, $env['type'], $env['event_id'], json_encode($env, JSON_UNESCAPED_UNICODE), $timeout);
            if ($code >= 200 && $code < 300) {
                q('UPDATE ext_events SET pushed_at = ?, last_error = NULL WHERE id = ?', [now(), (int)$e['id']]);
                set_setting('ext_last_ok', now()); $sent++;
                continue;
            }
            $tries = (int)$e['tries'] + 1;
            $wait = min(6 * 3600, 30 * (2 ** min($tries, 12)));   // 1 min, 2, 4 … up to 6 hours
            $msg = mb_substr($code ? "HTTP $code" : ($err ?: 'no answer'), 0, 200);
            q('UPDATE ext_events SET tries = ?, next_try = ?, last_error = ? WHERE id = ?', [$tries, date('Y-m-d H:i:s', time() + $wait), $msg, (int)$e['id']]);
            set_setting('ext_last_error', now() . ' · ' . $msg);
            $failed = $msg;
            break;
        }
    } finally {
        q("UPDATE settings SET v = '0' WHERE k = 'ext_lock'");
    }
    return ['sent' => $sent, 'error' => $failed];
}

/** Runs after the response has gone out: day summaries, webhook sending, clean-up. */
function ext_after_request(): void {
    try {
        if (!ext_on()) return;
        $hook = setting('ext_hook_url', '') !== '';
        $closeDays = setting('ext_day_done', '') < date('Y-m-d', strtotime('-1 day'));
        $retry = $hook && mt_rand(1, 15) === 1;
        if (empty($GLOBALS['ext_new']) && !$closeDays && !$retry) return;
        $async = false;
        if (function_exists('litespeed_finish_request')) { litespeed_finish_request(); $async = true; }
        elseif (function_exists('fastcgi_finish_request')) { fastcgi_finish_request(); $async = true; }
        ignore_user_abort(true);
        ext_close_days();
        if ($hook) $async ? ext_flush(25, 5) : ext_flush(3, 2);
        if (mt_rand(1, 50) === 1) q('DELETE FROM ext_events WHERE created_at < ?', [date('Y-m-d H:i:s', time() - EXT_KEEP_DAYS * 86400)]);
    } catch (Throwable $e) { /* never break a sale */ }
}

/** The management system's key, from the X-Api-Key header (or Authorization: Bearer). */
function ext_auth(): void {
    $k = (string)($_SERVER['HTTP_X_API_KEY'] ?? '');
    if ($k === '' && preg_match('/^Bearer\s+(\S+)$/i', (string)($_SERVER['HTTP_AUTHORIZATION'] ?? $_SERVER['REDIRECT_HTTP_AUTHORIZATION'] ?? ''), $m)) $k = $m[1];
    $want = setting('ext_key_hash', '');
    if ($k === '' || $want === '' || !ext_on() || !hash_equals($want, hash('sha256', $k))) {
        rate_limit('ext_bad', 20, 600);
        fail('bad_key', 401);
    }
    header('Access-Control-Allow-Origin: *');
}
function ext_range(): array {
    $f = valid_date($_GET['from'] ?? date('Y-m-d')); $t = valid_date($_GET['to'] ?? $f);
    if ($f > $t) [$f, $t] = [$t, $f];
    if ((strtotime($t) - strtotime($f)) / 86400 > 370) fail('range_too_long');
    return [$f, $t];
}
/** Paging by id: ?after=<last id seen>&limit=… */
function ext_page(int $def = 500): array { return [max(0, (int)($_GET['after'] ?? 0)), max(1, min(1000, (int)($_GET['limit'] ?? $def)))]; }
function ext_paged(string $key, array $rows, int $limit): array {
    $more = count($rows) > $limit; $rows = array_slice($rows, 0, $limit);
    return ['shop' => ext_shop(), $key => $rows, 'next_after' => $rows ? end($rows)['id'] : null, 'more' => $more];
}

/** Handles the ext_* actions; returns false when the action is not one of them. */
function ext_handle(string $a, array $in, callable $post): bool {
    switch ($a) {
    // ---------- management system (key) ----------
    case 'ext_ping':
        ext_auth();
        out(['ok' => true, 'shop' => ext_shop(), 'time' => now(), 'timezone' => 'Asia/Muscat', 'currency' => 'OMR']);

    case 'ext_events':   // every change, in order: keep ?after = the last event_id you processed
        ext_auth();
        [$after, $limit] = ext_page(200);
        $rows = q('SELECT * FROM ext_events WHERE id > ? ORDER BY id LIMIT ' . ($limit + 1), [$after])->fetchAll();
        $more = count($rows) > $limit; $rows = array_slice($rows, 0, $limit);
        $ev = array_map('ext_envelope', $rows);
        out(['shop' => ext_shop(), 'events' => $ev, 'next_after' => $ev ? end($ev)['event_id'] : $after, 'more' => $more]);

    case 'ext_orders':
        ext_auth();
        [$f, $t] = ext_range(); [$after, $limit] = ext_page();
        $rows = q('SELECT * FROM orders WHERE day BETWEEN ? AND ? AND id > ? ORDER BY id LIMIT ' . ($limit + 1), [$f, $t, $after])->fetchAll();
        out(ext_paged('orders', array_map('ext_order', $rows), $limit) + ['from' => $f, 'to' => $t]);

    case 'ext_app_sales':   // delivery-app sales the owner enters as daily totals
        ext_auth();
        [$f, $t] = ext_range(); [$after, $limit] = ext_page();
        $rows = q('SELECT * FROM channel_sales WHERE sale_date BETWEEN ? AND ? AND id > ? ORDER BY id LIMIT ' . ($limit + 1), [$f, $t, $after])->fetchAll();
        out(ext_paged('app_sales', array_map('ext_app_sale', $rows), $limit) + ['from' => $f, 'to' => $t]);

    case 'ext_expenses':
        ext_auth();
        [$f, $t] = ext_range(); [$after, $limit] = ext_page();
        $rows = q('SELECT * FROM expenses WHERE expense_date BETWEEN ? AND ? AND id > ? ORDER BY id LIMIT ' . ($limit + 1), [$f, $t, $after])->fetchAll();
        out(ext_paged('expenses', array_map('ext_expense', $rows), $limit) + ['from' => $f, 'to' => $t]);

    case 'ext_summary':   // day by day, plus totals for the period
        ext_auth();
        [$f, $t] = ext_range();
        if ((strtotime($t) - strtotime($f)) / 86400 > 92) fail('range_too_long');
        $days = []; $tot = ['orders' => 0, 'sales' => 0.0, 'commission' => 0.0, 'net_sales' => 0.0, 'expenses_total' => 0.0, 'net' => 0.0, 'by_payment' => []];
        for ($d = $f; $d <= $t; $d = date('Y-m-d', strtotime($d . ' +1 day'))) {
            $x = ext_day($d); $days[] = $x;
            foreach (['orders', 'sales', 'commission', 'net_sales', 'expenses_total', 'net'] as $k) $tot[$k] += $x[$k];
            foreach ((array)$x['by_payment'] as $k => $v) $tot['by_payment'][$k] = ($tot['by_payment'][$k] ?? 0) + $v;
        }
        foreach (['sales', 'commission', 'net_sales', 'expenses_total', 'net'] as $k) $tot[$k] = money($tot[$k]);
        $tot['by_payment'] = $tot['by_payment'] ? array_map('money', $tot['by_payment']) : new stdClass();
        out(['shop' => ext_shop(), 'from' => $f, 'to' => $t, 'days' => $days, 'totals' => $tot]);

    case 'ext_flush':   // for a cron job, if the server can't send after the response
        ext_auth();
        out(['ok' => true] + ext_flush(50, 8));

    // ---------- owner app: set up the link ----------
    case 'ext_config':
        need('owner');
        $url = setting('ext_hook_url', '');
        out(['on' => ext_on(), 'has_key' => setting('ext_key_hash', '') !== '', 'key_hint' => setting('ext_key_hint', ''),
             'hook_url' => $url, 'shop' => ext_shop(),
             'base_url' => 'https://' . ($_SERVER['HTTP_HOST'] ?? 'order.acaiee.com') . (BIZ === 'karak' ? '/karak' : '') . '/api/api.php',
             'pending' => $url === '' ? 0 : (int)q('SELECT COUNT(*) c FROM ext_events WHERE pushed_at IS NULL AND tries < ?', [EXT_MAX_TRIES])->fetch()['c'],
             'failed' => (int)q('SELECT COUNT(*) c FROM ext_events WHERE pushed_at IS NULL AND tries >= ?', [EXT_MAX_TRIES])->fetch()['c'],
             'events' => (int)q('SELECT COUNT(*) c FROM ext_events')->fetch()['c'],
             'last_ok' => setting('ext_last_ok', ''), 'last_error' => setting('ext_last_error', '')]);

    case 'ext_key_new':   // a new key (shown once); the old one stops working
        $post(); need('owner');
        $key = 'dose_' . bin2hex(random_bytes(20));
        set_setting('ext_key_hash', hash('sha256', $key));
        set_setting('ext_key_hint', substr($key, -4));
        if (!ext_on()) { set_setting('ext_on', '1'); set_setting('ext_day_done', date('Y-m-d', strtotime('-1 day'))); }
        out(['key' => $key]);

    case 'ext_hook_save':   // webhook address; a signing secret is made the first time (shown once)
        $post(); need('owner');
        $url = trim((string)($in['url'] ?? ''));
        if ($url !== '' && (!filter_var($url, FILTER_VALIDATE_URL) || !str_starts_with(strtolower($url), 'https://') || strlen($url) > 300)) fail('bad_url');
        set_setting('ext_hook_url', $url);
        $secret = null;
        if ($url !== '' && (setting('ext_hook_secret', '') === '' || !empty($in['new_secret']))) {
            $secret = 'whsec_' . bin2hex(random_bytes(24));
            set_setting('ext_hook_secret', $secret);
        }
        if ($url !== '' && !ext_on()) { set_setting('ext_on', '1'); set_setting('ext_day_done', date('Y-m-d', strtotime('-1 day'))); }
        if ($url !== '') q("UPDATE ext_events SET tries = 0, next_try = NULL WHERE pushed_at IS NULL");   // try the waiting ones again
        set_setting('ext_last_error', '');
        out(['ok' => true, 'secret' => $secret]);

    case 'ext_hook_test':   // sends a ping now and says what the management system answered
        $post(); need('owner');
        $url = setting('ext_hook_url', ''); $secret = setting('ext_hook_secret', '');
        if ($url === '' || $secret === '') fail('no_webhook');
        $env = ['event_id' => 0, 'shop' => ext_shop(), 'type' => 'ping', 'created_at' => now(), 'data' => ['message' => 'test']];
        [$code, $err] = ext_post($url, $secret, 'ping', 0, json_encode($env, JSON_UNESCAPED_UNICODE), 8);
        out(['ok' => $code >= 200 && $code < 300, 'code' => $code, 'error' => $err]);

    case 'ext_off':   // turn the link off: key and webhook stop working
        $post(); need('owner');
        foreach (['ext_key_hash', 'ext_key_hint', 'ext_hook_url', 'ext_hook_secret', 'ext_last_error', 'ext_day_done'] as $k) set_setting($k, '');
        set_setting('ext_on', '0');
        q('DELETE FROM ext_events');
        out(['ok' => true]);
    }
    return false;
}
