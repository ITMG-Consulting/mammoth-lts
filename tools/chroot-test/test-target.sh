#!/usr/bin/env bash
# Builds one generated dir (e.g. 7.2/buster/fpm) in a chroot of its FROM image, then runs the CI smoke tests.
# usage: [WORK=/tmp/mammoth-lts-chroot] test-target.sh <repo> <dir>   -> $WORK/tests/<dir with _>.log, "RESULT ok|FAIL <step>"
set -uo pipefail
S="${WORK:-/tmp/mammoth-lts-chroot}"
T="$(dirname "$(readlink -f "$BASH_SOURCE")")"
repo="$1" dir="$2"
name="${dir//\//_}"
root="$S/chroots/$name"
log="$S/tests/$name.log"
mkdir -p "$S/tests" "$S/chroots" "$S/rootfs"
exec > "$log" 2>&1

from="$(awk '$1 == "FROM" {print $2; exit}' "$repo/$dir/Dockerfile")"
cache="$S/rootfs/${from//[:\/]/_}"
[ -d "$cache" ] || "$T/fetch-rootfs.sh" "$from" "$cache" || { echo "RESULT FAIL fetch"; exit 1; }
rm -rf "$root" && cp -a "$cache" "$root"
mkdir -p "$root/ctx" && cp -a "$repo/$dir/." "$root/ctx/"
mkdir -p "$root/usr/local/bin" && cp "$T/tar-noproc-wrapper" "$root/usr/local/bin/tar"
# no /proc in this chroot: php-fpm -t only needs its error_log (/proc/self/fd/2) to be openable
mkdir -p "$root/proc/self/fd" && touch "$root/proc/self/fd/1" "$root/proc/self/fd/2"
python3 -I "$T/dockerfile2sh.py" "$repo/$dir/Dockerfile" /ctx/ > "$root/build.sh"

step() { echo "=== $1"; shift; chroot "$root" /usr/bin/env -i PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin HOME=/root /bin/sh -c "$*"; }
step build '. /build.sh' || { echo "RESULT FAIL build"; exit 1; }

version="${dir%%/*}"
expected="$(jq -r --arg v "$version" '.[$v].version + .[$v].extraVersion' "$repo/versions.json")"
env="$(grep -E '^export (PHP_INI_DIR|PHP_CFLAGS|PHP_CPPFLAGS|PHP_LDFLAGS|CXXFLAGS|PHPIZE_DEPS|PHP_VERSION)=' "$root/build.sh" | tr '\n' ';')"
step version "$env php -v | grep -F 'PHP $expected '" || { echo "RESULT FAIL version"; exit 1; }
step modules "$env php -m" || { echo "RESULT FAIL modules"; exit 1; }
case "$dir" in
	*/fpm) step fpm "$env php-fpm -t" || { echo "RESULT FAIL php-fpm-t"; exit 1; } ;;
	*/apache) step apache ". /etc/apache2/envvars && apache2ctl -t" || { echo "RESULT FAIL apache-t"; exit 1; } ;;
esac
case "$dir" in
	*/alpine*) deps='apk add --no-cache icu-dev freetype-dev libjpeg-turbo-dev libpng-dev' ;;
	*) deps='apt-get update && apt-get install -y --no-install-recommends libicu-dev libfreetype6-dev libjpeg-dev libpng-dev' ;;
esac
step extensions "$env set -eux; $deps; docker-php-ext-configure gd --with-freetype-dir=/usr --with-jpeg-dir=/usr 2>/dev/null || docker-php-ext-configure gd --with-freetype --with-jpeg; docker-php-ext-install -j\$(nproc) intl gd bcmath; php -m | grep -cE '^(intl|gd|bcmath)\$' | grep -qx 3; php -r 'echo Locale::getDefault(), \" \", gd_info()[\"FreeType Support\"] ? \"freetype\" : \"NO-freetype\", PHP_EOL;'" || { echo "RESULT FAIL extensions"; exit 1; }
echo "RESULT ok"
