<?php
declare(strict_types=1);
require __DIR__ . '/lib.php';
require __DIR__ . '/schema.php';

header('Content-Type: text/html; charset=utf-8');
$msg = ''; $done = false; $err = '';

try {
    create_schema();
    $hasUsers = (int)q('SELECT COUNT(*) c FROM users')->fetch()['c'] > 0;
} catch (Throwable $e) {
    $err = 'ما قدرنا نتصل بقاعدة البيانات. تأكد من البيانات في ملف api/config.php';
    $hasUsers = true;
}

if (!$err && !$hasUsers && $_SERVER['REQUEST_METHOD'] === 'POST') {
    $un = trim((string)($_POST['username'] ?? '')); $pw = (string)($_POST['password'] ?? '');
    if (!preg_match('/^[A-Za-z0-9_.-]{3,60}$/', $un)) $msg = 'اسم المستخدم: حروف إنجليزية أو أرقام، ٣ حروف أو أكثر';
    elseif (strlen($pw) < 8) $msg = 'كلمة السر ٨ حروف أو أكثر';
    elseif ($pw !== (string)($_POST['password2'] ?? '')) $msg = 'كلمتين السر مب متطابقة';
    else {
        q('INSERT INTO users (username, pass_hash, role, active, created_at) VALUES (?,?,?,1,?)', [$un, password_hash($pw, PASSWORD_DEFAULT), 'owner', now()]);
        $done = true;
    }
}
?><!doctype html>
<html lang="ar" dir="rtl"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>إعداد أساي دوز</title><link rel="stylesheet" href="../assets/app.css"></head>
<body><div class="login-wrap"><form class="login card" method="post">
<img src="../assets/logo-purple.png" alt="Açaí Dose">
<?php if ($err): ?>
  <h1 class="lal">في مشكلة</h1><p class="err"><?= htmlspecialchars($err) ?></p>
<?php elseif ($done): ?>
  <h1 class="lal">تم الإعداد</h1>
  <p style="font-weight:700;line-height:1.7;margin:0">الجداول جاهزة وحساب صاحب المحل انسوى.</p>
  <a class="btn" href="../dashboard.html">افتح الداشبورد</a>
<?php elseif ($hasUsers): ?>
  <h1 class="lal">الإعداد خالص</h1>
  <p style="font-weight:700;line-height:1.7;margin:0">النظام مجهز من قبل. هذي الصفحة ما تسوي شي الحين.</p>
  <a class="btn" href="../dashboard.html">الداشبورد</a>
<?php else: ?>
  <h1 class="lal">حساب صاحب المحل</h1>
  <div class="field"><label for="u">اسم المستخدم (إنجليزي)</label><input id="u" name="username" autocomplete="username" required dir="ltr"></div>
  <div class="field"><label for="p">كلمة السر</label><input id="p" name="password" type="password" autocomplete="new-password" minlength="8" required></div>
  <div class="field"><label for="p2">أعد كلمة السر</label><input id="p2" name="password2" type="password" autocomplete="new-password" minlength="8" required></div>
  <div class="err" role="alert"><?= htmlspecialchars($msg) ?></div>
  <button class="btn" type="submit">سوّ الحساب</button>
<?php endif; ?>
</form></div></body></html>
