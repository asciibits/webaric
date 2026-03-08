import {readFile} from 'node:fs/promises';
import {loadWebAric, WebAric} from './webaric.js';

let webaric: WebAric;

beforeAll(async () => {
  webaric = await loadWebAric(readFile('webaric.wasm'));
});

describe('Arithmetic Coder', () => {
  it('zooms low', () => {
    const result = webaric.zoomLow(10, 30, 40);
    console.log(`Results: ${result}`);
  });
});
