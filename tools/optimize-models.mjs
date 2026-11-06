import { NodeIO } from '@gltf-transform/core';
import { ALL_EXTENSIONS } from '@gltf-transform/extensions';
import { weld, simplify, dedup, prune, textureCompress, flatten, join } from '@gltf-transform/functions';
import { MeshoptSimplifier } from 'meshoptimizer';
import sharp from 'sharp';
import fs from 'fs';
import path from 'path';

const OUT = process.argv[2];
fs.mkdirSync(OUT, { recursive: true });
const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);
await MeshoptSimplifier.ready;

// Heights in "square units" (1 square = 1.0) -> real Staunton proportions
const HEIGHT = { king: 1.5, queen: 1.3, bishop: 1.1, knight: 1.0, rook: 0.82, pawn: 0.74 };
const TRIS = { king: 22000, queen: 22000, bishop: 18000, knight: 24000, rook: 16000, pawn: 12000 };

const jobs = [
  ['m1/01_king_light.glb','king','light'],['m1/02_king_dark.glb','king','dark'],
  ['m1/03_queen_light.glb','queen','light'],['m1/04_queen_dark.glb','queen','dark'],
  ['m1/05_bishop_light.glb','bishop','light'],['m1/06_bishop_dark.glb','bishop','dark'],
  ['m2/07_knight_light.glb','knight','light'],['m2/08_knight_dark.glb','knight','dark'],
  ['m2/09_rook_light.glb','rook','light'],['m2/10_rook_dark.glb','rook','dark'],
  ['m2/11_pawn_light.glb','pawn','light'],['m2/12_pawn_dark.glb','pawn','dark'],
];
const SRC = process.argv[3] || './raw-models/'; // folder containing m1/*.glb, m2/*.glb and board.glb
let total = 0;
for (const [file, type, color] of jobs) {
  const doc = await io.read(SRC + file);
  await doc.transform(flatten());
  const root = doc.getRoot();
  const prim = root.listMeshes()[0].listPrimitives()[0];
  const pos = prim.getAttribute('POSITION');
  const n = pos.getCount();
  let minY = Infinity, maxY = -Infinity;
  const v = [0,0,0];
  for (let i=0;i<n;i++){ pos.getElement(i,v); minY=Math.min(minY,v[1]); maxY=Math.max(maxY,v[1]); }
  const h = maxY - minY;
  // base centre = mean xz of the lowest 2% of vertices
  let sumX=0, sumZ=0, c=0;
  for (let i=0;i<n;i++){ pos.getElement(i,v); if (v[1] < minY + h*0.02){ sumX+=v[0]; sumZ+=v[2]; c++; } }
  const cx = sumX/c, cz = sumZ/c;
  const s = HEIGHT[type] / h;
  for (let i=0;i<n;i++){ pos.getElement(i,v); pos.setElement(i,[(v[0]-cx)*s, (v[1]-minY)*s, (v[2]-cz)*s]); }
  const before = prim.getIndices().getCount()/3;
  await doc.transform(
    weld(),
    simplify({ simplifier: MeshoptSimplifier, ratio: Math.min(1, TRIS[type]/before), error: 0.002 }),
    dedup(), prune(),
    textureCompress({ encoder: sharp, targetFormat: 'webp', resize: [1024,1024], quality: 88 }),
  );
  const out = `${OUT}/${type}_${color}.glb`;
  await io.write(out, doc);
  const sz = fs.statSync(out).size; total += sz;
  const after = root.listMeshes()[0].listPrimitives()[0].getIndices().getCount()/3;
  console.log(type, color, 'baseOffset', cx.toFixed(4), cz.toFixed(4), 'scale', s.toFixed(3), 'tris', before, '->', after, (sz/1e6).toFixed(2)+'MB');
}
// board: scale by 20 so one square == 1.0
{
  const doc = await io.read(SRC + 'board.glb');
  await doc.transform(flatten());
  const prim = doc.getRoot().listMeshes()[0].listPrimitives()[0];
  const pos = prim.getAttribute('POSITION'); const v=[0,0,0];
  for (let i=0;i<pos.getCount();i++){ pos.getElement(i,v); pos.setElement(i,[v[0]*20,v[1]*20,v[2]*20]); }
  await doc.transform(textureCompress({ encoder: sharp, targetFormat: 'webp', resize: [2048,2048], quality: 88 }), prune());
  await io.write(`${OUT}/board.glb`, doc);
  const sz = fs.statSync(`${OUT}/board.glb`).size; total += sz;
  console.log('board', (sz/1e6).toFixed(2)+'MB');
}
console.log('TOTAL', (total/1e6).toFixed(2)+'MB');
