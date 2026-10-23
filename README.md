# Mammoth LTS

Security-patched Docker images for end-of-life PHP: **PHP branches 7.0 → 8.1 with security fixes backported**, built like the
[official `php` image](https://hub.docker.com/_/php) on supported base images (Alpine 3.23 / 3.24, Debian bookworm / trixie).

> [!WARNING]
> These branches are end-of-life upstream. Backports reduce the risk, they do not make an EOL branch supported:
> not every upstream fix applies, and some are not backported yet (see [SECURITY.md](SECURITY.md)).
> Plan your upgrade to a supported PHP version.

> [!NOTE]
> Unofficial builds, not affiliated with the PHP Group nor with Docker. "Mammoth LTS" works with PHP, it is not PHP:
> derived products may not be called "PHP" ([PHP License 3.01](https://www.php.net/license/3_01.txt) clause 4).

## Branches

| Branch | Status | Base images (historic → current) | Patch series |
| --- | --- | --- | --- |
| 7.2 | built, tested | buster, stretch, alpine3.12, alpine3.11 → trixie, bookworm, alpine3.24, alpine3.23 | [patches/7.2](patches/7.2) |
| 7.3 | built, tested | bullseye, buster, alpine3.15, alpine3.14 → trixie, bookworm, alpine3.24, alpine3.23 | [patches/7.3](patches/7.3) |
| 7.4 | built, tested | bullseye, buster, alpine3.16, alpine3.15 → trixie, bookworm, alpine3.24, alpine3.23 | [patches/7.4](patches/7.4) |
| 8.0 | built, tested | bullseye, buster, alpine3.16 → trixie, bookworm, alpine3.24, alpine3.23 | [patches/8.0](patches/8.0) |
| 8.1 | built, tested | trixie, bookworm, alpine3.22, alpine3.21 → trixie, bookworm, alpine3.24, alpine3.23 | [patches/8.1](patches/8.1) |
| 7.0, 7.1 | planned | | |

Each branch is built on the base images docker-library last published it on (same tags as Docker Hub, so
`FROM php:7.2-fpm-alpine3.12` → `FROM ghcr.io/itmg-consulting/mammoth-lts:7.2-fpm-alpine3.12` is a drop-in change; **those OS releases are
EOL themselves**, Debian ones install from archive.debian.org) and on the currently supported ones, which we recommend.
Suite-less and `-alpine` aliases keep their Docker Hub meaning (`7.2-fpm` = buster, `7.2-fpm-alpine` = alpine3.12,
`7.3-fpm` / `7.4-fpm` / `8.0-fpm` = bullseye, `7.3-fpm-alpine` = alpine3.15, `7.4-fpm-alpine` / `8.0-fpm-alpine` = alpine3.16, `8.1-fpm` = trixie,
`8.1-fpm-alpine` = alpine3.22).

A branch is generated once `patches/<version>/series` exists (`versions.sh`). Supported branches (8.2+) are not
built here: use the official image.

## Security coverage

### PHP 7.2 (`7.2.34-p5`)

Every php-src security advisory published since the 7.2.34 release (October 2020) is either fixed or triaged:

| | Advisories |
| --- | --- |
| Published by php-src since 7.2.34 | **66** |
| Fixed by the deb.sury.org series | 30 |
| Fixed by our own backports of php-src commits (`patches/7.2/9002`–`9022`) | 21 |
| Not affecting 7.2 | 14 |
| Not fixed | 1 |
| Not triaged yet | **0** |

60 CVEs are fixed since the 7.2.34 release; [SECURITY.md](SECURITY.md) lists each one with its advisory, CVSS score
and source, and gives the reason for every advisory not fixed.

- **Fixed by deb.sury.org**: among others PHP-CGI argument injection (CVE-2024-4577 and its bypasses),
  `phar_dir_read()` overflow, `proc_open()` command injection, SOAP Apache Map use-after-free, state corruption after
  a bailout (CVE-2026-109618/109619), pgsql `E'...'` SQL injection, FPM status XSS. CVEs from before php-src started
  publishing GitHub advisories (2020–2023) were checked by hand: all fixed by deb.sury.org or not affecting 7.2.
- **Fixed by our backports**: http stream wrapper (header folding, headers without colon, CRLF / basic auth header
  check, redirect `Location` truncation and over-read, credential leak on cross-origin redirects), SOAP (NULL
  dereference, HTTP body overflow, unbounded recursion), mysqlnd heap over-reads (2 advisories), pgsql escaping
  errors, pdo_firebird NUL quoting, OpenSSL (wildcard out-of-bounds read, CN fallback after SAN mismatch), FastCGI
  IPv6 `allowed_clients` bypass, NUL bytes in hostnames and `dns_get_record()`, `XML_OPTION_SKIP_TAGSTART`
  out-of-bounds read, phar tar entry injection, `convert.*` filters info leak, `FILTER_SANITIZE_ENCODED` 0xFF.
  Each backport carries the upstream tests, adapted to 7.2. Patch 9023 fixes a double free that the mysqlnd
  backports (9018 / 9019) introduce before PHP 8.1, found by the AddressSanitizer job.
  For 20 of the 21, we reproduced the flaw on the unpatched
  code and checked that the fix removes it. The 21st (FILTER_SANITIZE_ENCODED) depends on uninitialised stack memory,
  so it cannot be reproduced reliably.
- **Not affecting 7.2**: the vulnerable code does not exist in 7.2 (added in 7.3 to 8.4), Windows-only issues, and
  the `urldecode()` ctype issue, which can only read out of bounds on NetBSD (glibc and musl are safe).
- **Not fixed**: the Marvin attack (CVE-2024-2408), a timing side channel in RSA decryption with PKCS#1 v1.5
  padding. php-src has no fix for it, in any version. The implicit rejection of OpenSSL ≥ 3.2 mitigates it, so
  exposure depends on the base image (tested: an invalid ciphertext is rejected with an error, which is the oracle,
  or implicitly):

  | Base image | OpenSSL | Marvin |
  | --- | --- | --- |
  | trixie, alpine3.24, alpine3.23 | 3.5 | mitigated |
  | bookworm | 3.0 (no backport) | exposed |
  | bullseye, buster, stretch, alpine3.16, alpine3.15, alpine3.12, alpine3.11 | 1.1 | exposed |

  The default tags (`7.2-fpm`, `7.2-fpm-alpine`, `7.3-fpm`, `7.3-fpm-alpine`, `7.4-fpm`, `7.4-fpm-alpine`, `8.0-fpm`, `8.0-fpm-alpine`) are exposed. Only applications that decrypt
  with an RSA private key are concerned: `openssl_private_decrypt()` (its default padding is PKCS#1 v1.5) and
  `openssl_open()`. The attacker must also be able to submit many ciphertexts and time the responses. TLS is not
  affected (PHP does not decrypt RSA as a TLS client; the web server handles TLS). If your application decrypts RSA,
  use a trixie or alpine3.23 / 3.24 image, or switch to OAEP padding (`OPENSSL_PKCS1_OAEP_PADDING`).

### PHP 7.3 (`7.3.33-p1`)

| | Advisories |
| --- | --- |
| Published by php-src since 7.3.33 (November 2021) | **66** |
| Fixed by the deb.sury.org series | 33 |
| Fixed by our own backports (`patches/7.3/9001`–`9020`) | 20 |
| Not affecting 7.3 | 12 |
| Not fixed | 1 |
| Not triaged yet | **0** |

- **deb.sury.org** stopped backporting to 7.3 earlier than to 7.4: the HTTP stream wrapper, SOAP, OpenSSL hostname,
  pgsql, mysqlnd, phar, FastCGI and filter fixes of 2025-2026 are missing from its 7.3 series.
- **Our backports**: deb.sury.org's own 7.4 backports of those fixes, applied to 7.3 (most as-is; the HTTP header
  parser, the credential stripping on cross-origin redirects, pgsql, mysqlnd and SOAP adapted to the 7.3 code, see the
  header of each patch), plus our 7.2 backport of the pdo_firebird NUL quoting (GHSA-w476-322c-wpvm). The patches
  name their php-src commit.
- **Fix of a deb.sury.org backport**: patch 9022, the same mysqlnd double free as 7.4 (9003).
- **Not affecting 7.3**: code added in 7.4 to 8.4 (`??=`, the FPM log flush command, libxml's Content-Type charset,
  mbstring, DOM C14N, bcmath rewrite, TLS peer name reset), and Windows-only issues.
- **Not fixed**: the Marvin attack, as for 7.2 (bullseye, buster and alpine3.14 / 3.15 ship OpenSSL 1.1: exposed).
- Also php-src 67259e45 (GH-14834, PEAR with libxml2 ≥ 2.13), as for the other branches.

### PHP 7.4 (`7.4.33-p4`)

| | Advisories |
| --- | --- |
| Published by php-src since 7.4.33 (November 2022) | **66** |
| Fixed by the deb.sury.org series | 58 |
| Fixed by our own backport of a php-src commit (`patches/7.4/9001`) | 1 |
| Not affecting 7.4 | 6 |
| Not fixed | 1 |
| Not triaged yet | **0** |

- **deb.sury.org** backported almost every advisory to 7.4, up to the PHP 8.2.35 fixes. Its mysqlnd fix
  (GHSA-r6x9-5r99-36j7) is labelled "partial", but only because some upstream tests were adapted to 7.4: the C code
  is the whole upstream fix (29 of its tests fail without it).
- **Fix of a deb.sury.org backport**: patch 9003, the mysqlnd fixes (GHSA-h35g-vwh6-m678, GHSA-r6x9-5r99-36j7)
  freed a malformed row's fields twice before PHP 8.1 (heap use-after-free reachable by a malicious MySQL server),
  found by the AddressSanitizer job.
- **Our backport**: pdo_firebird NUL quoting (GHSA-w476-322c-wpvm), built and tested with Firebird 3 and 4 on
  Debian. Also php-src 67259e45 (GH-14834, not a security fix): without it, PEAR does not install with
  libxml2 ≥ 2.13 (alpine3.23 / 3.24).
- **Not affecting 7.4**: same reasons as 7.2 (code added in PHP 8.x), plus the `??=` use-after-free
  (GHSA-rwp7-7vc6-8477): 7.4 re-evaluates the call on the write path instead of memoizing it, checked with opcode
  dumps.
- **Not fixed**: the Marvin attack, as for 7.2 (exposure per base image in the 7.2 section above).

### PHP 8.0 (`8.0.30-p2`)

| | Advisories |
| --- | --- |
| Published by php-src since 8.0.30 (August 2023) | **63** |
| Fixed by the 8.0.30 release itself (advisories published two days later) | 2 |
| Fixed by the deb.sury.org series | 54 |
| Not affecting 8.0 | 6 |
| Not fixed | 1 |
| Not triaged yet | **0** |

- **deb.sury.org** backported every advisory that affects 8.0, up to the PHP 8.2.35 fixes.
- **Fix of a deb.sury.org backport**: patch 9001, the same mysqlnd double free as 7.4 (9003): before PHP 8.1, buffered
  results keep the decoded rows, so the fields freed on the new error paths were freed again.
- **Not affecting 8.0**: code added in PHP 8.3 / 8.4 (mbstring, DOM C14N, bcmath rewrite, TLS peer name reset), and the
  `??=` use-after-free (GHSA-rwp7-7vc6-8477): like 7.4, 8.0 re-evaluates the call on the write path, checked with
  opcode dumps. The `pdo_firebird` parameter name overflow of 7.x does not exist in 8.0 (bounded copy).
- **Not fixed**: the Marvin attack, as for 7.2 (bullseye, buster and alpine3.16 ship OpenSSL 1.1: exposed).
- Also php-src build fixes (not security fixes): 67259e45 (GH-14834) for PEAR with libxml2 ≥ 2.13, and b3c8afe272
  (GH-18743) for the ZTS JIT with binutils ≥ 2.44 (alpine3.23 / 3.24 `zts` variants).

### PHP 8.1 (`8.1.34-p1`)

| | Advisories |
| --- | --- |
| Published by php-src since 8.1.34 (December 2025) | **29** |
| Fixed by the deb.sury.org series | 25 |
| Not affecting 8.1 | 4 |
| Not triaged yet | **0** |

- 8.1 was supported upstream until December 2025, so the backlog is short: deb.sury.org backported every advisory
  that affects 8.1, up to the PHP 8.2.35 fixes.
- The mysqlnd double free of the 7.x / 8.0 backports does not apply: 8.1 no longer keeps the decoded rows.
- **Not affecting 8.1**: code added in PHP 8.4 (mbstring, DOM C14N, bcmath rewrite) and the TLS peer name reset.
- **Not fixed**: the Marvin attack (published while 8.1 was supported, no php-src fix in any version): mitigated on
  trixie and alpine3.21+ (OpenSSL ≥ 3.2), exposed on bookworm (OpenSSL 3.0).
- Also two php-src build fixes that 8.1 never got upstream: 67259e45 (GH-14834) for PEAR with libxml2 ≥ 2.13, and
  577b8ae422 (GH-11678), the `fopencookie()` seeker signature on musl ≥ 1.2.4 (alpine3.21+); and b3c8afe272
  (GH-18743) for the ZTS JIT with binutils ≥ 2.44 (alpine3.22+ `zts` variants).
- `make test`: 3 Zend tests still expect user code to run after a memory-limit bailout, which the CVE-2026-109618 fix
  forbids; php-src rewrote them with the fix, deb.sury.org did not (listed in `known-test-failures`).

All Alpine images also get php-src 577b8ae422 (GH-11678, merged upstream in 8.2): on musl, PHP declared the
`fopencookie()` seek callback with the wrong signature (a position instead of a pointer to it), so a seek on a PHP
stream used as a C `FILE*` could go to a bogus offset. 7.2 and 7.3 had it on every Alpine image (their configure check looks for a
glibc-only type), 7.4 and 8.0 on alpine3.23 / 3.24 (musl ≥ 1.2.4 dropped `off64_t`); 8.1 did not build there without it.

Outside this tracking:

- **Base OS libraries of the historic suites**: alpine3.11 / 3.12, stretch and buster are end-of-life. Their
  OpenSSL, libxml2, curl, etc. no longer get fixes; only PHP itself is patched. Prefer the current suites, which pick
  up their distribution's updates on every weekly rebuild.
- **PHP bugs fixed upstream without a security advisory**, and PECL extensions you install yourself.
- **Known 7.2 / 7.3 / 7.4 issue with no advisory**: `pdo_firebird` copies a `:name` parameter longer than 71 characters from the
  SQL text into a fixed stack buffer. The SQL text alone can crash the process this way. Not fixed yet.

## Images

```
ghcr.io/itmg-consulting/mammoth-lts:<tag>
```

Tags follow the official image, plus the patch level of the build:

| Tag | Meaning |
| --- | --- |
| `7.2-fpm-alpine3.23`, `7.2.34-fpm-alpine3.23` | latest build of that branch / release |
| `7.2.34-p3-fpm-alpine3.23` | a given patch level |
| `7.2-fpm-alpine`, `7.2-fpm`, `7.2` | same base image as on Docker Hub (alpine3.12 / buster for 7.2) |

Images are rebuilt weekly for base image updates: the PHP inside a `-pN` tag never changes.

### Available tags

Per base image and variant: the tag of the current patch level (pins that exact PHP build), then the branch tags,
which always point to the latest build. Images are `linux/amd64`.

<!-- tags:start (tools/readme-tags.sh) -->
### 7.2 (`7.2.34-p5`)

| | `cli` | `fpm` | `zts` | `apache` |
| --- | --- | --- | --- | --- |
| buster | `7.2.34-p5-cli-buster`<br>`7.2-cli-buster`<br>`7.2-buster`<br>`7.2-cli`<br>`7.2` | `7.2.34-p5-fpm-buster`<br>`7.2-fpm-buster`<br>`7.2-fpm` | `7.2.34-p5-zts-buster`<br>`7.2-zts-buster`<br>`7.2-zts` | `7.2.34-p5-apache-buster`<br>`7.2-apache-buster`<br>`7.2-apache` |
| stretch | `7.2.34-p5-cli-stretch`<br>`7.2-cli-stretch`<br>`7.2-stretch` | `7.2.34-p5-fpm-stretch`<br>`7.2-fpm-stretch` | `7.2.34-p5-zts-stretch`<br>`7.2-zts-stretch` | `7.2.34-p5-apache-stretch`<br>`7.2-apache-stretch` |
| alpine3.12 | `7.2.34-p5-cli-alpine3.12`<br>`7.2-cli-alpine3.12`<br>`7.2-alpine3.12`<br>`7.2-cli-alpine`<br>`7.2-alpine` | `7.2.34-p5-fpm-alpine3.12`<br>`7.2-fpm-alpine3.12`<br>`7.2-fpm-alpine` | `7.2.34-p5-zts-alpine3.12`<br>`7.2-zts-alpine3.12`<br>`7.2-zts-alpine` |  |
| alpine3.11 | `7.2.34-p5-cli-alpine3.11`<br>`7.2-cli-alpine3.11`<br>`7.2-alpine3.11` | `7.2.34-p5-fpm-alpine3.11`<br>`7.2-fpm-alpine3.11` | `7.2.34-p5-zts-alpine3.11`<br>`7.2-zts-alpine3.11` |  |
| trixie | `7.2.34-p5-cli-trixie`<br>`7.2-cli-trixie`<br>`7.2-trixie` | `7.2.34-p5-fpm-trixie`<br>`7.2-fpm-trixie` | `7.2.34-p5-zts-trixie`<br>`7.2-zts-trixie` | `7.2.34-p5-apache-trixie`<br>`7.2-apache-trixie` |
| bookworm | `7.2.34-p5-cli-bookworm`<br>`7.2-cli-bookworm`<br>`7.2-bookworm` | `7.2.34-p5-fpm-bookworm`<br>`7.2-fpm-bookworm` | `7.2.34-p5-zts-bookworm`<br>`7.2-zts-bookworm` | `7.2.34-p5-apache-bookworm`<br>`7.2-apache-bookworm` |
| alpine3.24 | `7.2.34-p5-cli-alpine3.24`<br>`7.2-cli-alpine3.24`<br>`7.2-alpine3.24` | `7.2.34-p5-fpm-alpine3.24`<br>`7.2-fpm-alpine3.24` | `7.2.34-p5-zts-alpine3.24`<br>`7.2-zts-alpine3.24` |  |
| alpine3.23 | `7.2.34-p5-cli-alpine3.23`<br>`7.2-cli-alpine3.23`<br>`7.2-alpine3.23` | `7.2.34-p5-fpm-alpine3.23`<br>`7.2-fpm-alpine3.23` | `7.2.34-p5-zts-alpine3.23`<br>`7.2-zts-alpine3.23` |  |

### 7.3 (`7.3.33-p1`)

| | `cli` | `fpm` | `zts` | `apache` |
| --- | --- | --- | --- | --- |
| bullseye | `7.3.33-p1-cli-bullseye`<br>`7.3-cli-bullseye`<br>`7.3-bullseye`<br>`7.3-cli`<br>`7.3` | `7.3.33-p1-fpm-bullseye`<br>`7.3-fpm-bullseye`<br>`7.3-fpm` | `7.3.33-p1-zts-bullseye`<br>`7.3-zts-bullseye`<br>`7.3-zts` | `7.3.33-p1-apache-bullseye`<br>`7.3-apache-bullseye`<br>`7.3-apache` |
| buster | `7.3.33-p1-cli-buster`<br>`7.3-cli-buster`<br>`7.3-buster` | `7.3.33-p1-fpm-buster`<br>`7.3-fpm-buster` | `7.3.33-p1-zts-buster`<br>`7.3-zts-buster` | `7.3.33-p1-apache-buster`<br>`7.3-apache-buster` |
| alpine3.15 | `7.3.33-p1-cli-alpine3.15`<br>`7.3-cli-alpine3.15`<br>`7.3-alpine3.15`<br>`7.3-cli-alpine`<br>`7.3-alpine` | `7.3.33-p1-fpm-alpine3.15`<br>`7.3-fpm-alpine3.15`<br>`7.3-fpm-alpine` | `7.3.33-p1-zts-alpine3.15`<br>`7.3-zts-alpine3.15`<br>`7.3-zts-alpine` |  |
| alpine3.14 | `7.3.33-p1-cli-alpine3.14`<br>`7.3-cli-alpine3.14`<br>`7.3-alpine3.14` | `7.3.33-p1-fpm-alpine3.14`<br>`7.3-fpm-alpine3.14` | `7.3.33-p1-zts-alpine3.14`<br>`7.3-zts-alpine3.14` |  |
| trixie | `7.3.33-p1-cli-trixie`<br>`7.3-cli-trixie`<br>`7.3-trixie` | `7.3.33-p1-fpm-trixie`<br>`7.3-fpm-trixie` | `7.3.33-p1-zts-trixie`<br>`7.3-zts-trixie` | `7.3.33-p1-apache-trixie`<br>`7.3-apache-trixie` |
| bookworm | `7.3.33-p1-cli-bookworm`<br>`7.3-cli-bookworm`<br>`7.3-bookworm` | `7.3.33-p1-fpm-bookworm`<br>`7.3-fpm-bookworm` | `7.3.33-p1-zts-bookworm`<br>`7.3-zts-bookworm` | `7.3.33-p1-apache-bookworm`<br>`7.3-apache-bookworm` |
| alpine3.24 | `7.3.33-p1-cli-alpine3.24`<br>`7.3-cli-alpine3.24`<br>`7.3-alpine3.24` | `7.3.33-p1-fpm-alpine3.24`<br>`7.3-fpm-alpine3.24` | `7.3.33-p1-zts-alpine3.24`<br>`7.3-zts-alpine3.24` |  |
| alpine3.23 | `7.3.33-p1-cli-alpine3.23`<br>`7.3-cli-alpine3.23`<br>`7.3-alpine3.23` | `7.3.33-p1-fpm-alpine3.23`<br>`7.3-fpm-alpine3.23` | `7.3.33-p1-zts-alpine3.23`<br>`7.3-zts-alpine3.23` |  |

### 7.4 (`7.4.33-p4`)

| | `cli` | `fpm` | `zts` | `apache` |
| --- | --- | --- | --- | --- |
| bullseye | `7.4.33-p4-cli-bullseye`<br>`7.4-cli-bullseye`<br>`7.4-bullseye`<br>`7.4-cli`<br>`7.4` | `7.4.33-p4-fpm-bullseye`<br>`7.4-fpm-bullseye`<br>`7.4-fpm` | `7.4.33-p4-zts-bullseye`<br>`7.4-zts-bullseye`<br>`7.4-zts` | `7.4.33-p4-apache-bullseye`<br>`7.4-apache-bullseye`<br>`7.4-apache` |
| buster | `7.4.33-p4-cli-buster`<br>`7.4-cli-buster`<br>`7.4-buster` | `7.4.33-p4-fpm-buster`<br>`7.4-fpm-buster` | `7.4.33-p4-zts-buster`<br>`7.4-zts-buster` | `7.4.33-p4-apache-buster`<br>`7.4-apache-buster` |
| alpine3.16 | `7.4.33-p4-cli-alpine3.16`<br>`7.4-cli-alpine3.16`<br>`7.4-alpine3.16`<br>`7.4-cli-alpine`<br>`7.4-alpine` | `7.4.33-p4-fpm-alpine3.16`<br>`7.4-fpm-alpine3.16`<br>`7.4-fpm-alpine` | `7.4.33-p4-zts-alpine3.16`<br>`7.4-zts-alpine3.16`<br>`7.4-zts-alpine` |  |
| alpine3.15 | `7.4.33-p4-cli-alpine3.15`<br>`7.4-cli-alpine3.15`<br>`7.4-alpine3.15` | `7.4.33-p4-fpm-alpine3.15`<br>`7.4-fpm-alpine3.15` | `7.4.33-p4-zts-alpine3.15`<br>`7.4-zts-alpine3.15` |  |
| trixie | `7.4.33-p4-cli-trixie`<br>`7.4-cli-trixie`<br>`7.4-trixie` | `7.4.33-p4-fpm-trixie`<br>`7.4-fpm-trixie` | `7.4.33-p4-zts-trixie`<br>`7.4-zts-trixie` | `7.4.33-p4-apache-trixie`<br>`7.4-apache-trixie` |
| bookworm | `7.4.33-p4-cli-bookworm`<br>`7.4-cli-bookworm`<br>`7.4-bookworm` | `7.4.33-p4-fpm-bookworm`<br>`7.4-fpm-bookworm` | `7.4.33-p4-zts-bookworm`<br>`7.4-zts-bookworm` | `7.4.33-p4-apache-bookworm`<br>`7.4-apache-bookworm` |
| alpine3.24 | `7.4.33-p4-cli-alpine3.24`<br>`7.4-cli-alpine3.24`<br>`7.4-alpine3.24` | `7.4.33-p4-fpm-alpine3.24`<br>`7.4-fpm-alpine3.24` | `7.4.33-p4-zts-alpine3.24`<br>`7.4-zts-alpine3.24` |  |
| alpine3.23 | `7.4.33-p4-cli-alpine3.23`<br>`7.4-cli-alpine3.23`<br>`7.4-alpine3.23` | `7.4.33-p4-fpm-alpine3.23`<br>`7.4-fpm-alpine3.23` | `7.4.33-p4-zts-alpine3.23`<br>`7.4-zts-alpine3.23` |  |

### 8.0 (`8.0.30-p2`)

| | `cli` | `fpm` | `zts` | `apache` |
| --- | --- | --- | --- | --- |
| bullseye | `8.0.30-p2-cli-bullseye`<br>`8.0-cli-bullseye`<br>`8.0-bullseye`<br>`8.0-cli`<br>`8.0` | `8.0.30-p2-fpm-bullseye`<br>`8.0-fpm-bullseye`<br>`8.0-fpm` | `8.0.30-p2-zts-bullseye`<br>`8.0-zts-bullseye`<br>`8.0-zts` | `8.0.30-p2-apache-bullseye`<br>`8.0-apache-bullseye`<br>`8.0-apache` |
| buster | `8.0.30-p2-cli-buster`<br>`8.0-cli-buster`<br>`8.0-buster` | `8.0.30-p2-fpm-buster`<br>`8.0-fpm-buster` | `8.0.30-p2-zts-buster`<br>`8.0-zts-buster` | `8.0.30-p2-apache-buster`<br>`8.0-apache-buster` |
| alpine3.16 | `8.0.30-p2-cli-alpine3.16`<br>`8.0-cli-alpine3.16`<br>`8.0-alpine3.16`<br>`8.0-cli-alpine`<br>`8.0-alpine` | `8.0.30-p2-fpm-alpine3.16`<br>`8.0-fpm-alpine3.16`<br>`8.0-fpm-alpine` | `8.0.30-p2-zts-alpine3.16`<br>`8.0-zts-alpine3.16`<br>`8.0-zts-alpine` |  |
| trixie | `8.0.30-p2-cli-trixie`<br>`8.0-cli-trixie`<br>`8.0-trixie` | `8.0.30-p2-fpm-trixie`<br>`8.0-fpm-trixie` | `8.0.30-p2-zts-trixie`<br>`8.0-zts-trixie` | `8.0.30-p2-apache-trixie`<br>`8.0-apache-trixie` |
| bookworm | `8.0.30-p2-cli-bookworm`<br>`8.0-cli-bookworm`<br>`8.0-bookworm` | `8.0.30-p2-fpm-bookworm`<br>`8.0-fpm-bookworm` | `8.0.30-p2-zts-bookworm`<br>`8.0-zts-bookworm` | `8.0.30-p2-apache-bookworm`<br>`8.0-apache-bookworm` |
| alpine3.24 | `8.0.30-p2-cli-alpine3.24`<br>`8.0-cli-alpine3.24`<br>`8.0-alpine3.24` | `8.0.30-p2-fpm-alpine3.24`<br>`8.0-fpm-alpine3.24` | `8.0.30-p2-zts-alpine3.24`<br>`8.0-zts-alpine3.24` |  |
| alpine3.23 | `8.0.30-p2-cli-alpine3.23`<br>`8.0-cli-alpine3.23`<br>`8.0-alpine3.23` | `8.0.30-p2-fpm-alpine3.23`<br>`8.0-fpm-alpine3.23` | `8.0.30-p2-zts-alpine3.23`<br>`8.0-zts-alpine3.23` |  |

### 8.1 (`8.1.34-p1`)

| | `cli` | `fpm` | `zts` | `apache` |
| --- | --- | --- | --- | --- |
| trixie | `8.1.34-p1-cli-trixie`<br>`8.1-cli-trixie`<br>`8.1-trixie`<br>`8.1-cli`<br>`8.1` | `8.1.34-p1-fpm-trixie`<br>`8.1-fpm-trixie`<br>`8.1-fpm` | `8.1.34-p1-zts-trixie`<br>`8.1-zts-trixie`<br>`8.1-zts` | `8.1.34-p1-apache-trixie`<br>`8.1-apache-trixie`<br>`8.1-apache` |
| bookworm | `8.1.34-p1-cli-bookworm`<br>`8.1-cli-bookworm`<br>`8.1-bookworm` | `8.1.34-p1-fpm-bookworm`<br>`8.1-fpm-bookworm` | `8.1.34-p1-zts-bookworm`<br>`8.1-zts-bookworm` | `8.1.34-p1-apache-bookworm`<br>`8.1-apache-bookworm` |
| alpine3.22 | `8.1.34-p1-cli-alpine3.22`<br>`8.1-cli-alpine3.22`<br>`8.1-alpine3.22`<br>`8.1-cli-alpine`<br>`8.1-alpine` | `8.1.34-p1-fpm-alpine3.22`<br>`8.1-fpm-alpine3.22`<br>`8.1-fpm-alpine` | `8.1.34-p1-zts-alpine3.22`<br>`8.1-zts-alpine3.22`<br>`8.1-zts-alpine` |  |
| alpine3.21 | `8.1.34-p1-cli-alpine3.21`<br>`8.1-cli-alpine3.21`<br>`8.1-alpine3.21` | `8.1.34-p1-fpm-alpine3.21`<br>`8.1-fpm-alpine3.21` | `8.1.34-p1-zts-alpine3.21`<br>`8.1-zts-alpine3.21` |  |
| alpine3.24 | `8.1.34-p1-cli-alpine3.24`<br>`8.1-cli-alpine3.24`<br>`8.1-alpine3.24` | `8.1.34-p1-fpm-alpine3.24`<br>`8.1-fpm-alpine3.24` | `8.1.34-p1-zts-alpine3.24`<br>`8.1-zts-alpine3.24` |  |
| alpine3.23 | `8.1.34-p1-cli-alpine3.23`<br>`8.1-cli-alpine3.23`<br>`8.1-alpine3.23` | `8.1.34-p1-fpm-alpine3.23`<br>`8.1-fpm-alpine3.23` | `8.1.34-p1-zts-alpine3.23`<br>`8.1-zts-alpine3.23` |  |

<!-- tags:end -->

## Version number: `-pN`

`php -v` and `PHP_VERSION` report the patch level of the build:

```
$ docker run --rm ghcr.io/itmg-consulting/mammoth-lts:7.2-cli php -v
PHP 7.2.34-p1 (cli) (built: Oct 21 2026 23:57:37) ( NTS )
```

`-pN` is the "patch level" suffix both PHP and Composer understand:
`7.2.34 < 7.2.34-p1 < 7.2.34-p2 < … < 7.2.34-p10 < 7.2.35` for `version_compare()`, and Composer reads
`7.2.34-p10` as `7.2.34.0-patch10` (it satisfies `^7.2`). N goes up each time the PHP code changes:

- `tools/import-sury-patches.sh` bumps it when the imported patches change,
- `tools/bump-patchlevel.sh` / `tools/import-php-src-commit.sh` bump it for a local change,
- a rebuild for base image updates keeps it.

Each bump is recorded in `patches/<version>/CHANGELOG.md`.

## How the images are built

`Dockerfile-linux.template` is the last upstream [docker-library/php](https://github.com/docker-library/php)
template that still supported 8.1 (`68549643`), extended with the conditionals of the older templates for 7.0 → 8.0.
Only the source step differs from upstream:

1. download the php.net tarball, check its SHA-256 and the release managers' GPG signatures (as upstream),
2. apply `patches/<version>/series`,
3. regenerate `configure` (`buildconf`), and put the patched tree back in `/usr/src/php.tar.xz`, so extensions built
   later with `docker-php-ext-install` also come from patched sources,
4. set `PHP_EXTRA_VERSION` to `-pN`.

PHP 7 and 8.0 also get the compiler flags deb.sury.org uses for these versions on current toolchains (gcc 14/15, ICU 75+).

On the current base images (alpine3.23 / 3.24, bookworm, trixie), PHP is built against the system PCRE library, as
deb.sury.org does, instead of the copy bundled with php-src (PCRE 8.41 in 7.2, PCRE2 10.32 in 7.3, 10.35 in 7.4 and 8.0, 10.39 in 8.1), which no longer
gets fixes once the branch is EOL: the distribution maintains it. PHP 7.2 on trixie keeps the bundled copy (Debian
dropped PCRE1), and the historic suites keep it too, like the Docker Hub images. The PCRE headers are then part of
`PHPIZE_DEPS`, since the installed PHP headers include them.

```
./versions.sh          # versions.json, from patches/*/series and the php.net releases API
./apply-templates.sh   # <version>/<suite>/<variant>/Dockerfile + build context (patches included)
```

## Where the fixes come from

1. **[deb.sury.org](https://deb.sury.org/)** — Ondřej Surý maintains backports for every EOL branch (Debian / Ubuntu
   packages). `tools/import-sury-patches.sh <version>` imports the series of the signed source package
   (InRelease signed by `15058500A0235D97F5D10063B188E2B695BD4743` → Sources → `debian.tar.xz`, all checksums verified)
   and keeps what `patches/<version>/sury.conf` selects: the security patches, the few Debian build patches
   current distributions need, never the packaging credits nor the DNS telemetry patch (the import fails if a kept
   patch mentions telemetry or sury.org).
2. **[php-src](https://github.com/php/php-src)** — `tools/advisory-coverage.py` lists every published php-src
   advisory since the branch's last release and checks it against the applied patches. Advisories not covered are
   either backported with `tools/import-php-src-commit.sh <version> <commit> <name> [advisory]` (signed php-src commits
   only, `Origin:` header kept), or triaged in `patches/<version>/triage`:

   ```
   GHSA-xxxx-xxxx-xxxx not-affected: code introduced in 8.3
   GHSA-xxxx-xxxx-xxxx covered: fixed by Sury 0154, which does not name the advisory
   GHSA-xxxx-xxxx-xxxx wontfix: no php-src fix, mitigated by OpenSSL >= 3.2
   GHSA-xxxx-xxxx-xxxx pending: backport in progress
   ```

   It also covers the backport branches the PHP security team publishes itself for critical issues
   (e.g. `PHP-7.4-CVE-2026-109618-109619`).

3. **[docker-library/php](https://github.com/docker-library/php)** — the official image keeps improving its template and
   scripts (build fixes, new base images). `tools/upstream-review.sh` lists its commits since our fork point that are
   not triaged yet in [`upstream.reviewed`](upstream.reviewed) (`ported`, `not-applicable` or `pending`, with the
   reason); `--diff` shows them, `--sync-scripts` copies the version-independent `docker-php-*` scripts as-is.
   CI runs it weekly.

[SECURITY.md](SECURITY.md) (`tools/security-report.py`) lists, per branch, every backported fix with its advisory,
CVSS and publication date, and the php-src advisories not covered yet.

## Tests

- `tools/run-php-tests.sh <version>` builds the patched sources and runs PHP's own test suite on the areas the
  backports touch (Zend, main, session, xml/dom/libxml, openssl, sodium…). Expected failures (test expectations that
  predate libxml2 2.13 / OpenSSL 3, no tty…) are listed in `patches/<version>/known-test-failures`; any other failure
  fails CI.
- CI builds every variant, checks `php -v` / `PHP_VERSION`, `php-fpm -t`, and builds `intl`, `gd` and `bcmath` with
  `docker-php-ext-install`.
- `tools/run-asan-tests.sh <version>` builds the patched sources with AddressSanitizer and runs the tests the patch
  series adds or changes (the regression tests of the backported fixes): a backport that gives the right output but
  still reads or writes out of bounds is reported. Informative CI job for now.
- Without Docker: `tools/chroot-test/test-target.sh . 7.2/buster/fpm` builds a generated dir in a chroot of its base
  image (rootfs pulled from the Docker Hub registry) and runs the same smoke tests.

## Maintenance

| When | Do |
| --- | --- |
| deb.sury.org publishes a new revision | `tools/import-sury-patches.sh <v>`, review the diff, `./update.sh` (versions, templates, README tag tables), `tools/security-report.py` |
| php-src publishes an advisory | `tools/advisory-coverage.py`, then backport (`tools/import-php-src-commit.sh`) or triage |
| a local build fix | add it to `patches/<v>/local.series`, `tools/bump-patchlevel.sh <v> "<reason>"` |
| docker-library/php changes | `tools/upstream-review.sh --diff`, port or record it in `upstream.reviewed` |

## Credits and licenses

Mammoth LTS mostly packages other people's work:

- **[Ondřej Surý](https://deb.sury.org/)** maintains the deb.sury.org packages of every EOL PHP branch. Most of the
  fixes here are his patch series, used as published. If these images are useful to you, consider
  [supporting his work](https://deb.sury.org/#support).
- **Remi Collet** ([remirepo](https://rpms.remirepo.net/)) wrote many of the PHP 7.x adaptations of the upstream fixes
  that the deb.sury.org series carries (27 of the 114 patches for 7.4).
- **The PHP security team and php-src contributors** wrote the fixes and their tests; our own backports (`9*.patch`)
  only adapt their commits, and keep the `Origin:` of each.
- **[docker-library/php](https://github.com/docker-library/php)** (Tianon Gravi, Joseph Ferguson and contributors):
  the Dockerfile template, the `docker-php-*` scripts and the image layout all come from the official image.

Licenses:

- Dockerfiles and scripts: [docker-library/php](https://github.com/docker-library/php) (MIT), see [LICENSE](LICENSE).
- Patch series: [deb.sury.org](https://deb.sury.org/) by Ondřej Surý, `debian/*` under the Expat license; patches
  derived from php-src are under the PHP License 3.01. Paid long-term support for these packages:
  [PHP LTS by Freexian](https://www.freexian.com/lts/php/).
- PHP: the PHP Group, [PHP License 3.01](https://www.php.net/license/3_01.txt).
