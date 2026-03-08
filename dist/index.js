async function m(){let e=await fetch("webaric.wasm");return(await WebAssembly.instantiateStreaming(e)).instance.exports._zoom_low}var n=typeof window>"u"?void 0:window;n&&n.addEventListener("load",async()=>{n.zoomLow=await m();let[e,o,i,t,s,a]=n.zoomLow(10,40,30,0,0);console.log(`Got the data: newBits: ${e.toString(2)}, 
      numBits: ${o}, low/mid/high: ${i}/${s}/${t}, 
      newMidZooms: ${a}`)});export{m as getWebaric};
