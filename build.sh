#!/bin/bash

echo "Building..." >&2
tsc
for i in ./src/*.wat; do
  file="$(basename $i .wat)"
  if [ "./lib/$file.wasm" -ot "./src/$file.wat" ]; then
    TMP_FILE="$(mktemp)"
    trap 'rm -f "$TMP_FILE"' EXIT ERR HUP INT TERM
    npx wasm-as -all "./src/$file.wat" -o "$TMP_FILE"
    # npx wasm-opt -all -O3 "$TMP_FILE" -o "./lib/$file.wasm"
    mv "$TMP_FILE" ./lib/$file.wasm
    # npx -p wabt wat2wasm --enable-multi-memory src/$file.wat -o lib/$file.wasm
  fi
done
echo "Done." >&2
