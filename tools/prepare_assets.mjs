// Prepares the 3D assets for the native Android renderer (Filament).
//
//   cd tools && npm install
//   node prepare_assets.mjs <dir with the original web *.glb models> ../assets/models
//
// What it does
//  1. The original models use the EXT_texture_webp extension (REQUIRED). Filament cannot decode WebP, so every texture is
//     re-encoded as JPEG (base colour 1024px, metal/rough 512px; board 2048px / 1024px) and the extension is removed.
//  2. Generates table.glb (big dark disc with a soft radial pool of light) and the small flat "marker" models
//     used for selection / last move / legal moves / captures / check.
import { Document, NodeIO } from '@gltf-transform/core';
import { ALL_EXTENSIONS, KHRMaterialsUnlit } from '@gltf-transform/extensions';
import { prune, textureCompress } from '@gltf-transform/functions';
import sharp from 'sharp';
import fs from 'node:fs';

const [SRC, OUT] = process.argv.slice(2);
if (!SRC || !OUT) { console.error('usage: node prepare_assets.mjs <src models dir> <out dir>'); process.exit(1); }
fs.mkdirSync(OUT, { recursive: true });
const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);

const PIECES = ['king', 'queen', 'bishop', 'knight', 'rook', 'pawn'];
const FILES = [...PIECES.flatMap((p) => [`${p}_light`, `${p}_dark`]), 'board'];

async function convert(name) {
  const doc = await io.read(`${SRC}/${name}.glb`);
  const board = name === 'board';
  await doc.transform(
    textureCompress({ encoder: sharp, targetFormat: 'jpeg', quality: 92, slots: /baseColor/, resize: board ? [2048, 2048] : [1024, 1024] }),
    textureCompress({ encoder: sharp, targetFormat: 'jpeg', quality: 90, slots: /^(?!.*baseColor)/, resize: board ? [1024, 1024] : [512, 512] }),
    prune(),
  );
  for (const ext of doc.getRoot().listExtensionsUsed()) if (ext.extensionName === 'EXT_texture_webp') ext.dispose();
  await io.write(`${OUT}/${name}.glb`, doc);
  return fs.statSync(`${OUT}/${name}.glb`).size;
}

// ---------------------------------------------------------------- procedural models
const srgb2lin = (c) => { c /= 255; return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4); };
const hexLin = (hex, a = 1) => [srgb2lin((hex >> 16) & 255), srgb2lin((hex >> 8) & 255), srgb2lin(hex & 255), a];

function buildModel(name, { positions, uvs, indices, material }) {
  const doc = new Document();
  doc.createBuffer();
  const buffer = doc.getRoot().listBuffers()[0];
  const n = positions.length / 3;
  const normals = new Float32Array(n * 3);
  for (let i = 0; i < n; i++) normals[i * 3 + 1] = 1; // everything here is flat and faces +Y
  const acc = (type, array) => doc.createAccessor().setType(type).setArray(array).setBuffer(buffer);
  const prim = doc.createPrimitive()
    .setAttribute('POSITION', acc('VEC3', new Float32Array(positions)))
    .setAttribute('NORMAL', acc('VEC3', normals))
    .setIndices(acc('SCALAR', new Uint16Array(indices)));
  if (uvs) prim.setAttribute('TEXCOORD_0', acc('VEC2', new Float32Array(uvs)));
  prim.setMaterial(material(doc));
  const mesh = doc.createMesh(name).addPrimitive(prim);
  const node = doc.createNode(name).setMesh(mesh);
  doc.createScene(name).addChild(node);
  return doc;
}

function quad(h) {
  return { positions: [-h, 0, -h, -h, 0, h, h, 0, h, h, 0, -h], uvs: [0, 0, 0, 1, 1, 1, 1, 0], indices: [0, 1, 2, 0, 2, 3] };
}
function disc(r, seg, uvScale) {
  const positions = [0, 0, 0], uvs = [0.5, 0.5], indices = [];
  for (let i = 0; i <= seg; i++) {
    const a = (i / seg) * Math.PI * 2;
    const x = Math.cos(a) * r, z = Math.sin(a) * r;
    positions.push(x, 0, z); uvs.push(0.5 + (x / r) * 0.5 * uvScale, 0.5 + (z / r) * 0.5 * uvScale);
  }
  for (let i = 1; i <= seg; i++) indices.push(0, i + 1, i);
  return { positions, uvs, indices };
}
function ring(r0, r1, seg) {
  const positions = [], indices = [];
  for (let i = 0; i <= seg; i++) {
    const a = (i / seg) * Math.PI * 2, c = Math.cos(a), s = Math.sin(a);
    positions.push(c * r0, 0, s * r0, c * r1, 0, s * r1);
  }
  for (let i = 0; i < seg; i++) { const a = i * 2; indices.push(a, a + 3, a + 1, a, a + 2, a + 3); }
  return { positions, indices };
}

const unlitMat = (hex, alpha) => (doc) => {
  const ext = doc.createExtension(KHRMaterialsUnlit);
  return doc.createMaterial('marker').setBaseColorFactor(hexLin(hex, alpha)).setAlphaMode('BLEND').setDoubleSided(true)
    .setExtension('KHR_materials_unlit', ext.createUnlit());
};

async function png(width, height, fill) {
  const data = Buffer.alloc(width * height * 4);
  for (let y = 0; y < height; y++) for (let x = 0; x < width; x++) { const [r, g, b, a] = fill(x, y); const i = (y * width + x) * 4; data[i] = r; data[i + 1] = g; data[i + 2] = b; data[i + 3] = a; }
  return sharp(data, { raw: { width, height, channels: 4 } });
}
const lerp = (a, b, t) => a + (b - a) * t;
function gradient(stops, t) {
  t = Math.max(0, Math.min(1, t));
  for (let i = 1; i < stops.length; i++) if (t <= stops[i][0]) {
    const [t0, c0] = stops[i - 1], [t1, c1] = stops[i], k = (t - t0) / (t1 - t0 || 1);
    return c0.map((v, j) => lerp(v, c1[j], k));
  }
  return stops[stops.length - 1][1];
}

async function tableModel() {
  // same radial pool of light as the web version: canvas radial gradient (40px -> 512px of a 1024px canvas)
  const stops = [[0, [0x4a, 0x38, 0x2b]], [0.12, [0x33, 0x26, 0x1c]], [0.4, [0x1d, 0x15, 0x10]], [1, [0x15, 0x11, 0x0e]]];
  let seed = 12345; const rnd = () => ((seed = (seed * 1664525 + 1013904223) >>> 0) / 4294967296);
  const img = await png(1024, 1024, (x, y) => {
    const d = Math.hypot(x - 512, y - 512), c = gradient(stops, (d - 40) / (512 - 40)), n = (rnd() - 0.5) * 2;
    return [c[0] + n, c[1] + n, c[2] + n, 255];
  });
  const jpg = await img.jpeg({ quality: 92 }).toBuffer();
  const g = disc(90, 64, 1);
  const doc = buildModel('table', {
    ...g,
    material: (d) => {
      const tex = d.createTexture('table').setImage(new Uint8Array(jpg)).setMimeType('image/jpeg');
      return d.createMaterial('table').setBaseColorTexture(tex).setBaseColorFactor([srgb2lin(0xb0), srgb2lin(0xa0), srgb2lin(0x90), 1])
        .setRoughnessFactor(0.95).setMetallicFactor(0).setDoubleSided(true);
    },
  });
  await io.write(`${OUT}/table.glb`, doc);
}

async function checkModel() {
  const img = await png(128, 128, (x, y) => {
    const d = Math.hypot(x - 64, y - 64) / 64;
    const c = gradient([[0, [255, 40, 30, 0.95 * 255]], [0.6, [230, 40, 30, 0.5 * 255]], [1, [230, 40, 30, 0]]], (d * 64 - 4) / 60);
    return [c[0], c[1], c[2], c[3]];
  });
  const buf = await img.png().toBuffer();
  const doc = buildModel('marker_check', {
    ...quad(0.49),
    material: (d) => {
      const ext = d.createExtension(KHRMaterialsUnlit);
      const tex = d.createTexture('check').setImage(new Uint8Array(buf)).setMimeType('image/png');
      return d.createMaterial('marker_check').setBaseColorTexture(tex).setAlphaMode('BLEND').setDoubleSided(true).setExtension('KHR_materials_unlit', ext.createUnlit());
    },
  });
  await io.write(`${OUT}/marker_check.glb`, doc);
}

let total = 0;
for (const f of FILES) { const sz = await convert(f); total += sz; console.log(f.padEnd(14), (sz / 1e6).toFixed(2), 'MB'); }
await tableModel();
await checkModel();
await io.write(`${OUT}/marker_sel.glb`, buildModel('marker_sel', { ...quad(0.49), material: unlitMat(0x4fd18b, 0.55) }));
await io.write(`${OUT}/marker_last.glb`, buildModel('marker_last', { ...quad(0.49), material: unlitMat(0xf3c64a, 0.42) }));
await io.write(`${OUT}/marker_dot.glb`, buildModel('marker_dot', { ...disc(0.16, 24, 1), material: unlitMat(0x3fa66f, 0.8) }));
await io.write(`${OUT}/marker_cap.glb`, buildModel('marker_cap', { ...ring(0.36, 0.47, 48), material: unlitMat(0xe5533d, 0.85) }));
console.log('models total', (total / 1e6).toFixed(2), 'MB');
