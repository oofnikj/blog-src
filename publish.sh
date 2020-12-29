#!/usr/bin/env bash
set -eux

PUBLIC_DIR=public

rm -rf ${PUBLIC_DIR}/*
hugo -d ${PUBLIC_DIR}

pushd ${PUBLIC_DIR}
git add .
git commit -am 'publish' || true
popd
env | grep GIT
git add ${PUBLIC_DIR}