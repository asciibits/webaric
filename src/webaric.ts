type ZoomFunc = (
  low: number,
  high: number,
  mid: number,
  mid_zooms: number,
  need_leading_md: number,
) => number[];

export class WebAric {
  private _zoom_low: ZoomFunc;
  constructor(instance: WebAssembly.Instance) {
    this._zoom_low = instance.exports._zoom_low as ZoomFunc;
  }

  zoomLow(
    low: number,
    mid: number,
    high: number,
    mid_zooms = 0,
    need_leading_mid = true,
  ) {
    return this._zoom_low(
      low >> 0,
      mid >> 0,
      high >> 0,
      mid_zooms | 0,
      need_leading_mid ? 1 : 0,
    );
  }
}

export async function loadWebAricFromRemote(remotePath: string) {
  const response = await fetch(remotePath);
  const wasm = await WebAssembly.instantiateStreaming(response);
  return new WebAric(wasm.instance);
}

export async function loadWebAric(data: Promise<Buffer>) {
  const wasm = await WebAssembly.instantiate(data);
  return new WebAric(wasm);
}
