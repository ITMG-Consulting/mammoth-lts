# CLAUDE.md

Fork of docker-library/php that publishes **EOL PHP branches (7.0 → 8.1) with security fixes backported**.
Name: **Mammoth LTS** (`mammoth-lts`, elephant = PHP mascot; never put "php" in the product/image name, PHP License
clause 4: "X for PHP" is fine). The maintainer writes
in French; README/SECURITY are English (public project).

## Layout

- `Dockerfile-linux.template` — upstream template of the last 8.1-capable commit (`68549643`) + conditionals of the
  older upstream templates for 7.0 → 8.0 (`vid < …`), + our patch step (`has_patches`) and `-pN` version suffix.
- `versions.sh` → `versions.json` → `apply-templates.sh` → `<version>/<suite>/<variant>/` (generated, committed,
  each dir is a self-contained build context including `patches/`). Never edit generated dirs by hand.
- `patches/<version>/`
  - `sury.conf` — what to keep from the deb.sury.org series (`KEEP_FROM`, `KEEP_EXTRA`, `EXCLUDE` by patch number;
    numbering differs per branch)
  - `series` (generated: Sury kept + `local.series`), `0*.patch` (Sury), `9*.patch` (ours / php-src commits)
  - `SOURCE` (provenance), `debian.changelog` (Sury's, feeds SECURITY.md), `patchlevel` (N of `-pN`), `CHANGELOG.md`
  - `triage` (php-src advisories not covered: `GHSA-… covered|not-affected|wontfix|pending: reason`)
  - `known-test-failures` (expected `make test` failures, see tools/run-php-tests.sh)
- `tools/` — import-sury-patches.sh, import-php-src-commit.sh, bump-patchlevel.sh, advisory-coverage.py,
  security-report.py, run-php-tests.sh, tags.sh, upstream-review.sh, chroot-test/
- `upstream.reviewed` — triage of docker-library/php commits after the fork point (`# base 68549643`)
- `data/` — caches: advisories.json (CVSS/dates), php-src-advisories.json, coverage.json

## Decisions (do not revisit without the maintainer)

- Fix sources: deb.sury.org series first (debian/* is Expat, verified chain InRelease → Sources → debian.tar.xz,
  pinned key `15058500A0235D97F5D10063B188E2B695BD4743`), php-src commits for what Sury lacks. Always excluded:
  packaging credits (0064/0065/0068 for 7.2) and **0144 DNS telemetry to telemetry.sury.org** (import aborts if a kept
  patch mentions telemetry/sury.org).
- PCRE: system library on the current suites (`currentSuites` in versions.json, `system_pcre` in the template), like
  Sury; bundled copy on historic suites and for 7.2 on trixie (no PCRE1 in Debian 13). Decided 2026-10-22.
- No in-house security fixes: an issue neither php-src nor deb.sury.org fixed is documented, not patched (decided
  2026-10-22, e.g. the pdo_firebird `pname[64]` overflow). Build/compat fixes (gcc 14, libxml2 2.13...) are fine, and
  so are fixes of bugs a backport itself introduces (ours or Sury's): patch locally, report to Sury privately
  (ondrej@sury.org, Cc Remi Collet for 7.x adaptations; no private GitHub reporting), drop the patch once Sury ships
  it. E.g. 7.2 9023 / 7.4 9003: the mysqlnd h35g/r6x9 backports freed a malformed row's fields twice before PHP 8.1.
- Version string: `PHP_EXTRA_VERSION="-pN"` (php -v → `7.2.34-p1`). Only `-pN` sorts above the release in
  version_compare() and parses in Composer (`-eolN` sorts below and breaks Composer). N bumps when the applied PHP
  code changes (import with a diff, local patch); never for base-image-only rebuilds.
- Base images per branch: the **last series docker-library published** (same tags as Docker Hub, drop-in; these OS
  are EOL) + **currently supported** ones (alpine3.24/3.23, trixie/bookworm). Historic suites come first in
  `versions.sh`, so `7.2-fpm` / `7.2-fpm-alpine` keep the Hub meaning (buster / alpine3.12).
  Older series the Hub had over the years (e.g. alpine3.6–3.10 for 7.2) are intentionally not built (decided
  2026-10-22): users of those tags move to the last historic suite or to a current one. Current Alpine follows the
  official image (3.24 + 3.23 since 2026-10-22).
- Tags: official naming + `-pN` (`tools/tags.sh`). No dated tags.
- Commits: author `Mathieu GILLOOTS <mathieu@itmg-consulting.com>` (no git identity configured here: pass it with
  `git -c user.name=… -c user.email=…`), plus the Co-Authored-By trailer. Pushing needs the maintainer's credentials
  (remote origin is SSH: git@github.com:ITMG-Consulting/mammoth-lts.git).
- Variants: cli, fpm, zts, apache (Debian only), as upstream had for these branches.
- Public repo https://github.com/ITMG-Consulting/mammoth-lts: CI/CD = GitHub Actions, registry = GHCR
  `ghcr.io/itmg-consulting/mammoth-lts` (GITHUB_TOKEN, image name lowercased). Free for public repos, arm64 runners
  included. No self-hosted registry.
- CI builds only what changed on PR/push (generated dirs touched, or known-test-failures for `make test`); weekly
  schedule and manual runs rebuild everything; changes to tools/run-php-tests.sh, tools/tags.sh or the workflow rebuild all.

## Build specifics already solved (keep them)

- PHP 7 on gcc ≥ 14 / ICU ≥ 75: `-std=gnu99 -Wno-error=incompatible-pointer-types -fno-strict-aliasing`,
  `CXXFLAGS=-std=c++17` (Sury's flags).
- Sury build patches 0047/0048/0050 (pkg-config for freetype/icu/libxml) use `PKG_CHECK_MODULES`: PHP < 7.4 has no
  pkg.m4, so `/usr/share/aclocal/pkg.m4` is appended to `acinclude.m4` (buildconf **and** phpize build aclocal.m4
  from it), then `./buildconf --force` (needs autoconf + make).
- Patched tree is re-packed into `/usr/src/php.tar.xz` so `docker-php-ext-install` builds patched extensions.
- libxml2 ≥ 2.13 breaks ext/xml entity handling (PEAR install fails): php-src 67259e45 (GH-14834) as 9001 for 7.2.
- Debian jessie/stretch/buster/bullseye: sources rewritten to archive.debian.org (`archived_debian`), no `-updates`
  (bullseye LTS ended 2026-08: deb.debian.org pool files already 404).
- Alpine < 3.14 has no `www-data` group in baselayout.
- gcc >= 14 (alpine3.21+, trixie+, `gcc14` in the template): PHP 7 configure checks fail silently on implicit
  declarations (lost getaddrinfo = no IPv6 name resolution, pread/pwrite, ZEND_MM_ALIGNMENT, POSIX readdir_r...):
  `-fpermissive` in PHP_CFLAGS (as Sury). Check: diff `/usr/local/include/php/main/php_config.h` against an old suite.

## Resume / update routine

```
tools/import-sury-patches.sh <v>        # new Sury revision (weekly CI job "sury" = --check): bumps -pN + CHANGELOG if patches changed
tools/advisory-coverage.py              # php-src advisories not covered → backport or triage
tools/import-php-src-commit.sh <v> <sha> <name> [GHSA]   # backport an official fix (signed commits only)
./versions.sh && ./apply-templates.sh   # regenerate
python3 tools/security-report.py        # SECURITY.md (badges CVSS, dates, open advisories); update the README
                                        # "Security coverage" counts by hand
tools/run-asan-tests.sh <v>             # ASan build + the series' own tests (CI job "asan", host needs vm.mmap_rnd_bits=28)
tools/upstream-review.sh --diff         # official image (docker-library/php) commits since fork point 68549643 →
                                        # port to the template or record in upstream.reviewed; --sync-scripts for docker-php-*
```

Adding a branch: write `patches/<v>/sury.conf` (look at `debian/patches/series` of the Sury source package: Debian
build patches are the low numbers, keep only the pkg-config ones current distros need), import, build every suite,
run `tools/run-php-tests.sh <v>`, record `known-test-failures`, update README status table.

## Testing without Docker (this dev environment has none)

`tools/chroot-test/test-target.sh <repo> <dir>` (WORK=/tmp/mammoth-lts-chroot): pulls the FROM image rootfs from the
Docker Hub registry (fetch-rootfs.sh), replays the Dockerfile in a chroot (dockerfile2sh.py: ENV/RUN/COPY/WORKDIR,
each RUN in a subshell), then the CI smoke tests. Run several targets in parallel lanes (16 cores). Never edit the
script while it runs (bash reads it lazily: copy it first). Chroot artefacts, not Dockerfile bugs: no /proc (old
musl/glibc chmod via /proc/self/fd → tar-noproc-wrapper; php-fpm -t error_log → fake /proc/self/fd/2), apt
"Is /dev/pts mounted?" noise, PEAR "doc.php.net Unable to create XML parser" also happens on current Alpine (harmless).
CI (GitHub Actions) is the real check: build, smoke (`php -v` = version + `-pN`, php-fpm -t,
docker-php-ext-install intl gd bcmath), `make test` vs known failures, advisory coverage.

## State (2026-10-22, end of afternoon)

- Repo public, GHCR package public (anonymous pull OK). Pushed: Alpine 3.24/3.23 (0031840d).
- 7.2 = `-p2`, pushed and published (CI run 39759000995 green, 60 jobs): Sury 7.2.34-66 + GH-14834 + 21 php-src security backports (9002-9022, adapted
  to 7.2, each with ported .phpt tests) + `-fpermissive` on gcc 14 suites. All 66 php-src advisories since 7.2.34
  are triaged (`patches/7.2/triage`: 14 not-affected, 1 wontfix = Marvin, 1 covered by Sury 0154 without id).
  tools/run-php-tests.sh 7.2 in an alpine3.23 chroot: no new failure. Also tested before pushing (each new test
  fails on the old code, passes with the fix, no new failure in the extension's tests): pgsql/pdo_pgsql against a
  PostgreSQL 18 server in the chroot; pdo_firebird on Debian bookworm (Firebird 3) and trixie (Firebird 4, embedded
  engine, needs --with-interbase for the 7.2 test harness); soap GHSA-453j by fault injection (LD_PRELOAD shim making
  xmlNodeSetName() leave a NULL name like libxml2 < 2.13: segfault before, fixed after); soap GHSA-cj93 with the real
  2 GiB chunked scenario (~3 GB peak; the gcc 15 build kept the UB overflow check, so the old code did not crash here).
  Every other backport was also run against the old C code (new tests fail before, pass after), except ch8v
  (uninitialised stack byte, not deterministic); wg4p's upstream test passes on old code too (the OOB read goes to
  $index): reproduced separately (heap bytes leaked in $index keys, segfault with a 1 GiB offset).
- Documented, not fixed (no php-src / Sury fix, see Decisions): 7.2 and 7.4 pdo_firebird `firebird_alloc_prepare_stmt` copies `:name` into `pname[64]` unbounded:
  reachable from SQL text (even a `:name` in a comment), stack protector abort from 72 chars (DoS). No php-src advisory.
- docker-library/php: all 21 commits since the fork point triaged in upstream.reviewed.

- 7.4 = `-p1`, pushed and published (CI run 39764790360 green, 117 jobs; 7.2 republished too): Sury 7.4.33-31 (114 patches, KEEP_FROM=0048, 0052/0053 README and 0128
  telemetry excluded) + 9001 w476 pdo_firebird (tested on Debian with Firebird 3/4) + 9002 GH-14834 (PEAR install
  with libxml2 >= 2.13). All 66 advisories triaged (58 Sury, 1 ours, 6 not-affected, Marvin wontfix); Sury's
  "partial" r6x9 is complete on the C side (0151 un-XFAILs the 14 tests). run-php-tests 7.4: 50 known failures
  (OpenSSL 3.5 / libxml2 2.13 / no tty / musl). Chroot builds OK: alpine3.16, alpine3.24, bullseye (fpm); aria-mare's
  extensions (gd jpeg/freetype, intl, zip, opcache, pdo_mysql, mcrypt 1.0.4, apcu) build on alpine3.16 and 3.24.
- Found on the way: bullseye is EOL (archive.debian.org, added to `archived_debian`); `pecl install mcrypt-1.0.4`
  fails on every image incl. the official one ("does not have REST info xml"), use
  `pecl install https://pecl.php.net/get/mcrypt-1.0.4.tgz`; tools/import-sury-patches.sh failed on a first import
  (pipefail on missing series/local.series and on diff), fixed.

## Next (agreed with the maintainer)

1. Migrate aria-mare (/app/aria-mare-website, php:7.4-fpm-alpine = alpine3.16; its
   Dockerfile copies php.ini / pool config to /etc/php7/, which the official image ignores) and civ-corse.
2. Credits (Sury / docker-library) in README, trademark check of "Mammoth LTS" (maintainer).
3. civ-corse (/app/civ-corse/civ-corse) moves to ghcr.io/itmg-consulting/mammoth-lts:7.2-fpm-alpine3.12 or
   …-alpine3.24: test its extensions (mcrypt 1.0.1, apcu), wkhtmltopdf (surnet build for 3.24 / old one for 3.12),
   pdftk, the app.
4. Next branches: 8.0 → 8.1 → 7.3 → 7.1 → 7.0 (same advisory triage per branch); then arm64, cosign/SBOM.
- Context: started for civ-corse (PHP 7.2 FPM on Alpine, CVE-2026-109618/109619).
