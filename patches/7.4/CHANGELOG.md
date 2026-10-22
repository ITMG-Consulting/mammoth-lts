## 7.4.33-p3 (2026-10-22)

- 9003: fix of the mysqlnd GHSA-h35g / GHSA-r6x9 backports (Sury 0101/0149): a malformed row's fields were freed twice (heap use-after-free reachable by a malicious MySQL server), found by the ASan job

## 7.4.33-p2 (2026-10-22)

- current suites (alpine3.23/3.24, bookworm, trixie) build against the system PCRE2 (--with-external-pcre), like deb.sury.org: the PCRE2 10.35 bundled with php-src 7.4 gets no fixes

## 7.4.33-p1 (2026-10-22)

Sury `1:7.4.33-31+0~20261021.121+debian13~1.gbpe9c428`.

- initial import: 114 patches, see SECURITY.md
- `9001` php-src 3f40b65323 (GHSA-w476-322c-wpvm, CVE-2025-14179, pdo_firebird NUL quoting), adapted to 7.4
- `9002` php-src 67259e45 (GH-14834, ext/xml with libxml2 >= 2.13: PEAR install)

