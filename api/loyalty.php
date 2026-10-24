<?php
declare(strict_types=1);
// Loyalty: every N cups (or orders) paid on the website, or in the shop with the customer's mobile, earns one free cup.

function setting(string $k, string $default = ''): string {
    $r = q('SELECT v FROM settings WHERE k = ?', [$k])->fetch();
    return $r ? (string)$r['v'] : $default;
}
function set_setting(string $k, string $v): void {
    if (q('SELECT 1 FROM settings WHERE k = ?', [$k])->fetch()) q('UPDATE settings SET v = ? WHERE k = ?', [$v, $k]);
    else q('INSERT INTO settings (k, v) VALUES (?, ?)', [$k, $v]);
}
function loyalty_cfg(): array {
    return ['on' => setting('loyalty_on', '1') === '1', 'need' => max(2, (int)setting('loyalty_need', '5')), 'unit' => setting('loyalty_unit', 'cup') === 'order' ? 'order' : 'cup'];
}

/**
 * Stamps for one phone. Stamps come from website orders marked paid; free cups are not stamped.
 * A free cup is reserved as soon as an order uses it, so it cannot be used twice.
 */
function loyalty_state(string $phone): array {
    $cfg = loyalty_cfg();
    $earned = 0; $used = 0;
    if ($phone !== '') {
        $rows = q("SELECT items, status, payment, free_cups FROM orders WHERE phone = ? AND status <> 'cancelled' AND (source = 'web' OR (source IN ('pos','curb') AND payment IN ('cash','card')))", [$phone])->fetchAll();
        foreach ($rows as $o) {
            $free = (int)$o['free_cups'];
            $used += $free;
            if ($o['status'] !== 'done' || !$o['payment']) continue;
            $cups = 0; foreach (json_decode($o['items'], true) ?: [] as $i) $cups += (int)$i['qty'];
            $paid = max(0, $cups - $free);
            $earned += $cfg['unit'] === 'cup' ? $paid : ($paid > 0 ? 1 : 0);
        }
    }
    // Stamps the owner added or took away by hand
    if ($phone !== '') { $adj = q('SELECT stamp_adj FROM customers WHERE phone = ?', [$phone])->fetch(); $earned = max(0, $earned + (int)($adj['stamp_adj'] ?? 0)); }
    $won = intdiv($earned, $cfg['need']);
    return ['on' => $cfg['on'], 'need' => $cfg['need'], 'unit' => $cfg['unit'], 'stamps' => $earned - $won * $cfg['need'],
            'free' => max(0, $won - $used), 'earned' => $earned, 'used' => $used];
}

/** The customer's card as shown on the card page and in Apple Wallet. */
function card_info(array $c): array {
    $st = loyalty_state($c['phone']);
    return ['name' => $c['name'], 'phone_tail' => substr($c['phone'], -4), 'card' => $c['card_token']] + $st;
}

/** Call after anything that can change a customer's stamps: refreshes their Wallet pass. */
function loyalty_changed(string $phone): void {
    if ($phone === '') return;
    $c = q('SELECT id, card_token FROM customers WHERE phone = ?', [$phone])->fetch();
    if (!$c) return;
    q('UPDATE customers SET pass_updated = ? WHERE id = ?', [time(), (int)$c['id']]);
    require_once __DIR__ . '/gwallet_lib.php';
    wallet_push($c['card_token']);
    gw_update($c['card_token']);
}
