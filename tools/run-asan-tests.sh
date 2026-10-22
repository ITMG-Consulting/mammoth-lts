#!/bin/sh
# Builds the patched sources of a branch with AddressSanitizer and runs the .phpt tests the patch series adds or
# changes (the regression tests of the backported security fixes), so that a backport which only looks right
# (same output, but out-of-bounds or use-after-free left behind) fails CI.
# Runs inside a Debian container (CI): docker run --rm -v "$PWD:/src:ro" debian:bookworm /src/tools/run-asan-tests.sh 7.2
# The host needs vm.mmap_rnd_bits <= 28 (ASan cannot map its shadow memory with the default of recent kernels).
# Fails on any AddressSanitizer report; plain test failures (environment, see known-test-failures) are only listed.
# ASAN=0 builds without the sanitizer (to check the script itself where ASan cannot run).
set -eu

version="$1"
src=/src
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends autoconf bison ca-certificates curl file g++ gcc jq libc-dev make patch \
	pkg-config re2c xz-utils libcurl4-openssl-dev libedit-dev libicu-dev libonig-dev libpq-dev libreadline-dev \
	libsodium-dev libsqlite3-dev libssl-dev libxml2-dev libzip-dev zlib1g-dev > /dev/null

url="$(jq -r --arg v "$version" '.[$v].url' "$src/versions.json")"
sha256="$(jq -r --arg v "$version" '.[$v].sha256' "$src/versions.json")"
cflags="$(sed -n 's/^ENV PHP_CFLAGS="\(.*\)"$/\1/p' "$src/$version/bookworm/cli/Dockerfile")"
[ "${ASAN:-1}" = 0 ] || cflags="$cflags -fsanitize=address -fno-omit-frame-pointer -g"

mkdir -p /build && cd /build
curl -fsSL -o php.tar.xz "$url"
echo "$sha256 *php.tar.xz" | sha256sum -c -
tar -xJf php.tar.xz --strip-components=1
grep -vE '^\s*(#|$)' "$src/patches/$version/series" | while read -r p; do
	patch -p1 --no-backup-if-mismatch < "$src/patches/$version/$p" > /dev/null
done
grep -qs 'PKG_PROG_PKG_CONFIG' acinclude.m4 build/*.m4 || cat /usr/share/aclocal/pkg.m4 >> acinclude.m4
./buildconf --force > /dev/null 2>&1

# the tests added or changed by the patch series
grep -vE '^\s*(#|$)' "$src/patches/$version/series" | while read -r p; do
	sed -n 's#^+++ b/\(.*\.phpt\)$#\1#p' "$src/patches/$version/$p"
done | sort -u | while read -r t; do [ -f "$t" ] && echo "$t"; done > asan-tests
echo "$(wc -l < asan-tests) tests from the patch series"

export CFLAGS="$cflags" CPPFLAGS="$cflags" CXXFLAGS="-O2 -std=c++17" LDFLAGS="$(echo "$cflags" | grep -o -- '-fsanitize=address' || :)"
zip="$(case "$version" in 7.[0-3]) echo --enable-zip ;; *) echo --with-zip ;; esac)"
./configure --disable-cgi --without-pear --enable-mbstring --enable-mysqlnd --with-mysqli=mysqlnd \
	--with-pdo-mysql=mysqlnd --with-curl --with-openssl --with-zlib --with-sodium --with-pdo-sqlite=/usr --with-sqlite3=/usr \
	--with-pgsql --with-pdo-pgsql --enable-soap --enable-bcmath --enable-intl "$zip" --enable-exif --enable-ftp \
	--enable-pcntl --enable-sockets --with-libdir=lib/x86_64-linux-gnu > configure.log 2>&1 || { tail -20 configure.log; exit 1; }
make -j "$(nproc)" > make.log 2>&1 || { tail -30 make.log; exit 1; }

# run-tests.php must not use the Zend allocator, whose pooled memory hides heap errors from ASan: PHP 7.4+ knows
# --asan, older ones force USE_ZEND_ALLOC=1 unless running valgrind
if grep -q "'--asan'" run-tests.php; then
	asan=--asan
else
	asan=
	sed -i "s/\$env\['USE_ZEND_ALLOC'\] = '1';/\$env['USE_ZEND_ALLOC'] = '0';/" run-tests.php
	if grep -q "\$env\['USE_ZEND_ALLOC'\] = '1';" run-tests.php; then echo >&2 'error: run-tests.php still forces USE_ZEND_ALLOC=1'; exit 1; fi
fi

useradd -m tester 2> /dev/null || true
chown -R tester /build
mkdir -p /tmp/asan && chmod 1777 /tmp/asan
su tester -c "cd /build && NO_INTERACTION=1 REPORT_EXIT_STATUS=0 USE_ZEND_ALLOC=0 ZEND_DONT_UNLOAD_MODULES=1 \
	ASAN_OPTIONS=detect_leaks=0:log_path=/tmp/asan/report TEST_PHP_EXECUTABLE=/build/sapi/cli/php \
	sapi/cli/php run-tests.php -q $asan \$(cat asan-tests) > /build/tests.log 2>&1" || true

grep -E '^(Tests (failed|passed|skipped))' tests.log || true
sed -n '/^FAILED TEST SUMMARY/,/^=====*$/p' tests.log | grep -oE '\[[^]]+\.phpt\]$' | tr -d '[]' | sort -u > failed || true
[ ! -s failed ] || printf 'failing (not an ASan finding, compare with known-test-failures):\n%s\n' "$(cat failed)"
if ls /tmp/asan/report.* > /dev/null 2>&1; then
	echo "AddressSanitizer reports:"
	for f in /tmp/asan/report.*; do echo "--- $f"; head -40 "$f"; done
	exit 1
fi
echo "ok: no AddressSanitizer report"
