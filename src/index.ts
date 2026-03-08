type func = (
  low: number,
  high: number,
  mid: number,
  mid_zooms: number,
  need_leading_md: number,
) => number[];

declare global {
  interface Window {
    zoomLow: func;
  }
}

export async function getWebaric(): Promise<func> {
  const response = await fetch('webaric.wasm');
  const wasm = await WebAssembly.instantiateStreaming(response);
  return wasm.instance.exports._zoom_low as func;
}

const win: Window | undefined =
  typeof window === 'undefined' ? undefined : window;

if (win) {
  win.addEventListener('load', async () => {
    win.zoomLow = await getWebaric();
    const [newBits, numBits, low, high, mid, newMidZooms] = win.zoomLow(
      10,
      40,
      30,
      0,
      0,
    );

    console.log(
      `Got the data: newBits: ${newBits.toString(2)}, 
      numBits: ${numBits}, low/mid/high: ${low}/${mid}/${high}, 
      newMidZooms: ${newMidZooms}`,
    );
  });
}
