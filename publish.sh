#!/usr/bin/env bash
set -eux

PUBLIC_DIR=public

hugo -d ${PUBLIC_DIR} --ignoreCache

pushd ${PUBLIC_DIR}
git add .
git commit -am 'publish' || true
popd
git add ${PUBLIC_DIR}
git commit -am "${1:-auto publish}" || true
git push --recurse-submodules=on-demand