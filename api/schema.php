<?php
declare(strict_types=1);

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
    ];
    foreach ($sql as $s) db()->exec($s);
    $idx = [
        'CREATE INDEX orders_created ON orders (created_at)', 'CREATE INDEX orders_status ON orders (status)',
        'CREATE INDEX sales_date ON channel_sales (sale_date)', 'CREATE INDEX exp_date ON expenses (expense_date)',
        'CREATE INDEX hits_k ON hits (k, at)',
    ];
    foreach ($idx as $s) { try { db()->exec($s); } catch (Throwable $e) { /* already exists */ } }

    // v2: POS sales, car pickup, customer tracking
    $cols = [
        "source VARCHAR(8) NOT NULL DEFAULT 'web'", "payment VARCHAR(8) NULL", "car_plate VARCHAR(20) NULL",
        "car_desc VARCHAR(40) NULL", "token VARCHAR(32) NULL", "arrived_at DATETIME NULL", "created_by INT NULL",
        "commission DECIMAL(10,3) NULL", "n_orders INT NULL",
    ];
    $have = [];
    foreach (q(is_mysql() ? 'SHOW COLUMNS FROM orders' : 'PRAGMA table_info(orders)')->fetchAll() as $c) $have[] = $c['Field'] ?? $c['name'];
    foreach ($cols as $def) {
        $name = strtok($def, ' ');
        if (!in_array($name, $have, true)) db()->exec("ALTER TABLE orders ADD COLUMN $def");
    }
    foreach (['CREATE INDEX orders_token ON orders (token)', 'CREATE INDEX orders_source ON orders (source, day)'] as $s) {
        try { db()->exec($s); } catch (Throwable $e) { /* exists */ }
    }

    if (!(int)q('SELECT COUNT(*) c FROM products')->fetch()['c']) {
        $p = [['آساي سموذي', 'Açaí Smoothie', 'cup-smoothie.png', 3.3, 1],
              ['سجنتشر آساي سموذي', 'Açaí Smoothie Signature', 'cup-signature.png', 3.4, 2],
              ['آساي سموذي مع الفول السوداني', 'Açaí Smoothie with Peanut Butter', 'cup-peanut.png', 3.4, 3]];
        foreach ($p as $r) q('INSERT INTO products (name_ar, name_en, img, price, sort) VALUES (?,?,?,?,?)', $r);
    }
    foreach (['talabat', 'snoonu', 'khedmah'] as $c) {
        if (!q('SELECT 1 FROM channel_commissions WHERE channel = ?', [$c])->fetch())
            q('INSERT INTO channel_commissions (channel, pct) VALUES (?, 0)', [$c]);
    }
}
