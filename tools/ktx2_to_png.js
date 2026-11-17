// KTX2 (Basis UASTC/ETC1S) -> PNG, использует транскодер Basis из three.js
// node conv.js in.ktx2 out.png [normal]
const fs = require('fs'), path = require('path');
const { PNG } = require('pngjs');
const BASIS = require('./basis_cjs.js');
const wasmBinary = fs.readFileSync(path.join(__dirname, 'node_modules/three/examples/jsm/libs/basis/basis_transcoder.wasm'));

const jobs = [];
for (let i = 2; i < process.argv.length; i += 2) jobs.push([process.argv[i], process.argv[i + 1]]);
BASIS({ wasmBinary }).then(M => {
  M.initializeBasis();
  for (const [inp, out] of jobs) {
    try {
      const data = new Uint8Array(fs.readFileSync(inp));
      const f = new M.KTX2File(data);
      if (!f.isValid()) throw new Error('invalid ktx2');
      const w = f.getWidth(), h = f.getHeight();
      if (!f.startTranscoding()) throw new Error('startTranscoding failed');
      const fmt = 13; // cTFRGBA32
      const size = f.getImageTranscodedSizeInBytes(0, 0, 0, fmt);
      const dst = new Uint8Array(size);
      if (!f.transcodeImage(dst, 0, 0, 0, fmt, 0, -1, -1)) throw new Error('transcode failed');
      f.close(); f.delete();
      const png = new PNG({ width: w, height: h });
      png.data = Buffer.from(dst.buffer, 0, w * h * 4);
      fs.writeFileSync(out, PNG.sync.write(png));
      console.log('ok', out, w + 'x' + h);
    } catch (e) { console.log('FAIL', inp, e.message); }
  }
});
