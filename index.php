<?php
// Site root: shows the old or the new order page, whichever the owner picked in the app (setting site_design).
// Anything goes wrong reading the setting -> the old page, so ordering never breaks.
declare(strict_types=1);
$design = 'old';
try {
    require __DIR__ . '/api/lib.php';
    require __DIR__ . '/api/loyalty.php';
    $design = setting('site_design', 'old') === 'new' ? 'new' : 'old';
} catch (Throwable $e) { /* keep the old page */ }

header('Content-Type: text/html; charset=utf-8');
header('Cache-Control: no-cache');
if ($design !== 'new') { readfile(__DIR__ . '/index.html'); exit; }

// New page at the root: swap its preview <title>/noindex for the main page's search and share tags.
$old = (string)file_get_contents(__DIR__ . '/index.html');
$new = (string)file_get_contents(__DIR__ . '/new.html');
if (preg_match('~<title>.*?(?=<meta name="theme-color")~s', $old, $m)) {
    $new = preg_replace('~<title>.*?</title>\s*<meta name="robots"[^>]*>\s*~s', str_replace(['\\', '$'], ['\\\\', '\\$'], $m[0]), $new, 1);
}
echo $new;
