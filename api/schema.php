<?php
declare(strict_types=1);
require_once __DIR__ . '/loyalty.php';
require_once __DIR__ . '/karak_menu.php';

function create_schema(): void {
    $my = is_mysql();
    $id = $my ? 'INT UNSIGNED AUTO_INCREMENT PRIMARY KEY' : 'INTEGER PRIMARY KEY AUTOINCREMENT';
    $eng = $my ? ' ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci' : '';
    $sql = [
        "CREATE TABLE IF NOT EXISTS users (
            id $id, username VARCHAR(60) NOT NULL UNIQUE, pass_hash VARCHAR(255) NOT NULL,
            role VARCHAR(10) NOT NULL DEFAULT 'staff', active TINYINT NOT NULL DEFAULT 1, created_at DATETIME NOT NULL)$eng",
        "CREATE TABLE IF NOT EXISTS products (
            id $id, name_ar VARCHAR(120) NOT NULL, name_en VARCHAR(120) NOT NULL, img VARCHAR(120) NOT NULL DEFAULT '',
            price DECIMAL(10,3) NOT NULL, sort INT NOT NULL DEFAULT 0, active TINYINT NOT NULL DEFAULT 1)$eng",
        "CREATE TABLE IF NOT EXISTS orders (
            id $id, order_no INT NOT NULL, day DATE NOT NULL, created_at DATETIME NOT NULL, updated_at DATETIME NOT NULL,
            customer_name VARCHAR(60) NOT NULL, phone VARCHAR(20) NOT NULL, pickup_time VARCHAR(10), notes VARCHAR(300),
            items TEXT NOT NULL, total DECIMAL(10,3) NOT NULL, status VARCHAR(12) NOT NULL DEFAULT 'new')$eng",
        "CREATE TABLE IF NOT EXISTS day_counters (day DATE PRIMARY KEY, last_no INT NOT NULL)$eng",
        "CREATE TABLE IF NOT EXISTS channel_commissions (channel VARCHAR(12) PRIMARY KEY, pct DECIMAL(5,2) NOT NULL DEFAULT 0)$eng",
        "CREATE TABLE IF NOT EXISTS channel_sales (
            id $id, sale_date DATE NOT NULL, channel VARCHAR(12) NOT NULL, gross DECIMAL(10,3) NOT NULL,
            commission_pct DECIMAL(5,2) NOT NULL DEFAULT 0, commission DECIMAL(10,3) NOT NULL DEFAULT 0,
            orders_count INT NULL, note VARCHAR(120), created_at DATETIME NOT NULL)$eng",
        "CREATE TABLE IF NOT EXISTS expenses (
            id $id, expense_date DATE NOT NULL, category VARCHAR(60) NOT NULL, amount DECIMAL(10,3) NOT NULL,
            note VARCHAR(120), created_at DATETIME NOT NULL)$eng",
        "CREATE TABLE IF NOT EXISTS hits (k VARCHAR(120) NOT NULL, at DATETIME NOT NULL)$eng",
        "CREATE TABLE IF NOT EXISTS ingredients (
            id $id, k VARCHAR(20) NOT NULL DEFAULT '', name_ar VARCHAR(60) NOT NULL, name_en VARCHAR(60) NOT NULL,
            unit VARCHAR(4) NOT NULL DEFAULT 'g', pack_price DECIMAL(10,3) NOT NULL DEFAULT 0, pack_qty DECIMAL(12,3) NOT NULL DEFAULT 0,
            unit_cost DECIMAL(14,6) NOT NULL DEFAULT 0, sort INT NOT NULL DEFAULT 0, active TINYINT NOT NULL DEFAULT 1)$eng",
        "CREATE TABLE IF NOT EXISTS recipe_items (
            id $id, product_id INT NOT NULL, ingredient_id INT NOT NULL, qty DECIMAL(10,3) NOT NULL)$eng",
        "CREATE TABLE IF NOT EXISTS purchases (
            id $id, purchase_date DATE NOT NULL, ingredient_id INT NOT NULL, qty DECIMAL(12,3) NOT NULL, price DECIMAL(10,3) NOT NULL,
            note VARCHAR(120) NULL, expense_id INT NULL, created_at DATETIME NOT NULL)$eng",
        "CREATE TABLE IF NOT EXISTS stock_counts (
            id $id, counted_at DATETIME NOT NULL, ingredient_id INT NOT NULL, qty DECIMAL(12,3) NOT NULL, expected DECIMAL(12,3) NULL)$eng",
        "CREATE TABLE IF NOT EXISTS toppings (
            id $id, k VARCHAR(20) NOT NULL, name_ar VARCHAR(60) NOT NULL, name_en VARCHAR(60) NOT NULL,
            price DECIMAL(10,3) NOT NULL DEFAULT 0, sort INT NOT NULL DEFAULT 0, active TINYINT NOT NULL DEFAULT 1)$eng",
        "CREATE TABLE IF NOT EXISTS customers (
            id $id, phone VARCHAR(20) NOT NULL UNIQUE, name VARCHAR(60) NOT NULL DEFAULT '', car_plate VARCHAR(20) NULL,
            car_desc VARCHAR(40) NULL, offers TINYINT NOT NULL DEFAULT 0, note VARCHAR(200) NULL,
            created_at DATETIME NOT NULL, updated_at DATETIME NOT NULL,
            card_token VARCHAR(32) NULL, wallet_auth VARCHAR(32) NULL, pass_updated INT NOT NULL DEFAULT 0, gwallet TINYINT NOT NULL DEFAULT 0)$eng",
        "CREATE TABLE IF NOT EXISTS settings (k VARCHAR(40) PRIMARY KEY, v TEXT NOT NULL)$eng",
        "CREATE TABLE IF NOT EXISTS wallet_devices (device_id VARCHAR(100) PRIMARY KEY, push_token VARCHAR(200) NOT NULL, updated_at DATETIME NOT NULL)$eng",
        "CREATE TABLE IF NOT EXISTS wallet_regs (device_id VARCHAR(100) NOT NULL, serial VARCHAR(40) NOT NULL, created_at DATETIME NOT NULL, PRIMARY KEY (device_id, serial))$eng",
    ];
    foreach ($sql as $s) xq($s);
    $idx = [
        'CREATE INDEX orders_created ON orders (created_at)', 'CREATE INDEX orders_status ON orders (status)',
        'CREATE INDEX sales_date ON channel_sales (sale_date)', 'CREATE INDEX exp_date ON expenses (expense_date)',
        'CREATE INDEX hits_k ON hits (k, at)',
    ];
    foreach ($idx as $s) { try { xq($s); } catch (Throwable $e) { /* already exists */ } }

    // v2: POS sales, car pickup, customer tracking
    $cols = [
        "source VARCHAR(8) NOT NULL DEFAULT 'web'", "payment VARCHAR(8) NULL", "car_plate VARCHAR(20) NULL",
        "car_desc VARCHAR(40) NULL", "token VARCHAR(32) NULL", "arrived_at DATETIME NULL", "created_by INT NULL",
        "commission DECIMAL(10,3) NULL", "n_orders INT NULL",
        "free_cups INT NOT NULL DEFAULT 0", "discount DECIMAL(10,3) NOT NULL DEFAULT 0",
    ];
    $have = [];
    foreach (q(is_mysql() ? 'SHOW COLUMNS FROM orders' : 'PRAGMA table_info(orders)')->fetchAll() as $c) $have[] = $c['Field'] ?? $c['name'];
    foreach ($cols as $def) {
        $name = strtok($def, ' ');
        if (!in_array($name, $have, true)) xq("ALTER TABLE orders ADD COLUMN $def");
    }
    foreach (['CREATE INDEX orders_token ON orders (token)', 'CREATE INDEX orders_source ON orders (source, day)'] as $s) {
        try { xq($s); } catch (Throwable $e) { /* exists */ }
    }

    try { xq('CREATE INDEX orders_phone ON orders (phone)'); } catch (Throwable $e) { /* exists */ }
    // v4: loyalty card per customer (secret link + Apple Wallet)
    $have = [];
    foreach (q(is_mysql() ? 'SHOW COLUMNS FROM customers' : 'PRAGMA table_info(customers)')->fetchAll() as $c) $have[] = $c['Field'] ?? $c['name'];
    foreach (["card_token VARCHAR(32) NULL", "wallet_auth VARCHAR(32) NULL", "pass_updated INT NOT NULL DEFAULT 0", "gwallet TINYINT NOT NULL DEFAULT 0", "stamp_adj INT NOT NULL DEFAULT 0"] as $def) {
        $name = strtok($def, ' ');
        if (!in_array($name, $have, true)) xq("ALTER TABLE customers ADD COLUMN $def");
    }
    foreach (q('SELECT id FROM customers WHERE card_token IS NULL')->fetchAll() as $r)
        q('UPDATE customers SET card_token = ?, wallet_auth = ? WHERE id = ?', [bin2hex(random_bytes(16)), bin2hex(random_bytes(16)), (int)$r['id']]);
    try { xq('CREATE UNIQUE INDEX customers_card ON customers (card_token)'); } catch (Throwable $e) { /* exists */ }
    foreach ((BIZ === 'karak' ? ['loyalty_on' => '0', 'loyalty_need' => '10', 'loyalty_unit' => 'order'] : ['loyalty_on' => '1', 'loyalty_need' => '5', 'loyalty_unit' => 'cup']) as $k => $v)
        if (!q('SELECT 1 FROM settings WHERE k = ?', [$k])->fetch()) q('INSERT INTO settings (k, v) VALUES (?, ?)', [$k, $v]);
    // v3: one customer record per phone number, filled from earlier website orders
    if (!(int)q('SELECT COUNT(*) c FROM customers')->fetch()['c']) {
        $rows = q("SELECT phone, customer_name, car_plate, car_desc, created_at FROM orders WHERE phone <> '' ORDER BY id")->fetchAll();
        foreach ($rows as $r) save_customer($r['phone'], $r['customer_name'], $r['car_plate'], $r['car_desc'], null, $r['created_at']);
    }

    // v7: bowls. kind = cup | bowl (ready) | build (customer picks toppings); short description per product
    $have = [];
    foreach (q(is_mysql() ? 'SHOW COLUMNS FROM products' : 'PRAGMA table_info(products)')->fetchAll() as $c) $have[] = $c['Field'] ?? $c['name'];
    foreach (["kind VARCHAR(10) NOT NULL DEFAULT 'cup'", 'desc_ar VARCHAR(300) NULL', 'desc_en VARCHAR(300) NULL',
              'cat VARCHAR(20) NULL', 'size VARCHAR(10) NULL', 'soldout TINYINT NOT NULL DEFAULT 0'] as $def) {
        $name = strtok($def, ' ');
        if (!in_array($name, $have, true)) xq("ALTER TABLE products ADD COLUMN $def");
    }
    if (BIZ === 'acai') {
        if (!(int)q('SELECT COUNT(*) c FROM products')->fetch()['c']) {
            $p = [['آساي سموذي', 'Açaí Smoothie', 'cup-smoothie.png', 3.3, 1],
                  ['سجنتشر آساي سموذي', 'Açaí Smoothie Signature', 'cup-signature.png', 3.4, 2],
                  ['آساي سموذي مع الفول السوداني', 'Açaí Smoothie with Peanut Butter', 'cup-peanut.png', 3.4, 3]];
            foreach ($p as $r) q('INSERT INTO products (name_ar, name_en, img, price, sort) VALUES (?,?,?,?,?)', $r);
        }
        if (!q("SELECT 1 FROM settings WHERE k = 'bowls_added'")->fetch()) {
            // Hidden until the owner sets prices and switches them on
            q("INSERT INTO products (name_ar, name_en, img, price, sort, active, kind) VALUES (?,?,?,?,?,0,'bowl')", ['أساي باول', 'Açaí Bowl', 'bowl.png', 0, 30]);
            q("INSERT INTO products (name_ar, name_en, img, price, sort, active, kind) VALUES (?,?,?,?,?,0,'build')", ['اصنع أساي باولك', 'Build Your Açaí Bowl', 'bowl-build.png', 0, 31]);
            if (!(int)q('SELECT COUNT(*) c FROM toppings')->fetch()['c']) {
                $t = [['pb', 'زبدة فول سوداني', 'Peanut butter'], ['straw', 'فراولة', 'Strawberry'], ['granola', 'جرانولا', 'Granola'],
                      ['blue', 'توت أزرق', 'Blueberry'], ['rasp', 'توت أحمر', 'Raspberry'], ['banana', 'موز', 'Banana'],
                      ['almond', 'لوز مقروش', 'Crushed almonds'], ['honey', 'عسل', 'Honey']];
                foreach ($t as $i => $r) q('INSERT INTO toppings (k, name_ar, name_en, price, sort, active) VALUES (?,?,?,0,?,1)', [$r[0], $r[1], $r[2], $i + 1]);
            }
            q("INSERT INTO settings (k, v) VALUES ('bowls_added', '1')");
        }

        // v6: Mini (8oz) version of each cup, hidden until the owner sets a price and switches it on
        if (!q("SELECT 1 FROM products WHERE name_en LIKE 'Mini %' LIMIT 1")->fetch()) {
            foreach (q("SELECT * FROM products WHERE name_en NOT LIKE 'Mini %' AND kind = 'cup' ORDER BY sort, id")->fetchAll() as $r)
                q('INSERT INTO products (name_ar, name_en, img, price, sort, active) VALUES (?,?,?,?,?,0)',
                  ['ميني ' . $r['name_ar'], 'Mini ' . $r['name_en'], $r['img'], 2.4, (int)$r['sort'] + 10]);
        }
        // Owner's Mini prices, applied once (later changes are made in Settings)
        if (!q("SELECT 1 FROM settings WHERE k = 'mini_prices_set'")->fetch()) {
            q("UPDATE products SET price = 2.4 WHERE name_en = 'Mini Açaí Smoothie' AND price IN (0, 2.4)");
            q("UPDATE products SET price = 2.5 WHERE name_en IN ('Mini Açaí Smoothie Signature', 'Mini Açaí Smoothie with Peanut Butter') AND price IN (0, 2.4)");
            q("UPDATE products SET price = 2.4 WHERE name_en LIKE 'Mini %' AND price = 0");
            q("INSERT INTO settings (k, v) VALUES ('mini_prices_set', '1')");
        }
        // v8: ingredients and recipes (grams per cup), so the dashboard can work out what each drink costs
        if (!q("SELECT 1 FROM settings WHERE k = 'costing_added'")->fetch()) {
            $ing = [['acai', 'كريمة الأساي', 'Açaí cream', 'g'], ['straw', 'فراولة', 'Strawberry', 'g'], ['rasp', 'توت أحمر', 'Raspberry', 'g'],
                    ['blue', 'توت أزرق', 'Blueberry', 'g'], ['milk', 'حليب اللوز', 'Almond milk', 'g'], ['pb', 'زبدة الفول السوداني', 'Peanut butter', 'g'],
                    ['granola', 'جرانولا', 'Granola', 'g'], ['banana', 'موز', 'Banana', 'g'],
                    ['cup12', 'كوب 12oz', 'Cup 12oz', 'pc'], ['lid12', 'غطا 12oz', 'Lid 12oz', 'pc'], ['cup8', 'كوب 8oz', 'Cup 8oz', 'pc'], ['lid8', 'غطا 8oz', 'Lid 8oz', 'pc'],
                    ['straw_pc', 'مصاصة', 'Straw', 'pc']];
            $id = [];
            foreach ($ing as $i => $r) { q('INSERT INTO ingredients (k, name_ar, name_en, unit, sort) VALUES (?,?,?,?,?)', [$r[0], $r[1], $r[2], $r[3], $i + 1]); $id[$r[0]] = (int)db()->lastInsertId(); }
            // The owner's recipes (12oz) and the Mini (8oz) at two thirds; garnish is added to the same ingredient
            $pack12 = ['cup12' => 1, 'lid12' => 1, 'straw_pc' => 1]; $pack8 = ['cup8' => 1, 'lid8' => 1, 'straw_pc' => 1];
            $rec = [
                'Açaí Smoothie' => ['straw' => 30, 'rasp' => 30, 'blue' => 20, 'milk' => 80, 'acai' => 180] + $pack12,
                'Açaí Smoothie with Peanut Butter' => ['pb' => 30, 'straw' => 20, 'rasp' => 20, 'blue' => 10, 'milk' => 70, 'acai' => 170] + $pack12,
                'Açaí Smoothie Signature' => ['blue' => 10, 'straw' => 20, 'rasp' => 20, 'granola' => 30, 'milk' => 50, 'pb' => 15, 'banana' => 70, 'acai' => 150] + $pack12,
                'Mini Açaí Smoothie' => ['straw' => 20, 'rasp' => 20, 'blue' => 15, 'milk' => 55, 'acai' => 120] + $pack8,
                'Mini Açaí Smoothie with Peanut Butter' => ['pb' => 18, 'straw' => 15, 'rasp' => 15, 'blue' => 7, 'milk' => 45, 'acai' => 115] + $pack8,
                'Mini Açaí Smoothie Signature' => ['blue' => 7, 'straw' => 15, 'rasp' => 15, 'granola' => 22, 'milk' => 35, 'pb' => 10, 'banana' => 45, 'acai' => 100] + $pack8,
            ];
            foreach ($rec as $name => $items) {
                $p = q('SELECT id FROM products WHERE name_en = ?', [$name])->fetch(); if (!$p) continue;
                if (q('SELECT 1 FROM recipe_items WHERE product_id = ?', [(int)$p['id']])->fetch()) continue;
                foreach ($items as $k => $g) q('INSERT INTO recipe_items (product_id, ingredient_id, qty) VALUES (?,?,?)', [(int)$p['id'], $id[$k], $g]);
            }
            q("INSERT INTO settings (k, v) VALUES ('costing_added', '1')");
        }
    } else {
        seed_karak();
    }

    // Delivery apps this shop sells through (each with its commission, set by the owner)
    foreach ((BIZ === 'karak' ? ['talabat', 'tmdone', 'khedmah', 'snoonu'] : ['talabat', 'snoonu', 'khedmah']) as $c) {
        if (!q('SELECT 1 FROM channel_commissions WHERE channel = ?', [$c])->fetch())
            q('INSERT INTO channel_commissions (channel, pct) VALUES (?, 0)', [$c]);
    }
}
