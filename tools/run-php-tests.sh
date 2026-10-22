#!/bin/sh
# Builds the patched sources of a branch and runs PHP's own test suite on the areas the backports touch.
# Runs inside an Alpine container (CI): docker run --rm -v "$PWD:/src:ro" alpine:3.23 /src/tools/run-php-tests.sh 7.2
# Fails on any test failure not listed in patches/<version>/known-test-failures.
set -eu

version="$1"
src=/src
command -v jq > /dev/null || apk add --no-cache jq > /dev/null
url="$(jq -r --arg v "$version" '.[$v].url' "$src/versions.json")"
sha256="$(jq -r --arg v "$version" '.[$v].sha256' "$src/versions.json")"
cflags="$(sed -n 's/^ENV PHP_CFLAGS="\(.*\)"$/\1/p' "$src/$version/alpine3.23/cli/Dockerfile")"

apk add --no-cache autoconf bison coreutils curl file g++ gcc libc-dev make patch pkgconf re2c \
	curl-dev libedit-dev libsodium-dev libxml2-dev openssl-dev readline-dev sqlite-dev argon2-dev oniguruma-dev > /dev/null

mkdir -p /build && cd /build
curl -fsSL -o php.tar.xz "$url"
echo "$sha256 *php.tar.xz" | sha256sum -c -
tar -xJf php.tar.xz --strip-components=1
grep -vE '^\s*(#|$)' "$src/patches/$version/series" | while read -r p; do
	patch -p1 --no-backup-if-mismatch < "$src/patches/$version/$p" > /dev/null
done
grep -qs 'PKG_PROG_PKG_CONFIG' acinclude.m4 build/*.m4 || cat /usr/share/aclocal/pkg.m4 >> acinclude.m4
./buildconf --force > /dev/null 2>&1

export CFLAGS="$cflags" CPPFLAGS="$cflags" CXXFLAGS="-O2 -std=c++17"
./configure --enable-mbstring --enable-mysqlnd --with-curl --with-openssl --with-zlib --with-sodium \
	--with-pdo-sqlite=/usr --with-sqlite3=/usr --enable-fpm --disable-cgi --without-pear > /dev/null
make -j "$(nproc)" > /dev/null

adduser -D -S tester 2> /dev/null || true
chown -R tester /build
su tester -s /bin/sh -c 'cd /build && NO_INTERACTION=1 REPORT_EXIT_STATUS=0 make test \
	TESTS="Zend tests main ext/standard/tests/general_functions ext/session ext/xml ext/dom ext/simplexml ext/libxml ext/xmlreader ext/xmlwriter ext/openssl ext/sodium" \
	> /build/tests.log 2>&1' || true

sed -n '/^FAILED TEST SUMMARY/,/^=====*$/p' tests.log | grep -oE '\[[^]]+\.phpt\]$' | tr -d '[]' | sort -u > failed
grep -vE '^\s*(#|$)' "$src/patches/$version/known-test-failures" 2> /dev/null | sort -u > known || : > known
grep -E '^(Tests (failed|passed|skipped))' tests.log || true
new="$(comm -23 failed known)"
fixed="$(comm -13 failed known)"
[ -z "$fixed" ] || printf 'no longer failing (remove from known-test-failures):\n%s\n' "$fixed"
if [ -n "$new" ]; then
	printf 'NEW test failures:\n%s\n' "$new"
	for t in $new; do echo "--- ${t%.phpt}.diff"; head -30 "${t%.phpt}.diff" 2> /dev/null || true; done
	exit 1
fi
echo "ok: no new test failure"
