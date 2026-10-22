#!/usr/bin/env bash
set -Eeuo pipefail

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

# EOL branches only: supported branches (8.2+) are covered by the official image (https://hub.docker.com/_/php)
# a branch is published once patches/<version>/series exists (tools/import-sury-patches.sh, then reviewed)
versions=( "$@" )
if [ ${#versions[@]} -eq 0 ]; then
	versions=( 7.0 7.1 7.2 7.3 7.4 8.0 8.1 )
fi

json='{}'
[ "$#" -eq 0 ] || json="$(< versions.json)"

now="$(date --utc '+%s')"

# base images: the last series docker-library/php published for the branch (same tags as Docker Hub, drop-in
# replacement; these OS releases are EOL themselves) + the currently supported ones
declare -A historicSuites=(
	[7.0]='stretch jessie alpine3.7'
	[7.1]='buster stretch alpine3.10 alpine3.9'
	[7.2]='buster stretch alpine3.12 alpine3.11'
	[7.3]='bullseye buster alpine3.15 alpine3.14'
	[7.4]='bullseye buster alpine3.16 alpine3.15'
	[8.0]='bullseye buster alpine3.16'
	[8.1]='trixie bookworm alpine3.22 alpine3.21'
)
currentSuites='trixie bookworm alpine3.23 alpine3.22'

for version in "${versions[@]}"; do
	export version

	if [ ! -f "patches/$version/series" ]; then
		echo >&2 "warning: skipping '$version' (no patches/$version/series yet)"
		json="$(jq <<<"$json" -c '.[env.version] = null')"
		continue
	fi

	possi=( $(
		curl -fsSL "https://www.php.net/releases/index.php?json&max=100&version=${version%%.*}&cachebuster=$now" \
			| jq --raw-output '
				(keys[] | select(startswith(env.version + "."))) as $version
				| [ $version, (
					.[$version].source[]
					| select(.filename | endswith(".xz"))
					|
						"https://www.php.net/distributions/" + .filename,
						"https://www.php.net/distributions/" + .filename + ".asc",
						.sha256 // ""
				) ]
				| @sh
			' \
			| sort -rV \
			| head -1 \
			| xargs -n1
	) )
	[ "${#possi[@]}" -eq 4 ] || { echo >&2 "error: no release found for $version"; exit 1; }
	fullVersion="${possi[0]}" url="${possi[1]}" ascUrl="${possi[2]}" sha256="${possi[3]}"
	[ -n "$sha256" ] || { echo >&2 "error: no sha256 for $fullVersion"; exit 1; }

	# bumped by tools/import-sury-patches.sh whenever the applied patches change (or by hand for a local fix)
	extraVersion="-p$(< "patches/$version/patchlevel")"

	echo "$version: $fullVersion$extraVersion ($(awk -F': ' '$1 == "version" {print $2}' "patches/$version/SOURCE"))"

	# historic suites first: like on Docker Hub they get the suite-less / "-alpine" tags (tools/tags.sh)
	suites="$(printf '%s\n' ${historicSuites[$version]} $currentSuites | awk '!seen[$0]++' | paste -sd' ' -)"

	export fullVersion url ascUrl sha256 extraVersion suites
	json="$(
		jq <<<"$json" -c '
			.[env.version] = {
				version: env.fullVersion,
				url: env.url,
				ascUrl: env.ascUrl,
				sha256: env.sha256,
				extraVersion: env.extraVersion,
				patches: true,
				variants: [
					# order here controls the order of the library/ file
					(env.suites | split(" ")[]) as $suite
					| (
						"cli",
						"apache",
						"fpm",
						"zts",
						empty
					) as $variant
					| if $suite | startswith("alpine") and $variant == "apache" then empty else
						"\($suite)/\($variant)"
					end
				],
			}
		'
	)"
done

jq <<<"$json" 'to_entries | sort_by(.key) | from_entries' > versions.json
