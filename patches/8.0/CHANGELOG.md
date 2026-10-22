## 8.0.30-p1 (2026-10-22)

Sury `1:8.0.30-25+0~20261021.88+debian13~1.gbpabebea`.

- initial import: 93 patches, see SECURITY.md
- `9001` fix of the mysqlnd GHSA-h35g backport (Sury 0074): a malformed row's fields were freed twice before PHP 8.1, same fix as 7.4 9003
- `9002` php-src 67259e45 (GH-14834, ext/xml with libxml2 >= 2.13: PEAR install)

