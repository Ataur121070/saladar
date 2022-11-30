#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

if [ -n "${DEBUG:-}" ]; then
    set -x
fi

function main() {
    pushd /kong
        make dev
        cat /kong/spec/fixtures/hosts >> /etc/hosts
    popd

    exec "$@"
}

main