#!/bin/bash

mkdir -p dist
npx tsc
# Alternate:
#   npx -p wabt wat2wasm src/wasmcomp.wat -o lib/wasmcomp.wasm
sed -r '/DEBUG_START/{:b;N;s/DEBUG_END//;T b;d}' ./src/wasmcomp.wat > ./dist/stripped.wat
npx wasm-as -all ./dist/stripped.wat -o ./dist/wasmcomp_std.wasm
npx wasm-opt -all -O3 ./dist/wasmcomp_std.wasm -o ./dist/wasmcomp.wasm
rm ./dist/stripped.wat ./dist/wasmcomp_std.wasm
npx esbuild ./src/wasmcomp.ts --bundle --splitting --minify --format=esm --outdir=dist
npx html-minifier-terser --collapse-whitespace --remove-comments --minify-js true ./src/index.html -o ./dist/index.html
cp src/index.html dist/
