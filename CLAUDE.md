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
  are EOL) + **currently supported** ones (alpine3.23/3.22, trixie/bookworm). Historic suites come first in
  `versions.sh`, so `7.2-fpm` / `7.2-fpm-alpine` keep the Hub meaning (buster / alpine3.12).
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

## State (2026-10-22)

- 7.2: imported (Sury 7.2.34-66), `-p1`; alpine3.23/fpm built and tested; `make test` clean vs known failures.
  38 php-src advisories untriaged (Sury does not cover everything: e.g. 8.2.34 batch of 2026-09-24).
- 7.2 on all 8 suites (alpine3.11/3.12/3.22/3.23, stretch/buster/bookworm/trixie) built + smoke-tested in chroot
  (php -v 7.2.34-p1, NTS/ZTS, php-fpm -t, apache2ctl -t, docker-php-ext-install intl gd bcmath with freetype).
  Stretch needs dirmngr + libargon2 from buster (pinned), as upstream did.
- Todo: 7.0, 7.1, 7.3, 7.4, 8.0, 8.1; the 20 untested 7.2 suite/variant combos; triage 7.2 advisories; arm64;
  cosign; trademark check of the name before publishing; first commit/push
  (nothing committed yet — ask before committing/pushing).
- Context: started for civ-corse (/app/civ-corse/civ-corse, PHP 7.2 FPM on Alpine, CVE-2026-109618/109619).
