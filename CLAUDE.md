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
  security-report.py, run-php-tests.sh, tags.sh, readme-tags.sh, upstream-review.sh, chroot-test/
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
  `git -c user.name=… -c user.email=…`), no Co-Authored-By trailer and no mention of Claude / Anthropic in commit
  messages (maintainer's rule). Pushing needs the maintainer's credentials
  (remote origin is SSH: git@github.com:ITMG-Consulting/mammoth-lts.git).
- Variants: cli, fpm, zts, apache (Debian only), as upstream had for these branches.
- Architectures: `linux/amd64` + `linux/arm64`, each built on its own native runner (`ubuntu-24.04-arm`, free and
  unlimited on public repos); never QEMU, compiling PHP emulated is hopeless. Exception **7.0 jessie, amd64 only**:
  docker-library has no arm64 `debian:jessie-slim` (`arm64v8/debian:jessie-slim` exists but drops the "same base as
  the Hub" rule). Declared in `versions.sh` (`noArm64Suites`) -> `versions.json`, read by the CI matrix. All the
  other suites are proven ground: the Hub published arm64 for every one of these tags. Decided 2026-10-24.
- Public repo https://github.com/ITMG-Consulting/mammoth-lts: CI/CD = GitHub Actions, registry = GHCR
  `ghcr.io/itmg-consulting/mammoth-lts` (GITHUB_TOKEN, image name lowercased). Free for public repos, arm64 runners
  included. No self-hosted registry.
- CI builds only what changed on PR/push (generated dirs touched, or known-test-failures for `make test`); weekly
  schedule and manual runs rebuild everything; changes to tools/run-php-tests.sh, tools/tags.sh or the workflow rebuild all.
  `build` and `publish` run one job per (dir, architecture), as reusable workflows (`.github/workflows/build.yml`,
  `publish.yml`) called once per architecture: a matrix is capped at **256 jobs** and dirs x architectures is above
  that (360 on a full rebuild, which is what broke the first arm64 run on 2026-10-24; `generate` now fails early if
  the dir list alone passes 256). `publish` pushes each architecture untagged, by digest, and the `manifest` job
  turns the digests of a dir into the manifest list its tags point to. `make test` and `asan`
  stay amd64: they test the sources, not the image.
  A push diffs against the last successful CI run on main (not the previous push, which left the images of a failed
  run unpublished on 2026-10-23); no such run in the history (e.g. after a force-push) = rebuild all.

## Build specifics already solved (keep them)

- PHP 7 on gcc ≥ 14 / ICU ≥ 75: `-std=gnu99 -Wno-error=incompatible-pointer-types -fno-strict-aliasing`,
  `CXXFLAGS=-std=c++17` (Sury's flags).
- Sury build patches 0047/0048/0050 (pkg-config for freetype/icu/libxml) use `PKG_CHECK_MODULES`: PHP < 7.4 has no
  pkg.m4, so `/usr/share/aclocal/pkg.m4` is appended to `acinclude.m4` (buildconf **and** phpize build aclocal.m4
  from it), then `./buildconf --force` (needs autoconf + make).
- Patched tree is re-packed into `/usr/src/php.tar.xz` so `docker-php-ext-install` builds patched extensions.
- libxml2 ≥ 2.13 breaks ext/xml entity handling (PEAR install fails): php-src 67259e45 (GH-14834) as 9001 for 7.2.
- Debian jessie/stretch/buster/bullseye: sources rewritten to archive.debian.org (`archived_debian`), no `-updates`
  (bullseye LTS ended 2026-08: deb.debian.org pool files already 404). jessie on top of that: Debian never renews
  the signing key of an archived release, so apt can no longer authenticate the archive
  (`expired_archive_key` → `APT::Get::AllowUnauthenticated`; the PHP sources keep their GPG + SHA-256 check).
- Alpine < 3.14 has no `www-data` group in baselayout.
- jessie (the oldest suite): GnuPG 1.4 has no `gpgconf` (`gnupg1` → the `command -v gpgconf` guard of the Docker Hub
  image of that era), and gcc 4.9 rejects `-Wno-error=incompatible-pointer-types` (gcc 5) and `-std=c++17`
  (`old_gcc`; its ICU 52 does not need the C++17 headers the flag is there for).
- gcc >= 14 (alpine3.21+, trixie+, `gcc14` in the template): PHP 7 configure checks fail silently on implicit
  declarations (lost getaddrinfo = no IPv6 name resolution, pread/pwrite, ZEND_MM_ALIGNMENT, POSIX readdir_r...):
  `-fpermissive` in PHP_CFLAGS (as Sury). Check: diff `/usr/local/include/php/main/php_config.h` against an old suite.

## Resume / update routine

```
tools/import-sury-patches.sh <v>        # new Sury revision (weekly CI job "sury" = --check): bumps -pN + CHANGELOG if patches changed
tools/advisory-coverage.py              # php-src advisories not covered → backport or triage
tools/import-php-src-commit.sh <v> <sha> <name> [GHSA]   # backport an official fix (signed commits only)
./versions.sh && ./apply-templates.sh   # regenerate (./update.sh = both + tools/readme-tags.sh)
tools/readme-tags.sh                    # README "Available tags" tables (CI checks they are up to date)
python3 tools/security-report.py        # SECURITY.md (badges CVSS, dates, open advisories); update the README
                                        # "Security coverage" counts by hand
tools/run-asan-tests.sh <v>             # ASan build + the series' own tests (CI job "asan", host needs vm.mmap_rnd_bits=28)
tools/upstream-review.sh --diff         # official image (docker-library/php) commits since fork point 68549643 →
                                        # port to the template or record in upstream.reviewed; --sync-scripts for docker-php-*
```

Adding a branch: write `patches/<v>/sury.conf` (look at `debian/patches/series` of the Sury source package: Debian
build patches are the low numbers, keep only the pkg-config ones current distros need), import, build every suite
(at least one historic and one current suite through tools/chroot-test: their configure options differ), run
`tools/run-php-tests.sh <v>`, record `known-test-failures`, update README status table (`./update.sh` regenerates the
tag tables).

## Testing without Docker (this dev environment has none)

`tools/chroot-test/test-target.sh <repo> <dir>` (WORK=/tmp/mammoth-lts-chroot): pulls the FROM image rootfs from the
Docker Hub registry (fetch-rootfs.sh), replays the Dockerfile in a chroot (dockerfile2sh.py: ENV/RUN/COPY/WORKDIR,
each RUN in a subshell), then the CI smoke tests. Run several targets in parallel lanes (16 cores). Never edit the
script while it runs (bash reads it lazily: copy it first). Chroot artefacts, not Dockerfile bugs: no /proc (old
musl/glibc chmod via /proc/self/fd → tar-noproc-wrapper; php-fpm -t error_log → fake /proc/self/fd/2), apt
"Is /dev/pts mounted?" noise, PEAR "doc.php.net Unable to create XML parser" also happens on current Alpine (harmless).
CI (GitHub Actions) is the real check: build, smoke (`php -v` = version + `-pN`, php-fpm -t,
docker-php-ext-install intl gd bcmath), `make test` vs known failures, advisory coverage.

## State (2026-10-25)

- Published on GHCR, every branch below built and smoke-tested by CI:
  - 7.0 `-p2`: Sury 7.0.33-93 (177 patches) + the 7.1 set re-adapted (9001-9024) +
    GH-14834, mysqlnd double free fix (9025), musl (9026), CVE-2019-18218 (9027, Sury ships it for php7.1 only),
    gh22186 test without OPENSSL_DONT_ZERO_PAD_KEY (9028, the constant came with 7.1), soap tmp_soap scope
    (9029). 66/66 triaged. make test: 67 known failures + bug74093 flaky.
    ASan (2026-10-25): stack-use-after-scope in SoapServer::handle(). 7.0 declares the `zval tmp_soap` holding a
    SOAP_CLASS instance inside the `if (soap_obj == NULL)` block but dereferences soap_obj (= &tmp_soap) through
    the rest of the function; PHP 7.1 declares it at function scope and renames the session branch's pointer to
    tmp_soap_p, 9029 is that change. Upstream 7.0 bug, reached by the GHSA-85c2-q967-79q5 test of Sury 0223. jessie specifics, now in the template: its archive signing keys
    expired (`expired_archive_key` → `APT::Get::AllowUnauthenticated`), GnuPG 1.4 has no `gpgconf` (`gnupg1`), and
    gcc 4.9 has neither `-Wno-error=incompatible-pointer-types` nor `-std=c++17` (`old_gcc`).
  - 7.1 `-p1` (new): Sury 7.1.33-81 (130 patches) + 24 advisories adapted from the 7.2 fixes (9001-9024, ours
    and Sury's php7.2 ones) + GH-14834, mysqlnd double free fix (9025), musl (9026). 66/66 triaged.
    make test: 72 known failures (2018-era test certificates vs OpenSSL 3.5) + bug74093 flaky.
    PHP < 7.2 specifics, now in the template: phpdbg needs readline, `docker-php-ext-enable` writes
    `extension=<name>.so` (no short names), `make test` needs its directories created. alpine3.9 needs
    the musl iconv of the Docker Hub image.
  - 7.2 `-p5`: Sury 7.2.34-66 + 21 php-src backports (9002-9022) + mysqlnd double free fix (9023) + GH-11678 musl.
  - 7.3 `-p2`: Sury 7.3.33-35 (82 patches) + 20 advisories through Sury's php7.4 backports adapted to 7.3
    (9001-9020, 9005 = test infra of Sury 0111) + GH-14834, double free fix (9022), musl (9023), prepare error
    path fix (9024). 66/66 triaged. make test: 72 known failures + bug74093 flaky.
    ASan (2026-10-25): bad free in mysqlnd_stmt_prepare_read_eof(). Since 7.3 the MYSQLND_RES is carved out of the
    result set's memory pool (mysqlnd_result_init), so the mnd_efree() the error path still does frees a pointer
    into the arena; 7.4 destroys the pool in free_result_contents_internal() and dropped the free. Upstream 7.3
    bug, not Sury's, but the GHSA-r6x9 tests reach it -> 9024 calls free_result_internal() (the destructor:
    connection reference + pool). 7.0-7.2 are not affected, their MYSQLND_RES is still mnd_pecalloc()'d.
  - 7.4 `-p4`, 8.0 `-p2`, 8.1 `-p1` (Sury series + local fixes, see each patches/<v>/local.series).
- All php-src advisories triaged on every branch (tools/advisory-coverage.py: 0 untriaged).
- Documented, not fixed (no php-src / Sury fix): 7.0 / 7.1 / 7.2 / 7.3 / 7.4 pdo_firebird `pname[64]` overflow (see Decisions).
- Lessons: `asan`, `advisories`, `sury` and `upstream` are `continue-on-error`, the job shows a green check even
  when the step fails: read its annotations, not the check mark.
  The 7.3 make test / ASan jobs build with their own configure, not the Dockerfile's: before pushing a new
  branch, also run tools/chroot-test on one current suite (the 7.3 `--with-external-pcre` miss, fixed in 33319722).
  A test that changes the openssl/http ServerClientTestCase.inc must keep fixed-port tests working (Sury 0107 → 0111).
  Chroot-test the oldest suite too (jessie needed three fixes the newer ones do not), and re-check an adapted
  backport against the branch's own code: 7.0 has no local `conn` in mysqlnd_stmt_prepare_read_eof() (the 7.1 hunk
  of 9021 did not even compile), and a test shipped with a Sury patch can use a constant the branch lacks (9028).
- Name "Mammoth LTS" kept (decided 2026-10-23, after the TMview check: EU mark MAMMOTH 012399895 in classes 9/38/42).

## Next (agreed with the maintainer)

1. Report the mysqlnd double free of the GHSA-h35g backport privately to Sury (draft /app/report-sury-mysqlnd.txt,
   php7.3 0113 / 7.4 0101 / 8.0 0074; our fix public since 2026-10-22). Not sent yet.
2. 7.0 was the last branch, published on 2026-10-24. arm64 added the same day; its first full rebuild hit the
   256-job matrix cap, fixed on 2026-10-25 (one workflow call per architecture). Next: cosign/SBOM.
3. 9029 (7.0 soap) is not compile-checked yet: this dev container kills long background builds, and the 7.0
   series takes a full rebuild. Either rerun `ASAN=0 tools/run-asan-tests.sh 7.0` in one go, or let the CI
   `asan 7.0` job answer. 9024 (7.3) is checked: builds, and the 141 tests fail identically with and without it.
4. To decide: same class of bad free still open upstream in `mysqlnd_result.c`, `mnd_efree(conn->current_result)`
   on the read_result_metadata() failure path (7.3, 7.4 and 8.0; gone in 8.1). Pool-allocated like the one 9024
   fixes, but no test of the series reaches it, so ASan does not report it.
- Context: started for civ-corse (PHP 7.2 FPM on Alpine, CVE-2026-109618/109619); aria-mare (7.4) and civ-corse
  (7.2) run on Mammoth images in production since 2026-10-22.
