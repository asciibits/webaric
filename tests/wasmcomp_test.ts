import {readFile} from 'node:fs/promises';
import {suite, test, before, beforeEach} from 'node:test';
import {strict as assert} from 'node:assert/strict';

let utils: Record<string, Function>;
let wasmcomp: Record<string, Function>;
let enableLogging = false;

function logi32arr(...values: number[]) {
  if (enableLogging) {
    console.log(
      'Log: ' + (values[0]?.toString(16).toUpperCase() ?? ''),
      values.slice(1).map(log32),
    );
  }
}

function logi64arr(...values: bigint[]) {
  if (enableLogging) {
    console.log(
      'Log: ' + (values[0]?.toString(16).toUpperCase() ?? ''),
      values.slice(1).map(log64),
    );
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

before(async () => {
  const test = {
    log1: logi32arr,
    log2: logi32arr,
    log3: logi32arr,
    log4: logi32arr,
    log5: logi32arr,
    log6: logi32arr,
    log64_1: logi64arr,
    log64_2: logi64arr,
    log64_3: logi64arr,
    log64_4: logi64arr,
    log64_5: logi64arr,
    log64_6: logi64arr,
    random32: () => Math.floor(Math.random() * 0xffffffff),
    nanonow: process.hrtime.bigint,
  };
  utils = await loadWasm(await readFile('./lib/utils.wasm'), {test});
  wasmcomp = await loadWasm(await readFile('./lib/wasmcomp.wasm'), {
    test,
    utils,
  });
});

beforeEach(() => {
  enableLogging = false;
});

// test(() => {
//   let nanos = 0n;
//   for (let i = 0; i < 100; i++) {
//     enableLogging = true;
//     nanos += utils._benchmark_reverse32(1024*1024);
//   }
//   console.log("Benchmark time: " + Number(nanos) / 100000000);
// })

suite('Utils', () => {
  suite('Min/Max', () => {
    test('handles simple min', () => {
      assert.equal(utils._min32(0, 0), 0);
      assert.equal(utils._min32(0, 1), 0);
      assert.equal(utils._min32(1, 0), 0);
    });
    test('min is unsigned', () => {
      assert.equal(utils._min32(-1, 0), 0);
    });
    test('min handles boundary conditions', () => {
      assert.equal(utils._min32(0xffffffff, 0), 0);
      assert.equal(utils._min32(0xffffffff, 0xffffffff), 0xffffffff | 0);
      assert.equal(utils._min32(0xfffffffe, 0xffffffff), 0xfffffffe | 0);
    });
    test('handles simple max', () => {
      assert.equal(utils._max32(0, 0), 0);
      assert.equal(utils._max32(0, 1), 1);
      assert.equal(utils._max32(1, 0), 1);
    });
    test('max is unsigned', () => {
      assert.equal(utils._max32(-1, 0), -1);
    });
    test('max handles boundary conditions', () => {
      assert.equal(utils._max32(0xffffffff, 0), 0xffffffff | 0);
      assert.equal(utils._max32(0xffffffff, 0xffffffff), 0xffffffff | 0);
      assert.equal(utils._max32(0xfffffffe, 0xffffffff), 0xffffffff | 0);
    });
  });
  suite('Mid', () => {
    suite('mid_ratio', () => {
      test('handles simple ratio', () => {
        assert.equal(utils._mid_ratio(100, 199, 1, 2), 150n);
        assert.equal(utils._mid_ratio(100, 199, 20, 100), 120n);
        assert.equal(
          utils._mid_ratio(0x11111111, 0xdddddddd, 0xdeadbeef, 0xffffffff),
          0xc335a9d1n,
        );
      });
      test(
        'fails with a zero denominator',
        {expectFailure: /divide by zero/} as any,
        () => {
          utils._mid_ratio(100, 199, 7, 0);
        },
      );
    });
    suite('mid_i32', () => {
      test('handles simple values', () => {
        assert.equal(utils._mid_i32(100, 199, 0x80000000n), 150n);
        assert.equal(utils._mid_i32(100, 199, 0x33333398n), 120n);
        assert.equal(
          utils._mid_i32(0x11111111, 0xdddddddd, 0xdeadbeefn),
          0xc335a9d0n,
        );
      });
    });
  });
  suite('Reverse', () => {
    test('reverses 32 bits', () => {
      // symmetric: 0, 6, 9, f
      // pairs: 1/8, 2/4, 3/c, 5/a, 7/e, b/d
      assert.equal(utils._reverse32(0x12345678), 0x1e6a2c48 | 0);
      assert.equal(utils._reverse32(0xdf21bb87), 0xe1dd84fb | 0);
      assert.equal(utils._reverse32(0xbf4e2f23), 0xc4f472fd | 0);
      assert.equal(utils._reverse32(0x91b1217a), 0x5e848d89 | 0);
      assert.equal(utils._reverse32(0x67efc8e8), 0x1713f7e6 | 0);
      assert.equal(utils._reverse32(0x93232aa3), 0xc554c4c9 | 0);
      assert.equal(utils._reverse32(0x1343a142), 0x4285c2c8 | 0);
    });
    test('reverses 64 bits', () => {
      // handle signed by &ing
      function as64(v: bigint): bigint {
        return v & 0xffffffffffffffffn;
      }
      // symmetric: 0, 6, 9, f
      // pairs: 1/8, 2/4, 3/c, 5/a, 7/e, b/d
      assert.equal(
        as64(utils._reverse64(0x0123456789abcdefn)),
        0xf7b3d591e6a2c480n,
      );
      assert.equal(
        as64(utils._reverse64(0xbf4e2f2391b1217an)),
        0x5e848d89c4f472fdn,
      );
      assert.equal(
        as64(utils._reverse64(0x67efc8e893232aa3n)),
        0xc554c4c91713f7e6n,
      );
    });
  });
});
suite('Arithmetic Coder', () => {
  suite('Encoding Zooms', () => {
    test('no zoom low', () => {
      const [outerZooms, midZooms] = wasmcomp._zoom(0x3fffffff, 0x80000000);
      assert.equal(outerZooms, 0);
      assert.equal(midZooms, 0);
    });
    test('single zoom low', () => {
      const [outerZooms, midZooms] = wasmcomp._zoom(0x3fffffff, 0x7fffffff);
      assert.equal(outerZooms, 1);
      assert.equal(midZooms, 0);
    });
    test('single zoom mid (lower)', () => {
      const [outerZooms, midZooms] = wasmcomp._zoom(0x40000000, 0x80000000);
      assert.equal(outerZooms, 0);
      assert.equal(midZooms, 1);
    });
    test('no zoom high', () => {
      const [outerZooms, midZooms] = wasmcomp._zoom(0x7fffffff, 0xc0000000);
      assert.equal(outerZooms, 0);
      assert.equal(midZooms, 0);
    });
    test('single zoom high', () => {
      const [outerZooms, midZooms] = wasmcomp._zoom(0x80000000, 0xc0000000);
      assert.equal(outerZooms, 1);
      assert.equal(midZooms, 0);
    });
    test('single zoom mid (higher)', () => {
      const [outerZooms, midZooms] = wasmcomp._zoom(0x7fffffff, 0xbfffffff);
      assert.equal(outerZooms, 0);
      assert.equal(midZooms, 1);
    });
    test('max zooms low', () => {
      const [outerZooms, midZooms] = wasmcomp._zoom(0, 1);
      assert.equal(outerZooms, 31);
      assert.equal(midZooms, 0);
    });
    test('max zooms high', () => {
      const [outerZooms, midZooms] = wasmcomp._zoom(0xfffffffe, 0xffffffff);
      assert.equal(outerZooms, 31);
      assert.equal(midZooms, 0);
    });
    test('max zooms mid', () => {
      const [outerZooms, midZooms] = wasmcomp._zoom(0x7fffffff, 0x80000000);
      assert.equal(outerZooms, 0);
      assert.equal(midZooms, 31);
    });
    test('identical zoom', () => {
      const [outerZooms, midZooms] = wasmcomp._zoom(0xdeadbeef, 0xdeadbeef);
      assert.equal(outerZooms, 32);
      assert.equal(midZooms, 0);
    });
    test('many zooms arbitrary', () => {
      const [outerZooms, midZooms] = wasmcomp._zoom(
        0b10110101001010110101001010011110,
        0b10110101001010110101001010100000,
      );
      assert.equal(outerZooms, 26);
      assert.equal(midZooms, 4);
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
