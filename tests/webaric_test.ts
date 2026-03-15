import {readFile} from 'node:fs/promises';
import {loadWebAric} from '../src/webaric.js';
import {suite, test, before, beforeEach} from 'node:test';
import {strict as assert} from 'node:assert/strict';

let exports: Record<string, Function>;
let enableLogging = false;

function logNumbers(...values: number[]) {
  if (enableLogging) {
    console.log(
      'Log: ' + (values[0]?.toString(16).toUpperCase() ?? ''),
      values.slice(1).map((v, i) => (v >>> 0).toString(2).padStart(32, '0')),
    );
  }
}

function logBigInts(...values: bigint[]) {
  if (enableLogging) {
    console.log(
      'Log: ' + (values[0]?.toString(16).toUpperCase() ?? ''),
      values.slice(1).map((v, i) => (v >> 0n).toString(2).padStart(32, '0')),
    );
  }
}

before(async () => {
  exports = await loadWebAric(await readFile('./lib/webaric.wasm'), {
    log1: logNumbers,
    log2: logNumbers,
    log3: logNumbers,
    log4: logNumbers,
    log5: logNumbers,
    log6: logNumbers,
    log64_1: logBigInts,
    log64_2: logBigInts,
    log64_3: logBigInts,
    log64_4: logBigInts,
    log64_5: logBigInts,
    log64_6: logBigInts,
  });
});

beforeEach(() => {
  enableLogging = false;
});

suite('Arithmetic Coder', () => {
  suite('Min/Max', () => {
    test('handles simple min', () => {
      assert.equal(exports._min32(0, 0), 0);
      assert.equal(exports._min32(0, 1), 0);
      assert.equal(exports._min32(1, 0), 0);
    });
    test('min is unsigned', () => {
      assert.equal(exports._min32(-1, 0), 0);
    });
    test('min handles boundary conditions', () => {
      assert.equal(exports._min32(0xffffffff, 0), 0);
      assert.equal(exports._min32(0xffffffff, 0xffffffff), 0xffffffff | 0);
      assert.equal(exports._min32(0xfffffffe, 0xffffffff), 0xfffffffe | 0);
    });
    test('handles simple max', () => {
      assert.equal(exports._max32(0, 0), 0);
      assert.equal(exports._max32(0, 1), 1);
      assert.equal(exports._max32(1, 0), 1);
    });
    test('max is unsigned', () => {
      assert.equal(exports._max32(-1, 0), -1);
    });
    test('max handles boundary conditions', () => {
      assert.equal(exports._max32(0xffffffff, 0), 0xffffffff | 0);
      assert.equal(exports._max32(0xffffffff, 0xffffffff), 0xffffffff | 0);
      assert.equal(exports._max32(0xfffffffe, 0xffffffff), 0xffffffff | 0);
    });
  });
  suite('Mid', () => {
    suite('mid_ratio', () => {
      test('handles simple ratio', () => {
        assert.equal(exports._mid_ratio(100, 199, 1, 2), 150n);
        assert.equal(exports._mid_ratio(100, 199, 20, 100), 120n);
        assert.equal(
          exports._mid_ratio(0x11111111, 0xdddddddd, 0xdeadbeef, 0xffffffff),
          0xc335a9d1n,
        );
      });
      test(
        'fails with a zero denominator',
        {expectFailure: /divide by zero/} as any,
        () => {
          exports._mid_ratio(100, 199, 7, 0);
        },
      );
    });
    suite('mid_i32', () => {
      test('handles simple values', () => {
        assert.equal(exports._mid_i32(100, 199, 0x80000000n), 150n);
        assert.equal(exports._mid_i32(100, 199, 0x33333398n), 120n);
        assert.equal(
          exports._mid_i32(0x11111111, 0xdddddddd, 0xdeadbeefn),
          0xc335a9d0n,
        );
      });
    });
  });
  suite('Encoding Zooms', () => {
    test('no zoom low', () => {
      const [outerZooms, midZooms] = exports._zoom(0x3fffffff, 0x80000000);
      assert.equal(outerZooms, 0);
      assert.equal(midZooms, 0);
    });
    test('single zoom low', () => {
      const [outerZooms, midZooms] = exports._zoom(0x3fffffff, 0x7fffffff);
      assert.equal(outerZooms, 1);
      assert.equal(midZooms, 0);
    });
    test('single zoom mid (lower)', () => {
      const [outerZooms, midZooms] = exports._zoom(0x40000000, 0x80000000);
      assert.equal(outerZooms, 0);
      assert.equal(midZooms, 1);
    });
    test('no zoom high', () => {
      const [outerZooms, midZooms] = exports._zoom(0x7fffffff, 0xc0000000);
      assert.equal(outerZooms, 0);
      assert.equal(midZooms, 0);
    });
    test('single zoom high', () => {
      const [outerZooms, midZooms] = exports._zoom(0x80000000, 0xc0000000);
      assert.equal(outerZooms, 1);
      assert.equal(midZooms, 0);
    });
    test('single zoom mid (higher)', () => {
      const [outerZooms, midZooms] = exports._zoom(0x7fffffff, 0xbfffffff);
      assert.equal(outerZooms, 0);
      assert.equal(midZooms, 1);
    });
    test('max zooms low', () => {
      const [outerZooms, midZooms] = exports._zoom(0, 1);
      assert.equal(outerZooms, 31);
      assert.equal(midZooms, 0);
    });
    test('max zooms high', () => {
      const [outerZooms, midZooms] = exports._zoom(0xfffffffe, 0xffffffff);
      assert.equal(outerZooms, 31);
      assert.equal(midZooms, 0);
    });
    test('max zooms mid', () => {
      const [outerZooms, midZooms] = exports._zoom(0x7fffffff, 0x80000000);
      assert.equal(outerZooms, 0);
      assert.equal(midZooms, 31);
    });
    test('many zooms arbitrary', () => {
      const [outerZooms, midZooms] = exports._zoom(
        0b10110101001010110101001010011110,
        0b10110101001010110101001010100000,
      );
      assert.equal(outerZooms, 26);
      assert.equal(midZooms, 4);
    });
  });
});
