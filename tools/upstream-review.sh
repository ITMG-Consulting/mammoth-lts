#!/usr/bin/env bash
# Tracks docker-library/php (the official image) after our fork point.
#
# - lists upstream commits touching the template or the shared scripts that are not triaged yet in upstream.reviewed
#   (one line per commit: "<sha> ported|not-applicable|pending: reason"), with --diff to show what they change
# - --sync-scripts copies the version-independent scripts (docker-php-*, apache2-foreground) from upstream as-is
# Exit code 1 when something is untriaged or a shared script differs, so CI can flag it.
set -Eeuo pipefail

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")/.."

showDiff= sync=
for arg; do
	case "$arg" in
		--diff) showDiff=1 ;;
		--sync-scripts) sync=1 ;;
		*) echo "usage: $0 [--diff] [--sync-scripts]" >&2; exit 1 ;;
	esac
done

scripts=( docker-php-entrypoint docker-php-ext-configure docker-php-ext-enable docker-php-ext-install docker-php-source apache2-foreground )
watched=( Dockerfile-linux.template apply-templates.sh versions.sh generate-stackbrew-library.sh "${scripts[@]}" )

git remote get-url upstream > /dev/null 2>&1 || git remote add upstream https://github.com/docker-library/php.git
git fetch --quiet upstream master
base="$(awk '$1 == "#" && $2 == "base" {print $3}' upstream.reviewed)"

status=0
echo "upstream: $(git log -1 --format='%h %ad %s' --date=short upstream/master)"
echo "fork point: $(git log -1 --format='%h %ad %s' --date=short "$base")"

untriaged=0
while read -r sha subject; do
	[ -n "$sha" ] || continue
	if grep -qE "^${sha:0:8}[0-9a-f]* " upstream.reviewed; then
		continue
	fi
	untriaged=$(( untriaged + 1 ))
	echo "untriaged  $sha $subject"
	if [ -n "$showDiff" ]; then
		git show --format= "$sha" -- "${watched[@]}" | sed 's/^/    /'
	fi
done < <(git log --no-merges --format='%h %s' "$base..upstream/master" -- "${watched[@]}")
[ "$untriaged" -eq 0 ] || status=1

for f in "${scripts[@]}"; do
	if ! git diff --quiet upstream/master -- "$f"; then
		if [ -n "$sync" ]; then
			git show "upstream/master:$f" > "$f"
			echo "synced     $f (run ./apply-templates.sh)"
		else
			echo "differs    $f (tools/upstream-review.sh --sync-scripts)"
			status=1
		fi
	fi
done

pending="$(grep -cE '^[0-9a-f]+ pending:' upstream.reviewed || true)"
echo "$untriaged untriaged, $pending pending in upstream.reviewed"
exit "$status"
