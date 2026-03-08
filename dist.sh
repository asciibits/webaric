#!/bin/bash

mkdir -p dist
npx tsc
# Alternate:
#   npx -p wabt wat2wasm src/webaric.wat -o lib/webaric.wasm
npx wasm-as -all ./src/webaric.wat -o ./dist/webaric.wasm
npx esbuild ./src/webaric.ts --bundle --splitting --minify --format=esm --outdir=dist
npx html-minifier-terser --collapse-whitespace --remove-comments --minify-js true ./src/index.html -o ./dist/index.html
cp src/index.html dist/
