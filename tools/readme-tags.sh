#!/usr/bin/env bash
# Rewrites the "Available tags" tables of README.md (between the tags:start / tags:end markers) from versions.json
# and tools/tags.sh: one table per branch, suites as rows, variants as columns; in each cell the tag of the current
# patch level, then the branch-level tags (which follow every rebuild).
set -Eeuo pipefail

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")/.."
command -v jq > /dev/null || { echo >&2 'error: jq is required'; exit 1; }
variants=( cli fpm zts apache )

table="$(
	for version in $(jq -r 'to_entries[] | select(.value) | .key' versions.json); do
		full="$(jq -r --arg v "$version" '.[$v].version + .[$v].extraVersion' versions.json)"
		echo
		echo "### $version (\`$full\`)"
		echo
		echo "| |$(printf ' `%s` |' "${variants[@]}")"
		echo "| --- |$(printf ' --- |%.0s' "${variants[@]}")"
		for suite in $(jq -r --arg v "$version" '[.[$v].variants[] | split("/")[0]] | reduce .[] as $s ([]; if index([$s]) then . else . + [$s] end) | .[]' versions.json); do
			row="| $suite |"
			for variant in "${variants[@]}"; do
				if jq -e --arg v "$version" --arg d "$suite/$variant" '.[$v].variants | index($d)' versions.json > /dev/null; then
					# the current patch level first (older -pN tags stay pullable but are not listed), then the branch tags
					cell="$(tools/tags.sh "$version/$suite/$variant" | grep -E "^($full-$variant-$suite|$version(-|\$))" | sed 's/.*/`&`/' | paste -sd' ' - | sed 's/` `/`<br>`/g')"
				else
					cell=''
				fi
				row+=" $cell |"
			done
			echo "$row"
		done
	done
)"

python3 -I - README.md "$table" <<-'EOF'
	import sys
	path, table = sys.argv[1], sys.argv[2]
	text = open(path).read()
	start, end = "<!-- tags:start (tools/readme-tags.sh) -->", "<!-- tags:end -->"
	head, rest = text.split(start, 1)
	_, tail = rest.split(end, 1)
	open(path, "w").write(head + start + "\n" + table.strip("\n") + "\n\n" + end + tail)
EOF
