#!/usr/bin/env bash
set -eux

PUBLIC_DIR=public

rm -rf ${PUBLIC_DIR}/*
hugo -d ${PUBLIC_DIR}

pushd ${PUBLIC_DIR}
git commit -am 'publish'
popd
git submodule update public