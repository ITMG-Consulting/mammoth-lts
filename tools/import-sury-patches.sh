#!/usr/bin/env bash
# Imports the security patch series of an EOL PHP version from deb.sury.org into patches/<version>/.
#
# Chain of trust: InRelease (signed with the pinned Sury key) -> Sources.xz (sha256 from InRelease)
# -> <pkg>_<ver>.debian.tar.xz (sha256 from Sources). Nothing is fetched outside that chain.
#
# Per-version selection lives in patches/<version>/sury.conf:
#   SURY_SUITE=trixie            # dist whose source package is imported
#   KEEP_FROM=0057               # every patch numbered >= KEEP_FROM is kept (new upstream fixes land at the end)
#   KEEP_EXTRA="0047 0048"       # Debian build patches below KEEP_FROM that we still need
#   EXCLUDE="0144"               # patches dropped on purpose (see README of the version)
# Local patches (not from Sury) are listed in patches/<version>/local.series and appended to the series.
set -Eeuo pipefail

SURY_KEY_FPR='15058500A0235D97F5D10063B188E2B695BD4743'
SURY_BASE='https://packages.sury.org/php'

usage() { echo "usage: $0 <php-version>   e.g. $0 7.2" >&2; exit 1; }
[ "$#" -eq 1 ] || usage
version="$1"

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")/.."
dir="patches/$version"
conf="$dir/sury.conf"
[ -f "$conf" ] || { echo >&2 "error: missing $conf"; exit 1; }
SURY_SUITE= KEEP_FROM= KEEP_EXTRA= EXCLUDE=
# shellcheck source=/dev/null
. "$conf"
: "${SURY_SUITE:?}" "${KEEP_FROM:?}"
pkg="php$version"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
export GNUPGHOME="$work/gnupg"
mkdir -m 700 "$GNUPGHOME"

gpg --batch --quiet --keyserver keyserver.ubuntu.com --recv-keys "$SURY_KEY_FPR"
gpg --batch --quiet --with-colons --fingerprint "$SURY_KEY_FPR" | grep -q "^fpr:::::::::$SURY_KEY_FPR:"

curl -fsSL -o "$work/InRelease" "$SURY_BASE/dists/$SURY_SUITE/InRelease"
gpg --batch --quiet --status-fd 3 --decrypt -o "$work/Release" "$work/InRelease" 3> "$work/status" 2> /dev/null
grep -q "^\[GNUPG:\] VALIDSIG $SURY_KEY_FPR " "$work/status" || { echo >&2 "error: bad InRelease signature"; exit 1; }

sourcesSha="$(awk '/^SHA256:/{s=1; next} /^[^ ]/{s=0} s && $3 == "main/source/Sources.xz" {print $1}' "$work/Release")"
[ -n "$sourcesSha" ]
curl -fsSL -o "$work/Sources.xz" "$SURY_BASE/dists/$SURY_SUITE/main/source/Sources.xz"
echo "$sourcesSha *$work/Sources.xz" | sha256sum -c --quiet -

xz -dc "$work/Sources.xz" | awk -v pkg="$pkg" '
	/^Package: / { cur = $2 }
	cur == pkg && /^Version: / { print "VERSION " $2 }
	cur == pkg && /^Directory: / { print "DIRECTORY " $2 }
	cur == pkg && /^Checksums-Sha256:/ { s = 1; next }
	cur == pkg && s && /^ / { if ($3 ~ /\.debian\.tar\.xz$/) print "DEBTAR " $1 " " $3; next }
	{ s = 0 }
' > "$work/meta"
debVersion="$(awk '$1 == "VERSION" {print $2}' "$work/meta")"
directory="$(awk '$1 == "DIRECTORY" {print $2}' "$work/meta")"
read -r _ debtarSha debtar < <(grep '^DEBTAR ' "$work/meta")
[ -n "$debVersion" ] && [ -n "$directory" ] && [ -n "$debtar" ] || { echo >&2 "error: $pkg not found in $SURY_SUITE Sources"; exit 1; }

curl -fsSL -o "$work/$debtar" "$SURY_BASE/$directory/$debtar"
echo "$debtarSha *$work/$debtar" | sha256sum -c --quiet -
mkdir "$work/deb"
tar -xJf "$work/$debtar" -C "$work/deb"
patchdir="$work/deb/debian/patches"

kept=()
while read -r p; do
	case "$p" in ''|'#'*) continue ;; esac
	num="${p%%-*}"
	if [[ " $EXCLUDE " == *" $num "* ]]; then
		continue
	elif [[ "$num" > "$KEEP_FROM" || "$num" == "$KEEP_FROM" || " $KEEP_EXTRA " == *" $num "* ]]; then
		kept+=( "$p" )
	fi
done < "$patchdir/series"

# never ship anything that phones home, even if a new patch slips past the exclusion list
for p in "${kept[@]}"; do
	if grep -qiE '^\+.*(telemetry|sury\.org)' "$patchdir/$p"; then
		echo >&2 "error: $p references telemetry or sury.org, review it and add it to EXCLUDE"
		exit 1
	fi
done

fingerprint() { (cd "$dir" && grep -vsE '^\s*(#|$)' series | xargs -r sha256sum || true) 2> /dev/null | sha256sum; }
old="$(mktemp)"
[ -f "$dir/series" ] && cp "$dir/series" "$old"
before="$(fingerprint)"
find "$dir" -maxdepth 1 -name '0*.patch' -delete
for p in "${kept[@]}"; do
	cp "$patchdir/$p" "$dir/"
done
{
	printf '%s\n' "${kept[@]}"
	[ ! -f "$dir/local.series" ] || grep -vE '^\s*(#|$)' "$dir/local.series"
} > "$dir/series"
cp "$work/deb/debian/changelog" "$dir/debian.changelog"

# "-pN" suffix of PHP_VERSION (php -v): version_compare() and composer both rank 7.2.34-p1 above 7.2.34
if [ ! -f "$dir/patchlevel" ] || [ "$before" != "$(fingerprint)" ]; then
	initial="$([ -f "$dir/patchlevel" ] || echo 1)"
	patchlevel=$(( $(cat "$dir/patchlevel" 2> /dev/null || echo 0) + 1 ))
	echo "$patchlevel" > "$dir/patchlevel"
	added="$( (diff "$old" "$dir/series" || true) | sed -n 's/^> //p')"
	{
		upstream="${debVersion#*:}"
		echo "## ${upstream%%-*}-p$patchlevel ($(date --utc +%F))"
		echo
		echo "Sury \`$debVersion\`."
		echo
		if [ -n "$initial" ]; then
			echo "- initial import: $(grep -cvE '^\s*(#|$)' "$dir/series") patches, see SECURITY.md"
		elif [ -n "$added" ]; then
			while read -r p; do
				ids="$(grep -ohE 'CVE-[0-9]{4}-[0-9]{4,}|GHSA(-[0-9a-z]{4}){3}' "$dir/$p" | sort -u | paste -sd' ' -)"
				echo "- \`$p\`${ids:+ ($ids)}"
			done <<< "$added"
		else
			echo "- patch contents updated"
		fi
		echo
		[ -f "$dir/CHANGELOG.md" ] && cat "$dir/CHANGELOG.md"
	} > "$work/CHANGELOG.md"
	mv "$work/CHANGELOG.md" "$dir/CHANGELOG.md"
fi

cat > "$dir/SOURCE" <<-EOF
	package: $pkg
	version: $debVersion
	suite: $SURY_SUITE
	debian-tarball: $SURY_BASE/$directory/$debtar
	debian-tarball-sha256: $debtarSha
	release-date: $(awk -F': ' '$1 == "Date" {print $2}' "$work/Release")
	license: debian/* Expat (Ondřej Surý), patches derived from php-src PHP-3.01
EOF

echo "$pkg $debVersion: ${#kept[@]} patches kept"
diff -u --label previous --label current "$old" "$dir/series" || true
rm -f "$old"
