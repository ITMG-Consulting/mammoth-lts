#!/usr/bin/env bash
# Bumps the "-pN" patch level of a branch after a local change (patches/<version>/local.series, template fix
# that changes the PHP build...). Sury imports bump it on their own (tools/import-sury-patches.sh).
# A rebuild for base image updates only (Alpine / Debian packages) keeps the same patch level.
set -Eeuo pipefail

[ "$#" -eq 2 ] || { echo "usage: $0 <php-version> <reason>   e.g. $0 7.2 'GH-14834 libxml2 2.13 fix'" >&2; exit 1; }
version="$1" reason="$2"

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")/.."
dir="patches/$version"
[ -f "$dir/patchlevel" ] || { echo >&2 "error: $dir/patchlevel missing, import the branch first"; exit 1; }

patchlevel=$(( $(< "$dir/patchlevel") + 1 ))
upstream="$(awk -F': ' '$1 == "version" {print $2}' "$dir/SOURCE")"
upstream="${upstream#*:}"
{
	echo "## ${upstream%%-*}-p$patchlevel ($(date --utc +%F))"
	echo
	echo "- $reason"
	echo
	cat "$dir/CHANGELOG.md"
} > "$dir/CHANGELOG.md.new"
mv "$dir/CHANGELOG.md.new" "$dir/CHANGELOG.md"
echo "$patchlevel" > "$dir/patchlevel"
echo "$version: ${upstream%%-*}-p$patchlevel"
