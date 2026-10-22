#!/usr/bin/env bash
# Prints the image tags of one build directory, e.g. tools/tags.sh 7.2/alpine3.23/fpm:
#   7.2.34-p1-fpm-alpine3.23  7.2.34-fpm-alpine3.23  7.2-fpm-alpine3.23  (+ "-alpine" for the newest Alpine,
#   and the suite-less tags for the first Debian suite: 7.2.34-p1-fpm 7.2.34-fpm 7.2-fpm, plain "7.2" for cli)
# Same naming as the official image, plus the "-pN" patch level. No dated tags: -pN changes whenever PHP changes.
set -Eeuo pipefail

dir="${1%/}"
version="${dir%%/*}" rest="${dir#*/}"
suite="${rest%%/*}" variant="${rest#*/}"

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")/.."
full="$(jq -r --arg v "$version" '.[$v].version' versions.json)"
extra="$(jq -r --arg v "$version" '.[$v].extraVersion' versions.json)"
firstAlpine="$(jq -r --arg v "$version" '[.[$v].variants[] | split("/")[0] | select(startswith("alpine"))][0]' versions.json)"
firstDebian="$(jq -r --arg v "$version" '[.[$v].variants[] | split("/")[0] | select(startswith("alpine") | not)][0]' versions.json)"

suites=( "$suite" )
[ "$suite" != "$firstAlpine" ] || suites+=( alpine )
[ "$suite" != "$firstDebian" ] || suites+=( '' )

for v in "$full$extra" "$full" "$version"; do
	for s in "${suites[@]}"; do
		echo "$v-$variant${s:+-$s}"
		[ "$variant" != 'cli' ] || echo "$v${s:+-$s}"
	done
done
