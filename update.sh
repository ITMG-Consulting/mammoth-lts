#!/usr/bin/env bash
set -Eeuo pipefail

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

./versions.sh "$@"
./apply-templates.sh "$@"
tools/readme-tags.sh
