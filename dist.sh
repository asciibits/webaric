#!/bin/bash

npx wasm-as -all ./src/webaric.wat -o ./dist/webaric.wasm
npx esbuild ./src/index.ts --bundle --splitting --minify --format=esm --outdir=dist
npx html-minifier-terser --collapse-whitespace --remove-comments --minify-js true ./src/index.html -o ./dist/index.html
cp src/index.html dist/
