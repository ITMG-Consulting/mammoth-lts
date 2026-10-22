## 8.0.30-p2 (2026-10-22)

- `9003` php-src 577b8ae422 (GH-11678, fopencookie() seeker signature on musl) on alpine3.23/3.24 (musl >= 1.2.4 has no off64_t): the seeker took a position instead of a pointer, fseek() on a stream cast to FILE* (e.g. curl CURLOPT_FILE) went to a bogus offset
- `9004` php-src b3c8afe272 (GH-18743): ZTS JIT tlsgd register, the zts variants do not build on alpine3.22+ (binutils >= 2.44) without it

## 8.0.30-p1 (2026-10-22)

Sury `1:8.0.30-25+0~20261021.88+debian13~1.gbpabebea`.

- initial import: 93 patches, see SECURITY.md
- `9001` fix of the mysqlnd GHSA-h35g backport (Sury 0074): a malformed row's fields were freed twice before PHP 8.1, same fix as 7.4 9003
- `9002` php-src 67259e45 (GH-14834, ext/xml with libxml2 >= 2.13: PEAR install)

