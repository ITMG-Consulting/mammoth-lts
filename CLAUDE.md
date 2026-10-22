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
  - `triage` (php-src advisories not covered: `GHSA-… not-affected|wontfix|pending: reason`)
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
- Debian jessie/stretch/buster: sources rewritten to archive.debian.org (`archived_debian`), no `-updates`.
- Alpine < 3.14 has no `www-data` group in baselayout.

## Resume / update routine

```
tools/import-sury-patches.sh <v>        # new Sury revision: bumps -pN + CHANGELOG if patches changed; review the diff
tools/advisory-coverage.py              # php-src advisories not covered → backport or triage
tools/import-php-src-commit.sh <v> <sha> <name> [GHSA]   # backport an official fix (signed commits only)
./versions.sh && ./apply-templates.sh   # regenerate
python3 tools/security-report.py        # SECURITY.md (badges CVSS, dates, open advisories)
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

## State (2026-10-22, end of day)

- Repo public, pushed: https://github.com/ITMG-Consulting/mammoth-lts (main = 57b27d0a). CI run 39704404884 left
  running overnight (first full 7.2 build + make test + publish to GHCR). Local commit 24583e1a (Alpine 3.24/3.23)
  **not pushed yet**: push once that run is over (a push cancels the running one).
- 7.2: Sury 7.2.34-66 + GH-14834, `-p1`. All 8 suites built + smoke-tested in chroot (alpine3.11/3.12/3.23/3.24,
  stretch/buster/bookworm/trixie), make test clean on alpine3.23 and on GitHub CI. Debian stretch/buster smoke test
  fixed in CI (libfreetype6-dev).
- docker-library/php: all 21 commits since the fork point triaged in upstream.reviewed.

## Tomorrow (agreed with the maintainer)

1. Check run 39704404884 (fix failures), push 24583e1a, remind the maintainer to make the GHCR package public
   (Packages → mammoth-lts → Package settings → Change visibility).
2. Credits (Sury / docker-library) in README, trademark check of "Mammoth LTS" (maintainer).
3. Triage the 38 php-src advisories not covered for 7.2 (`tools/advisory-coverage.py`): backport with
   tools/import-php-src-commit.sh or record in patches/7.2/triage. Security priority.
4. civ-corse (/app/civ-corse/civ-corse) moves to ghcr.io/itmg-consulting/mammoth-lts:7.2-fpm-alpine3.12 or
   …-alpine3.24: test its extensions (mcrypt 1.0.1, apcu), wkhtmltopdf (surnet build for 3.24 / old one for 3.12),
   pdftk, the app.
5. Next branches: 7.4 → 8.0 → 8.1 → 7.3 → 7.1 → 7.0; then arm64, cosign/SBOM.
- Context: started for civ-corse (PHP 7.2 FPM on Alpine, CVE-2026-109618/109619).
