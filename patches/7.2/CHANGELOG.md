## 7.2.34-p5 (2026-10-22)

- `9024` php-src 577b8ae422 (GH-11678, fopencookie() seeker signature on musl) on every Alpine image: 7.2's configure test uses the glibc type __off64_t, which musl never had, so the seeker took a position instead of a pointer (context adapted to 7.2)

## 7.2.34-p4 (2026-10-22)

- 9023: fix of our mysqlnd GHSA-h35g / GHSA-r6x9 backports (9018/9019): a malformed row's fields were freed twice (heap use-after-free reachable by a malicious MySQL server), found by the ASan job

## 7.2.34-p3 (2026-10-22)

- current suites (alpine3.23/3.24, bookworm) build against the system PCRE (--with-pcre-regex=/usr), like deb.sury.org: the PCRE 8.41 bundled with php-src 7.2 gets no fixes

## 7.2.34-p2 (2026-10-22)

- 21 php-src security fixes deb.sury.org has not backported (9002-9022, see SECURITY.md); gcc 14 suites (alpine3.23/3.24, trixie) build with -fpermissive so configure detects getaddrinfo, pread/pwrite, ZEND_MM_ALIGNMENT... again

## 7.2.34-p1 (2026-10-21)

Sury `7.2.34-66+0~20261021.122+debian13~1.gbpe0bcd4`.

- initial import: 102 patches, see SECURITY.md

