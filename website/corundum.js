const module = fetch("http://localhost:8000/zig-out/wasm/corundum.wasm")

const instance = WebAssembly.instantiateStreaming(module).then(instance => {
    const { memory, alloc, free, solve } = instance.instance.exports;

    function toWASM(memory, alloc, string) {
        const encoded = new TextEncoder().encode(string);
        const length = encoded.length;

        const ptr = alloc(length);

        const wasmBuffer = new Uint8Array(memory.buffer, ptr, length);
        wasmBuffer.set(encoded);

        return { ptr, length };
    }

    function fromWASM(memory, ptr, len) {
        const buffer = new Uint8Array(memory.buffer, ptr, len);
        return new TextDecoder('utf-8').decode(buffer);
    }

    document.querySelector('#submit').addEventListener('click', (event) => {
        const string = document.querySelector("#input").value;
        console.log(`original: "${string}"`)

        const start = performance.now();
        const stringLocation = toWASM(memory, alloc, string);
        // console.log(`copied string to WASM: ptr ${stringLocation.ptr}, len ${stringLocation.length}`);

        const resultLocation = solve(stringLocation.ptr, stringLocation.length);
        const resultPtr = Number(resultLocation >> 32n);
        const resultLen = Number(resultLocation & 0xFFFFFFFFn);
        // console.log(`returned from WASM: ptr ${resultPtr}, len ${resultLen}`);

        const result = fromWASM(memory, resultPtr, resultLen);
        // console.log(`returned value: "${result}"`);
        const took = performance.now() - start;

        const pre = document.createElement('pre')
        pre.innerText = result;

        const p = document.createElement('p')
        p.innerText = `took ~${took} ms (according to JS)`

        document.querySelector('body').appendChild(pre);
        document.querySelector('body').appendChild(p);

        free(stringLocation.ptr, stringLocation.length);
        free(resultPtr, resultLen);
    })
})
