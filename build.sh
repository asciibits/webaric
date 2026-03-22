#!/bin/bash

echo "Building..." >&2
tsc
# compile source to wasm
cargo build --profile wasm --features js_debug --target wasm32-unknown-unknown
START=$(date +%s.%N)
echo -e "    \033[1;32mStripping wasm\033[m..." >&2
WAT_FILE="$(mktemp)"
WASM_FILE="$(mktemp)"
trap 'rm -f "$WAT_FILE" "$WASM_FILE"' EXIT ERR HUP INT TERM
npx wasm2wat ./target/wasm32-unknown-unknown/wasm/wasmcomp.wasm -o $WAT_FILE
# get the list of exported finctions
exports=( $(sed -r -n -e '/wasm_bindgen/{n;/^pub fn /s/^.* ([^ ]*)\(.*/"\1"/p}' src/*.rs) )
if [ "${#exports[*]}" == "0" ]; then
  echo "No exports found - problem with the build script?" >&2
  exit 1
fi
# turn the list of exports into a sed expression like: "add"|"sub"
exports="$(IFS="|"; echo "${exports[*]}")"
# strip all non-exported symbols from the web assembly
sed -i -r -e "/$exports/! s/\(export\s*\"[^\"]*\"(\s*\([^\)]*\))*\s*\)//g" -e '/__wbg_/ {s/"__wbindgen_placeholder__"/"js"/;s/"__wbg_(.*)_[a-f0-9]*"/"\1"/}' $WAT_FILE
# strip remaining dead code
npx wat2wasm --enable-all $WAT_FILE -o $WASM_FILE
npx wasm-opt -all -O3 $WASM_FILE -o ./lib/wasmcomp.wasm

# Not necessary, but useful to have the text wat file around
npx wasm2wat -f ./lib/wasmcomp.wasm -o ./generated/wasmcomp.wat

END=$(date +%s.%N)
echo -e "    \033[1;32mFinished\033[m in $(echo "($END - $START)" | bc | sed -r 's/\.(..).*/.\1/')s. WASM exports: ${exports//|/,}" >&2


# for i in ./src/*.wat; do
#   file="$(basename $i .wat)"
#   if [ "./lib/$file.wasm" -ot "./src/$file.wat" ]; then
#     TMP_FILE="$(mktemp)"
#     trap 'rm -f "$TMP_FILE"' EXIT ERR HUP INT TERM
#     npx wasm-as -all "./src/$file.wat" -o "$TMP_FILE"
#     # npx wasm-opt -all -O3 "$TMP_FILE" -o "./lib/$file.wasm"
#     mv "$TMP_FILE" ./lib/$file.wasm
#     # npx -p wabt wat2wasm --enable-multi-memory src/$file.wat -o lib/$file.wasm
#   fi
# done
echo "Done." >&2
