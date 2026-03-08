import {readFileSync} from 'node:fs';
import { loadWebAric, WebAric } from '../src/webaric.js';
import { describe, it } from 'node:test';

let webaric: WebAric|null = null;

// beforeAll(async () => {
//   const buffer = readFileSync('./lib/webaric.wasm');
//   console.log('Buffer: ' + buffer);
//   await loadWebAric(buffer);
// });

describe('Arithmetic Coder', () => {
  it('zooms low', () => {
    // const result = webaric!.zoomLow(10, 30, 40);
    // console.log(`Results: ${result}`);
  });
});
