#!/usr/bin/env bash
# Adds an official php-src commit to the local patches of an EOL branch (patches/<version>/local.series).
#
# Use it for fixes deb.sury.org has not backported (see tools/advisory-coverage.py), or for the backport branches
# the PHP security team publishes itself for EOL versions (e.g. PHP-7.4-CVE-2026-109618-109619).
# The commit must belong to php/php-src and carry a verified signature; NEWS hunks are dropped.
# If the patch does not apply as-is on the branch, adapt it by hand (keep the "Origin:" header) and check it in.
set -Eeuo pipefail

[ "$#" -ge 3 ] || { echo "usage: $0 <php-version> <commit-sha> <short-name> [advisory-id]   e.g. $0 7.2 67259e45 GH-14834" >&2; exit 1; }
version="$1" sha="$2" name="$3" advisory="${4:-}"

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")/.."
dir="patches/$version"
[ -f "$dir/series" ] || { echo >&2 "error: import the Sury series of $version first"; exit 1; }

meta="$(curl -fsSL -H 'Accept: application/vnd.github+json' "https://api.github.com/repos/php/php-src/commits/$sha")"
fullSha="$(jq -r '.sha' <<< "$meta")"
verified="$(jq -r '.commit.verification.verified' <<< "$meta")"
[ "$verified" = 'true' ] || { echo >&2 "error: $fullSha has no verified signature on github.com/php/php-src"; exit 1; }

last="$(grep -hoE '^9[0-9]{3}' "$dir/local.series" 2> /dev/null | sort -n | tail -1)"
num=$(( ${last:-9000} + 1 ))
file="$num-$(tr -c 'A-Za-z0-9.\n' '-' <<< "$name" | tr -s '-')"
file="${file%-}.patch"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
curl -fsSL -o "$work/commit.patch" "https://github.com/php/php-src/commit/$fullSha.patch?full_index=1"
{
	echo "Origin: https://github.com/php/php-src/commit/$fullSha"
	[ -z "$advisory" ] || echo "Advisory: $advisory"
	echo "Imported-by: tools/import-php-src-commit.sh (NEWS hunks dropped)"
	echo
	python3 -I - "$work/commit.patch" <<-'EOF'
		import re, sys
		text = open(sys.argv[1]).read()
		head, sep, rest = text.partition("\ndiff --git ")
		parts = [("diff --git " + p) for p in rest.split("\ndiff --git ")] if sep else []
		print(head)
		print("\n".join(p for p in parts if not p.startswith("diff --git a/NEWS ")), end="")
	EOF
} > "$dir/$file"

echo "$file" >> "$dir/local.series"
grep -qxF "$file" "$dir/series" || echo "$file" >> "$dir/series"
tools/bump-patchlevel.sh "$version" "php-src $name (${fullSha:0:10})${advisory:+, $advisory}"
echo "added $dir/$file: now build the branch and run the tests, the patch may need adapting"
