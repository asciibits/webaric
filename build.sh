#!/bin/bash

echo "Building..." >&2
tsc
for i in ./src/*.wat; do
  file="$(basename $i .wat)"
  [ "./lib/$file.wasm" -ot "./src/$file.wat" ] && npx -p wabt wat2wasm --enable-multi-memory src/$file.wat -o lib/$file.wasm
done
echo "Done." >&2
