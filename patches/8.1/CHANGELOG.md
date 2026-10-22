## 8.1.34-p1 (2026-10-22)

Sury `8.1.34-9+0~20261021.82+debian13~1.gbp4e430a`.

- initial import: 36 patches, see SECURITY.md
- `9001` php-src 67259e45 (GH-14834, ext/xml with libxml2 >= 2.13: PEAR install), context adapted to 8.1
- `9002` php-src 577b8ae422 (GH-11678, fopencookie seeker signature on musl >= 1.2.4: alpine3.21+ do not build without it), merged upstream in 8.2 only
- `9003` php-src b3c8afe272 (GH-18743): ZTS JIT tlsgd register, the zts variants do not build on alpine3.22+ (binutils >= 2.44) without it
