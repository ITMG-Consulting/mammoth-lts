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
| 7.0, 7.1, 7.3, 7.4, 8.0, 8.1 | planned | | |

Each branch is built on the base images docker-library last published it on (same tags as Docker Hub, so
`FROM php:7.2-fpm-alpine3.12` → `FROM ghcr.io/itmg-consulting/mammoth-lts:7.2-fpm-alpine3.12` is a drop-in change; **those OS releases are
EOL themselves**, Debian ones install from archive.debian.org) and on the currently supported ones, which we recommend.
Suite-less and `-alpine` aliases keep their Docker Hub meaning (`7.2-fpm` = buster, `7.2-fpm-alpine` = alpine3.12).

A branch is generated once `patches/<version>/series` exists (`versions.sh`). Supported branches (8.2+) are not
built here: use the official image.

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

PHP 7 also gets the compiler flags deb.sury.org uses for these versions on current toolchains (gcc 14/15, ICU 75+).

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
- Without Docker: `tools/chroot-test/test-target.sh . 7.2/buster/fpm` builds a generated dir in a chroot of its base
  image (rootfs pulled from the Docker Hub registry) and runs the same smoke tests.

## Maintenance

| When | Do |
| --- | --- |
| deb.sury.org publishes a new revision | `tools/import-sury-patches.sh <v>`, review the diff, `./versions.sh && ./apply-templates.sh`, `tools/security-report.py` |
| php-src publishes an advisory | `tools/advisory-coverage.py`, then backport (`tools/import-php-src-commit.sh`) or triage |
| a local build fix | add it to `patches/<v>/local.series`, `tools/bump-patchlevel.sh <v> "<reason>"` |
| docker-library/php changes | `tools/upstream-review.sh --diff`, port or record it in `upstream.reviewed` |

## Credits and licenses

- Dockerfiles and scripts: [docker-library/php](https://github.com/docker-library/php) (MIT), see [LICENSE](LICENSE).
- Patch series: [deb.sury.org](https://deb.sury.org/) by Ondřej Surý, `debian/*` under the Expat license; patches
  derived from php-src are under the PHP License 3.01. Paid long-term support for these packages:
  [PHP LTS by Freexian](https://www.freexian.com/lts/php/).
- PHP: the PHP Group, [PHP License 3.01](https://www.php.net/license/3_01.txt).
