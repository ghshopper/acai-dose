<?php
// Karak Dose order page. Served through PHP so phones and the host's cache always get the latest copy.
header('Content-Type: text/html; charset=utf-8');
header('Cache-Control: no-store, max-age=0');
readfile(__DIR__ . '/karak.html');
