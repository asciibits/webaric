export async function loadWebAricFromRemote(remotePath: string) {
  const response = await fetch(remotePath);
  const wasm = await WebAssembly.instantiateStreaming(response);
  return wasm.instance.exports;
}

export async function loadWebAric(
  buffer: Buffer,
  loggers: Record<string, (...values: number[]) => void> = {},
) {
  const module = (await WebAssembly.instantiate(buffer, {
    test: {
      ...loggers,
    },
  })) as any;
  return module.instance.exports;
}
