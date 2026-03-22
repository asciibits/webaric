import {readFile} from 'node:fs/promises';
import {suite, test, before, beforeEach} from 'node:test';
import {strict as assert} from 'node:assert/strict';

let wasmcomp: Record<string, Function>;
let enableLogging = false;

function abs(val: number): number;
function abs(val: bigint): bigint;
function abs(val: number | bigint): number | bigint {
  if (typeof val === 'number') {
    return val >>> 0;
  } else {
    return val < 0n ? -val : val;
  }
}

function log32(val: number) {
  function bytebits(val: number) {
    return (val & 0xff).toString(2).padStart(8, '0');
  }
  return (
    bytebits(val >> 24) +
    ':' +
    bytebits(val >> 16) +
    ' ' +
    bytebits(val >> 8) +
    ':' +
    bytebits(val)
  );
}

function log64(val: bigint) {
  function bytebits(val: bigint) {
    return (val & 0xffn).toString(2).padStart(8, '0');
  }
  return (
    bytebits(val >> 56n) +
    ':' +
    bytebits(val >> 48n) +
    ' ' +
    bytebits(val >> 40n) +
    ':' +
    bytebits(val >> 32n) +
    ' ' +
    bytebits(val >> 24n) +
    ':' +
    bytebits(val >> 16n) +
    ' ' +
    bytebits(val >> 8n) +
    ':' +
    bytebits(val)
  );
}

function log64s(...val: bigint[]) {
  if (!enableLogging) return;
  console.log(
    `${val[0].toString(16).padStart(2, '0')}:\n${val
      .slice(1)
      .map(n => '    ' + log64(n))
      .join('\n')}`,
  );
}

function log32s(...val: number[]) {
  if (!enableLogging) return;
  console.log(
    `${val[0].toString(16).padStart(2, '0')}:\n${val
      .slice(1)
      .map(n => '    ' + log32(n))
      .join('\n')}`,
  );
}

function logValue(val: any): string {
  switch (typeof val) {
    case 'number':
      return log32(val);
    case 'bigint':
      return log64(val);
    default:
      return String(val);
  }
}

let lastData: any[];

let callback = function (name: string, params: string[], ...args: any[]) {
  lastData = args;
  if (!enableLogging) return;
  console.log(`call: ${name}:`);
  for (let i = 0; i < args.length; i++) {
    console.log(`  ${params[i].padEnd(15)}: ${logValue(args[i])}`);
  }
};

let lastEncoded: {result: bigint; resultCount: number} | null = null;
let lastError: {errorCode: number; p1: number; p2: number; p3: number} | null =
  null;

let bitEncoded = function (result: bigint, resultCount: number) {
  lastEncoded = {result, resultCount};
};

let errorHandler = function (
  errorCode: number,
  p1: number,
  p2: number,
  p3: number,
) {
  lastError = {errorCode, p1, p2, p3};
};

before(async () => {
  wasmcomp = await loadWasm(await readFile('./lib/wasmcomp.wasm'), {
    js: {
      // bit encoder callback
      bit_encoded: bitEncoded,
      // error handler
      error_handler: errorHandler,
      // logging functions for help
      log32_1: log32s,
      log32_2: log32s,
      log32_3: log32s,
      log32_4: log32s,
      log32_5: log32s,
      log32_6: log32s,
      log64_1: log64s,
      log64_2: log64s,
      log64_3: log64s,
      log64_4: log64s,
      log64_5: log64s,
      log64_6: log64s,
    },
  });
});

beforeEach(() => {
  enableLogging = false;
  lastEncoded = null;
  lastError = null;
});

// test(() => {
//   let nanos = 0n;
//   for (let i = 0; i < 100; i++) {
//     enableLogging = true;
//     nanos += utils._benchmark_reverse32(1024*1024);
//   }
//   console.log("Benchmark time: " + Number(nanos) / 100000000);
// })

suite('Arithmetic Coder', () => {
  suite('Zooms', () => {
    test('no zoom low', () => {
      let zoomData = abs(wasmcomp.zoom(0x3fffffff, 0x80000000) as bigint);
      zoomData = zoomData < 0 ? -zoomData : zoomData;
      assert.equal(Number(zoomData >> 32n), 0);
      assert.equal(Number(zoomData & 0xffffffffn), 0);
    });
    test('single zoom low', () => {
      let zoomData = abs(wasmcomp.zoom(0x3fffffff, 0x7fffffff) as bigint);
      zoomData = zoomData < 0 ? -zoomData : zoomData;
      assert.equal(Number(zoomData >> 32n), 1);
      assert.equal(Number(zoomData & 0xffffffffn), 1);
    });
    test('single zoom mid (lower)', () => {
      let zoomData = abs(wasmcomp.zoom(0x40000000, 0x80000000) as bigint);
      zoomData = zoomData < 0 ? -zoomData : zoomData;
      assert.equal(Number(zoomData >> 32n), 1);
      assert.equal(Number(zoomData & 0xffffffffn), 0);
    });
    test('no zoom high', () => {
      let zoomData = abs(wasmcomp.zoom(0x7fffffff, 0xc0000000) as bigint);
      zoomData = zoomData < 0 ? -zoomData : zoomData;
      assert.equal(Number(zoomData >> 32n), 0);
      assert.equal(Number(zoomData & 0xffffffffn), 0);
    });
    test('single zoom high', () => {
      let zoomData = abs(wasmcomp.zoom(0x80000000, 0xc0000000) as bigint);
      zoomData = zoomData < 0 ? -zoomData : zoomData;
      assert.equal(Number(zoomData >> 32n), 1);
      assert.equal(Number(zoomData & 0xffffffffn), 1);
    });
    test('single zoom mid (higher)', () => {
      let zoomData = abs(wasmcomp.zoom(0x7fffffff, 0xbfffffff) as bigint);
      zoomData = zoomData < 0 ? -zoomData : zoomData;
      assert.equal(Number(zoomData >> 32n), 1);
      assert.equal(Number(zoomData & 0xffffffffn), 0);
    });
    test('max zooms low', () => {
      let zoomData = abs(wasmcomp.zoom(0, 1) as bigint);
      zoomData = zoomData < 0 ? -zoomData : zoomData;
      assert.equal(Number(zoomData >> 32n), 31);
      assert.equal(Number(zoomData & 0xffffffffn), 31);
    });
    test('max zooms high', () => {
      let zoomData = abs(wasmcomp.zoom(0xfffffffe, 0xffffffff) as bigint);
      zoomData = zoomData < 0 ? -zoomData : zoomData;
      assert.equal(Number(zoomData >> 32n), 31);
      assert.equal(Number(zoomData & 0xffffffffn), 31);
    });
    test('max zooms mid', () => {
      let zoomData = abs(wasmcomp.zoom(0x7fffffff, 0x80000000) as bigint);
      zoomData = zoomData < 0 ? -zoomData : zoomData;
      assert.equal(Number(zoomData >> 32n), 31);
      assert.equal(Number(zoomData & 0xffffffffn), 0);
    });
    test('identical zoom', () => {
      let zoomData = abs(wasmcomp.zoom(0xdeadbeef, 0xdeadbeef) as bigint);
      zoomData = zoomData < 0 ? -zoomData : zoomData;
      assert.equal(Number(zoomData >> 32n), 32);
      assert.equal(Number(zoomData & 0xffffffffn), 32);
    });
    test('many zooms arbitrary', () => {
      let zoomData = abs(
        wasmcomp.zoom(
          0b10110101001010110101001010011110,
          0b10110101001010110101001010100000,
        ) as bigint,
      );
      zoomData = zoomData < 0 ? -zoomData : zoomData;
      assert.equal(Number(zoomData >> 32n), 30);
      assert.equal(Number(zoomData & 0xffffffffn), 26);
    });
  });
  suite('encode_bit', () => {
    test('encode_bit encodes bit', () => {
      wasmcomp.encode_bit(0, 0xffffffff, 1, 0x80000000);
      const {result, resultCount} = lastEncoded!;
      assert.equal(result, 0n);
      assert.equal(resultCount, 0);
    });
    test('encode_bit encodes bit', () => {
      wasmcomp.encode_bit(0, 0xffffffff, 1, 0x7fffffff);
      const {result, resultCount} = lastEncoded!;
      assert.equal(result, 0n);
      assert.equal(resultCount, 0);
    });
  });
});

async function loadWasm(
  buffer: Buffer,
  importObject: Record<string, any> = {},
) {
  const module = (await WebAssembly.instantiate(buffer, importObject)) as any;
  return module.instance.exports;
}
