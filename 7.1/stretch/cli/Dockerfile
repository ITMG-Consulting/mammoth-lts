#
# NOTE: THIS DOCKERFILE IS GENERATED VIA "apply-templates.sh"
#
# PLEASE DO NOT EDIT IT DIRECTLY.
#

FROM debian:stretch-slim

# stretch is EOL: its packages (security updates included) only remain on archive.debian.org
# (which resets pipelined connections mid-download, "read (104: Connection reset by peer)": no pipelining, and retry)
RUN set -eux; \
	sed -ri \
		-e 's!https?://(deb|security)\.debian\.org/!http://archive.debian.org/!' \
		-e '/-updates/d' \
		/etc/apt/sources.list; \
	{ \
		echo 'Acquire::Check-Valid-Until "false";'; \
		echo 'Acquire::http::Pipeline-Depth "0";'; \
		echo 'Acquire::Retries "5";'; \
	} > /etc/apt/apt.conf.d/99archive

# prevent Debian's PHP packages from being installed
# https://github.com/docker-library/php/pull/542
RUN set -eux; \
	{ \
		echo 'Package: php*'; \
		echo 'Pin: release *'; \
		echo 'Pin-Priority: -1'; \
	} > /etc/apt/preferences.d/no-debian-php

# dependencies required for running "phpize"
# (see persistent deps below)
ENV PHPIZE_DEPS \
		autoconf \
		dpkg-dev \
		file \
		g++ \
		gcc \
		libc-dev \
		make \
		pkg-config \
		re2c

# persistent / runtime deps
RUN set -eux; \
	apt-get update; \
	apt-get install -y --no-install-recommends \
		$PHPIZE_DEPS \
		ca-certificates \
		curl \
		xz-utils \
	; \
	rm -rf /var/lib/apt/lists/*

ENV PHP_INI_DIR /usr/local/etc/php
RUN set -eux; \
	mkdir -p "$PHP_INI_DIR/conf.d"; \
# allow running as an arbitrary user (https://github.com/docker-library/php/issues/743)
	[ ! -d /var/www/html ]; \
	mkdir -p /var/www/html; \
	chown www-data:www-data /var/www/html; \
	chmod 1777 /var/www/html

# Apply stack smash protection to functions using local buffers and alloca()
# Make PHP's main executable position-independent (improves ASLR security mechanism, and has no performance impact on x86_64)
# Enable optimization (-O2)
# Enable linker optimization (this sorts the hash buckets to improve cache locality, and is non-default)
# https://github.com/docker-library/php/issues/272
# -D_LARGEFILE_SOURCE and -D_FILE_OFFSET_BITS=64 (https://www.php.net/manual/en/intro.filesystem.php)
# PHP 7 predates gcc 14+ (C23 by default in gcc 15, incompatible-pointer-types as an error) and ICU 75+ (C++17 headers)
# same flags as deb.sury.org for these versions
ENV PHP_CFLAGS="-fstack-protector-strong -fpic -fpie -O2 -D_LARGEFILE_SOURCE -D_FILE_OFFSET_BITS=64 -std=gnu99 -Wno-error=incompatible-pointer-types -fno-strict-aliasing"
ENV CXXFLAGS="-fstack-protector-strong -fpic -fpie -O2 -std=c++17"
ENV PHP_CPPFLAGS="$PHP_CFLAGS"
ENV PHP_LDFLAGS="-Wl,-O1 -pie"

ENV GPG_KEYS A917B1ECDA84AEC2B568FED6F50ABC807BD5DCD0 528995BFEDFBA7191D46839EF9BA0ADA31CBD89E 1729F83938DA44E27BA0F4D3DBDB397470D12172

ENV PHP_VERSION 7.1.33-p1
ENV PHP_URL="https://www.php.net/distributions/php-7.1.33.tar.xz" PHP_ASC_URL="https://www.php.net/distributions/php-7.1.33.tar.xz.asc"
ENV PHP_SHA256="bd7c0a9bd5433289ee01fd440af3715309faf583f75832b64fe169c100d52968"

RUN set -eux; \
	\
	savedAptMark="$(apt-mark showmanual)"; \
	apt-get update; \
	apt-get install -y --no-install-recommends gnupg dirmngr; \
	rm -rf /var/lib/apt/lists/*; \
	\
	mkdir -p /usr/src; \
	cd /usr/src; \
	\
	curl -fsSL -o php.tar.xz "$PHP_URL"; \
	\
	if [ -n "$PHP_SHA256" ]; then \
		echo "$PHP_SHA256 *php.tar.xz" | sha256sum -c -; \
	fi; \
	\
	curl -fsSL -o php.tar.xz.asc "$PHP_ASC_URL"; \
	export GNUPGHOME="$(mktemp -d)"; \
	for key in $GPG_KEYS; do \
# the keyservers fail intermittently ("keyserver receive failed"): retry, and fall back to other servers
		for attempt in 1 2 3; do \
			for server in keyserver.ubuntu.com keys.openpgp.org pgp.mit.edu; do \
				gpg --batch --keyserver "$server" --recv-keys "$key" && break 2 || :; \
			done; \
			sleep 5; \
		done; \
		gpg --batch --list-keys "$key" > /dev/null; \
	done; \
	gpg --batch --verify php.tar.xz.asc php.tar.xz; \
	gpgconf --kill all; \
	rm -rf "$GNUPGHOME"; \
	\
	apt-mark auto '.*' > /dev/null; \
	apt-mark manual $savedAptMark > /dev/null; \
	apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false

COPY docker-php-source /usr/local/bin/
COPY patches/ /usr/src/php-patches/

RUN set -eux; \
	\
	savedAptMark="$(apt-mark showmanual)"; \
	apt-get update; \
	apt-get install -y --no-install-recommends \
		libcurl4-openssl-dev \
		libedit-dev \
		libsqlite3-dev \
		libssl-dev \
		libxml2-dev \
		patch \
		zlib1g-dev \
	; \
	\
	export \
		CFLAGS="$PHP_CFLAGS" \
		CPPFLAGS="$PHP_CPPFLAGS" \
		LDFLAGS="$PHP_LDFLAGS" \
# https://github.com/php/php-src/blob/d6299206dd828382753453befd1b915491b741c6/configure.ac#L1496-L1511
		PHP_BUILD_PROVIDER='mammoth-lts (unofficial build)' \
		PHP_UNAME='Linux - Docker' \
	; \
	docker-php-source extract; \
	cd /usr/src/php; \
# backported security fixes and build fixes, see patches/7.1/SOURCE
	while read -r p; do \
		case "$p" in ''|'#'*) continue ;; esac; \
		patch -p1 --no-backup-if-mismatch < "/usr/src/php-patches/$p"; \
	done < /usr/src/php-patches/series; \
	rm -rf /usr/src/php-patches; \
# PHP < 7.4 does not ship pkg.m4; buildconf and phpize both build aclocal.m4 from acinclude.m4
	if ! grep -qs 'PKG_PROG_PKG_CONFIG' acinclude.m4 build/*.m4; then \
		cat /usr/share/aclocal/pkg.m4 >> acinclude.m4; \
	fi; \
	./buildconf --force; \
# docker-php-ext-* re-extract /usr/src/php.tar.xz: keep the patched tree there
	tar -cJf /usr/src/php.tar.xz -C /usr/src --exclude=php/.docker-extracted php; \
	gnuArch="$(dpkg-architecture --query DEB_BUILD_GNU_TYPE)"; \
	debMultiarch="$(dpkg-architecture --query DEB_BUILD_MULTIARCH)"; \
# https://bugs.php.net/bug.php?id=74125
	if [ ! -d /usr/include/curl ]; then \
		ln -sT "/usr/include/$debMultiarch/curl" /usr/local/include/curl; \
	fi; \
	./configure \
		--build="$gnuArch" \
		--with-config-file-path="$PHP_INI_DIR" \
		--with-config-file-scan-dir="$PHP_INI_DIR/conf.d" \
		\
# make sure invalid --configure-flags are fatal errors instead of just warnings
		--enable-option-checking=fatal \
		\
# https://github.com/docker-library/php/issues/439
		--with-mhash \
		\
# https://github.com/docker-library/php/issues/822
		--with-pic \
		\
# --enable-ftp is included here for compatibility with existing versions. ftp_ssl_connect() needed ftp to be compiled statically before PHP 7.0 (see https://github.com/docker-library/php/issues/236).
		--enable-ftp \
# --enable-mbstring is included here because otherwise there's no way to get pecl to use it properly (see https://github.com/docker-library/php/issues/195)
		--enable-mbstring \
# --enable-mysqlnd is included here because it's harder to compile after the fact than extensions are (since it's a plugin for several extensions, not an extension in itself)
		--enable-mysqlnd \
# always build against system sqlite3 (https://github.com/php/php-src/commit/6083a387a81dbbd66d6316a3a12a63f06d5f7109)
		--with-pdo-sqlite=/usr \
		--with-sqlite3=/usr \
		\
		--with-curl \
		--with-iconv \
		--with-openssl \
		--with-libedit \
		--with-zlib \
		\
# https://github.com/docker-library/php/pull/1259
		--enable-phpdbg \
		\
# bundled pcre does not support JIT on riscv64 until 10.41 (php 8.3+)
# https://github.com/PCRE2Project/pcre2/commits/pcre2-10.41/src/sljit/sljitNativeRISCV_64.c
# https://github.com/php/php-src/tree/php-8.3.0/ext/pcre/pcre2lib
		$(test "$gnuArch" = 'riscv64-linux-gnu' && echo '--without-pcre-jit') \
		--with-libdir="lib/$debMultiarch" \
		\
# https://github.com/docker-library/php/pull/939#issuecomment-730501748
		--enable-embed \
	; \
# "php -v" / PHP_VERSION report the patch level of this build, e.g. 7.2.34-p3 (> 7.2.34 for version_compare() and composer)
	sed -ri \
		-e 's/^(#define PHP_EXTRA_VERSION ).*/\1"-p1"/' \
		-e 's/^(#define PHP_VERSION "[0-9.]+).*/\1-p1"/' \
		main/php_version.h; \
	grep -q '^#define PHP_VERSION "7.1.33-p1"$' main/php_version.h; \
	make -j "$(nproc)"; \
	find -type f -name '*.a' -delete; \
	make install; \
	find \
		/usr/local \
		-type f \
		-perm '/0111' \
		-exec sh -euxc ' \
			strip --strip-all "$@" || : \
		' -- '{}' + \
	; \
	make clean; \
	\
# https://github.com/docker-library/php/issues/692 (copy default example "php.ini" files somewhere easily discoverable)
	cp -v php.ini-* "$PHP_INI_DIR/"; \
	\
	cd /; \
	docker-php-source delete; \
	\
# reset apt-mark's "manual" list so that "purge --auto-remove" will remove all build dependencies
	apt-mark auto '.*' > /dev/null; \
	[ -z "$savedAptMark" ] || apt-mark manual $savedAptMark; \
	find /usr/local -type f -executable -exec ldd '{}' ';' \
		| awk '/=>/ { so = $(NF-1); if (index(so, "/usr/local/") == 1) { next }; gsub("^/(usr/)?", "", so); printf "*%s\n", so }' \
		| sort -u \
		| xargs -rt dpkg-query --search \
# https://manpages.debian.org/trixie/dpkg/dpkg-query.1.en.html#S (we ignore diversions and it'll be really unusual for more than one package to provide any given .so file)
		| awk 'sub(":$", "", $1) { print $1 }' \
		| sort -u \
		| xargs -r apt-mark manual \
	; \
	apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
	rm -rf /var/lib/apt/lists/*; \
	\
# update pecl channel definitions https://github.com/docker-library/php/issues/443
	pecl update-channels; \
	rm -rf /tmp/pear ~/.pearrc; \
	\
# smoke test
	php --version

COPY docker-php-ext-* docker-php-entrypoint /usr/local/bin/

# https://github.com/docker-library/php/pull/1010 (gd < 7.4 looks for freetype-config, gone from Debian)
RUN { echo '#!/bin/sh'; echo 'exec pkg-config "$@" freetype2'; } > /usr/local/bin/freetype-config && chmod +x /usr/local/bin/freetype-config


ENTRYPOINT ["docker-php-entrypoint"]
CMD ["php", "-a"]
