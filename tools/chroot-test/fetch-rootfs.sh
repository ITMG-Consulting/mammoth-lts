#!/usr/bin/env bash
# Extracts the linux/amd64 rootfs of a Docker Hub image without Docker: fetch-rootfs.sh debian:buster-slim <dir>
set -Eeuo pipefail
image="$1" dest="$2"
repo="${image%%:*}" tag="${image#*:}"
[[ "$repo" == */* ]] || repo="library/$repo"

token="$(curl -fsSL "https://auth.docker.io/token?service=registry.docker.io&scope=repository:$repo:pull" | jq -r .token)"
reg() { curl -fsSL -H "Authorization: Bearer $token" "$@"; }
accept='application/vnd.oci.image.index.v1+json,application/vnd.docker.distribution.manifest.list.v2+json,application/vnd.oci.image.manifest.v1+json,application/vnd.docker.distribution.manifest.v2+json'

manifest="$(reg -H "Accept: $accept" "https://registry-1.docker.io/v2/$repo/manifests/$tag")"
if jq -e '.manifests' <<< "$manifest" > /dev/null; then
	digest="$(jq -r '.manifests[] | select(.platform.os == "linux" and .platform.architecture == "amd64" and (.platform.variant // "") == "") | .digest' <<< "$manifest" | head -1)"
	manifest="$(reg -H "Accept: $accept" "https://registry-1.docker.io/v2/$repo/manifests/$digest")"
fi

mkdir -p "$dest"
for layer in $(jq -r '.layers[].digest' <<< "$manifest"); do
	reg -o "$dest.layer" "https://registry-1.docker.io/v2/$repo/blobs/$layer"
	echo "$layer" | sed 's/^sha256://' | { read -r sum; echo "$sum *$dest.layer" | sha256sum -c --quiet -; }
	tar -xzf "$dest.layer" -C "$dest" --exclude='dev/*'
	rm "$dest.layer"
done
cp /etc/resolv.conf "$dest/etc/resolv.conf"
for d in "null c 1 3" "zero c 1 5" "urandom c 1 9" "random c 1 8" "tty c 5 0" "full c 1 7"; do
	set -- $d
	[ -e "$dest/dev/$1" ] || mknod -m 666 "$dest/dev/$1" "$2" "$3" "$4"
done
mkdir -p "$dest/dev/shm" "$dest/proc" "$dest/tmp"
chmod 1777 "$dest/tmp" "$dest/dev/shm"
echo "$image -> $dest"
