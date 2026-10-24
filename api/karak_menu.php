<?php
declare(strict_types=1);
// Karak Dose: first-run menu (from the printed menu), categories, and the owner's login copied from Açaí Dose.

/** Menu sections in the order they show on the till and the order page. */
function karak_categories(): array {
    return [
        ['k' => 'karak', 'en' => 'Karak', 'ar' => 'كرك'],
        ['k' => 'milk', 'en' => 'Milk', 'ar' => 'حليب'],
        ['k' => 'drinks', 'en' => 'Hot & Cold', 'ar' => 'مشروبات'],
        ['k' => 'toast', 'en' => 'Toast', 'ar' => 'توست'],
        ['k' => 'samoon', 'en' => 'Samoon', 'ar' => 'صامون'],
        ['k' => 'rakhal', 'en' => 'Rakhal', 'ar' => 'رخال'],
        ['k' => 'salalah', 'en' => 'Salalah Pie', 'ar' => 'فطيرة صلالة'],
        ['k' => 'croissant', 'en' => 'Croissant', 'ar' => 'كرواسون'],
        ['k' => 'chapati', 'en' => 'Chapati', 'ar' => 'جباتي'],
        ['k' => 'burger', 'en' => 'Burger', 'ar' => 'برجر'],
        ['k' => 'club', 'en' => 'Club', 'ar' => 'كلوب'],
        ['k' => 'wrap', 'en' => 'Wrap', 'ar' => 'راب'],
        ['k' => 'sarookh', 'en' => 'Sarookh', 'ar' => 'صاروخ'],
        ['k' => 'snacks', 'en' => 'Snacks', 'ar' => 'سناكس'],
        ['k' => 'dishes', 'en' => 'Dishes', 'ar' => 'أطباق'],
        ['k' => 'juices', 'en' => 'Juices', 'ar' => 'عصائر'],
        ['k' => 'mojito', 'en' => 'Mojito', 'ar' => 'موهيتو'],
        ['k' => 'passion', 'en' => 'Passion', 'ar' => 'باشن'],
        ['k' => 'roob', 'en' => 'Roob Special', 'ar' => 'روب سبيشل'],
    ];
}

function seed_karak(): void {
    if (q("SELECT 1 FROM settings WHERE k = 'karak_menu'")->fetch()) return;
    if (!(int)q('SELECT COUNT(*) c FROM products')->fetch()['c']) {
        // [en, ar, price] or [en, ar, [small, large]] / [en, ar, ['meal' => x, 'regular' => y]]; null price = hidden until priced
        $fill = [['Cheese', 'جبن', 0], ['Egg Cheese', 'بيض وجبن', 1], ['Oman Chips', 'شيبس عمان', 1], ['Egg Chips', 'بيض وشيبس', 2],
                 ['Honey Cheese', 'عسل وجبن', 1], ['Sausage Cheese', 'نقانق وجبن', 1], ['Chocolate', 'شوكولاتة', 1], ['Labneh', 'لبنة', 1],
                 ['Labneh Zaatar', 'لبنة وزعتر', 1], ['Honey Labneh', 'عسل ولبنة', 1], ['Jam', 'مربى', 1]];
        $bread = fn(string $en, string $ar, array $p) => array_map(fn($f) => ["$en {$f[0]}", "$ar {$f[1]}", $p[$f[2]]], $fill);
        $sl = fn($s, $l) => ['small' => $s, 'large' => $l];
        $mr = fn($m, $r) => ['meal' => $m, 'regular' => $r];
        $menu = [
            'karak' => [['Karak', 'كرك', $sl(0.1, 0.2)], ['Saffron Karak', 'كرك زعفران', $sl(0.2, 0.4)], ['Cardamom Karak', 'كرك هيل', $sl(0.2, 0.4)],
                        ['Ginger Karak', 'كرك زنجبيل', $sl(0.2, 0.4)], ['Zaatar Karak', 'كرك زعتر', $sl(0.2, 0.4)], ['Boost Karak', 'كرك بوست', $sl(0.2, 0.4)],
                        ['Horlicks Karak', 'كرك هورلكس', $sl(0.2, 0.4)], ['Turmeric Karak', 'كرك كركم', $sl(0.2, 0.4)]],
            'milk' => [['Milk', 'حليب', $sl(0.2, 0.4)], ['Saffron Milk', 'حليب زعفران', $sl(0.3, 0.5)], ['Cardamom Milk', 'حليب هيل', $sl(0.2, 0.4)],
                       ['Ginger Milk', 'حليب زنجبيل', $sl(0.2, 0.4)], ['Zaatar Milk', 'حليب زعتر', $sl(0.2, 0.4)], ['Boost Milk', 'حليب بوست', $sl(0.2, 0.4)],
                       ['Horlicks Milk', 'حليب هورلكس', $sl(0.2, 0.4)], ['Turmeric Milk', 'حليب كركم', $sl(0.2, 0.4)]],
            'drinks' => [['Cappuccino', 'كابتشينو', 0.6], ['Hot Chocolate', 'هوت شوكليت', 0.6], ['Red Tea', 'شاي أحمر', 0.1],
                         ['Black Coffee', 'قهوة سوداء', $sl(0.2, 0.4)], ['Nescafe', 'نسكافيه', $sl(0.2, 0.4)], ['Kinza', 'كينزا', 0.3],
                         ['Top Fruit', 'توب فروت', 0.15], ['Water', 'ماي', 0.1], ['Zaatar Tea', 'شاي زعتر', 0.1], ['Green Tea', 'شاي أخضر', 0.2]],
            'toast' => $bread('Toast', 'توست', [0.3, 0.4, 0.5]),
            'samoon' => $bread('Samoon', 'صامون', [0.3, 0.4, 0.5]),
            'rakhal' => $bread('Rakhal', 'رخال', [0.3, 0.4, 0.5]),
            'salalah' => $bread('Salalah Pie', 'فطيرة صلالة', [0.6, 0.6, 0.7]),
            'croissant' => $bread('Croissant', 'كرواسون', [0.4, 0.5, 0.6]),
            'chapati' => $bread('Chapati', 'جباتي', [0.4, 0.5, 0.6]),
            'burger' => [['Chicken Burger', 'برجر دجاج', $mr(0.7, 0.5)], ['Beef Burger', 'برجر لحم', $mr(0.7, 0.5)], ['Hotdog Burger', 'برجر هوت دوج', $mr(0.7, 0.5)],
                         ['Chicken Nuggets', 'برجر ناجتس', $mr(0.8, 0.6)], ['Chicken Filet Burger', 'برجر فيليه دجاج', $mr(0.8, 0.6)],
                         ['Jumbo Prawns Burger', 'برجر روبيان جامبو', $mr(0.8, 0.6)], ['Chicken Tandoori Burger', 'برجر دجاج تندوري', $mr(0.8, 0.6)],
                         ['Khalee Burger', 'برجر خالي', $mr(0.8, 0.6)], ['Vegetable Burger', 'برجر خضار', $mr(0.8, 0.6)], ['Zinger Burger', 'برجر زنجر', $mr(1.0, 0.8)]],
            'club' => [['Zinger Club', 'كلوب زنجر', $mr(1.2, 1.0)], ['Chicken Club', 'كلوب دجاج', $mr(1.2, 1.0)], ['Beef Club', 'كلوب لحم', $mr(1.2, 1.0)],
                       ['Mix Club', 'كلوب مكس', $mr(1.2, 1.0)], ['Muscat Club', 'كلوب مسقط', $mr(1.2, 1.0)], ['Lulu Club', 'كلوب لولو', $mr(1.2, 1.0)],
                       ['Special Club', 'كلوب سبيشل', $mr(1.2, 1.0)], ['Hotdog Club', 'كلوب هوت دوج', $mr(1.2, 1.0)], ['Emarat Club', 'كلوب إمارات', $mr(1.2, 1.0)],
                       ['Vegetable Club', 'كلوب خضار', $mr(null, null)]],
            'wrap' => [['Mathafi Wrap', 'راب مطافي', $mr(1.2, 1.0)], ['Zinger Wrap', 'راب زنجر', $mr(1.2, 1.0)], ['Nuggets Wrap', 'راب ناجتس', $mr(1.2, 1.0)],
                       ['Tikka Wrap', 'راب تكا', $mr(1.2, 1.0)], ['Shish Taouk Wrap', 'راب شيش طاووق', $mr(1.2, 1.0)], ['Vegetable Wrap', 'راب خضار', $mr(1.2, 1.0)],
                       ['Egg Wrap', 'راب بيض', $mr(1.0, 0.8)], ['Hotdog Wrap', 'راب هوت دوج', $mr(1.0, 0.8)]],
            'sarookh' => [['Mathafi Sarookh', 'صاروخ مطافي', 1.0], ['Zinger Sarookh', 'صاروخ زنجر', 1.0], ['Nuggets Sarookh', 'صاروخ ناجتس', 1.0],
                          ['Tikka Sarookh', 'صاروخ تكا', 1.0], ['Shish Taouk Sarookh', 'صاروخ شيش طاووق', 1.0], ['Vegetable Sarookh', 'صاروخ خضار', 1.0],
                          ['Egg Sarookh', 'صاروخ بيض', 0.8], ['Hotdog Sarookh', 'صاروخ هوت دوج', 0.8], ['Falafel Sarookh', 'صاروخ فلافل', 0.8]],
            'snacks' => [['Fries', 'بطاطس', 0.6], ['Corn Flakes', 'كورن فليكس', 0.6], ['Corn Flakes Chocolate', 'كورن فليكس شوكولاتة', 0.6],
                         ['Indomie Chicken', 'إندومي دجاج', 0.6], ['Indomie Vegetable', 'إندومي خضار', 0.6], ['Indomie Meat', 'إندومي لحم', 0.6], ['Indomie Curry', 'إندومي كاري', 0.6]],
            'dishes' => [['Balaleet', 'بلاليط', 1.0], ['Tomato Eggs', 'بيض بالطماطم', 1.0], ['Hotdog Masala with Chapati', 'ماسالا نقانق مع جباتي', 1.0]],
            'juices' => [['Avocado', 'أفوكادو', 1.2], ['Grape', 'عنب', 1.2], ['Pomegranate', 'رمان', 1.2], ['Watermelon', 'بطيخ', 1.0], ['Orange', 'برتقال', 1.2],
                         ['Strawberry', 'فراولة', 1.2], ['Chickoo', 'شيكو', 1.2], ['Mango', 'مانجو', 1.2], ['Banana', 'موز', 1.0], ['Lemon Mint', 'ليمون بالنعناع', 1.0]],
            'mojito' => [['Strawberry Mojito', 'موهيتو فراولة', 1.5], ['Pineapple Mojito', 'موهيتو أناناس', 1.5], ['Watermelon Mojito', 'موهيتو بطيخ', 1.5],
                         ['Pomegranate Mojito', 'موهيتو رمان', 1.5], ['Blackberry Mojito', 'موهيتو بلاك بيري', 1.5], ['Blueberry Mojito', 'موهيتو بلو بيري', 1.5],
                         ['Lemon Mint Mojito', 'موهيتو ليمون ونعناع', 1.5], ['Passion Fruit Mojito', 'موهيتو باشن فروت', 1.5]],
            'passion' => [['Passion Mango', 'باشن مانجو', 1.5], ['Passion Orange', 'باشن برتقال', 1.5], ['Passion Pineapple', 'باشن أناناس', 1.5], ['Passion Pomegranate', 'باشن رمان', 1.5]],
            'roob' => [['Roob Mango', 'روب مانجو', 1.5], ['Roob Strawberry', 'روب فراولة', 1.5], ['Roob Pomegranate', 'روب رمان', 1.5], ['Roob Blueberry', 'روب توت أزرق', 1.5]],
        ];
        $ci = 0;
        foreach ($menu as $cat => $items) {
            $ci++;
            foreach ($items as $i => [$en, $ar, $price]) {
                $sort = $ci * 1000 + $i * 10;
                $variants = is_array($price) ? $price : [null => $price];
                $vi = 0;
                foreach ($variants as $size => $p) {
                    q("INSERT INTO products (name_ar, name_en, img, price, sort, active, kind, cat, size) VALUES (?,?,'',?,?,?,'item',?,?)",
                      [$ar, $en, $p ?? 0, $sort + $vi++, $p === null ? 0 : 1, $cat, $size === '' ? null : $size]);
                }
            }
        }
    }
    set_setting('categories', json_encode(karak_categories(), JSON_UNESCAPED_UNICODE));
    // The owner signs in to Karak Dose with the same username and password as Açaí Dose (staff accounts are made per shop)
    if (!(int)q('SELECT COUNT(*) c FROM users')->fetch()['c']) {
        $owners = db()->query("SELECT username, pass_hash, created_at FROM users WHERE role = 'owner' AND active = 1")->fetchAll();
        foreach ($owners as $o) q("INSERT INTO users (username, pass_hash, role, active, created_at) VALUES (?, ?, 'owner', 1, ?)", [$o['username'], $o['pass_hash'], $o['created_at']]);
    }
    set_setting('karak_menu', '1');
}

/** Kinza and Top Fruit come in flavours: one row per flavour, same price (owner's update after the first menu). */
function karak_flavours(): void {
    if (q("SELECT 1 FROM settings WHERE k = 'karak_flavours'")->fetch()) return;
    $sets = ['Kinza' => ['cola', 'cola_diet', 'lemon', 'lemon_diet', 'citrus', 'berry', 'orange'], 'Top Fruit' => ['mango', 'orange', 'mixed']];
    foreach ($sets as $en => $flav) {
        $p = q("SELECT * FROM products WHERE name_en = ? AND size IS NULL ORDER BY id LIMIT 1", [$en])->fetch();
        if (!$p) continue;
        q('UPDATE products SET size = ? WHERE id = ?', [$flav[0], (int)$p['id']]);
        foreach (array_slice($flav, 1) as $i => $f)
            q("INSERT INTO products (name_ar, name_en, img, price, sort, active, kind, cat, size) VALUES (?,?,'',?,?,?,?,?,?)",
              [$p['name_ar'], $p['name_en'], $p['price'], (int)$p['sort'] + $i + 1, (int)$p['active'], $p['kind'], $p['cat'], $f]);
    }
    set_setting('karak_flavours', '1');
}
