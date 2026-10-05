import * as THREE from 'three';
import { MARK_H, MARK_PATH, MARK_W } from '../brand/mark';

/** Seeded PRNG (mulberry32) so the flock looks the same on every load. */
export function rng(seed: number) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/** Paper colors as sRGB hex. Light reads as the clay logo on ivory; dark is the logo's dark-surface tint. */
export const PALETTE = {
  light: [0xb54c3c, 0xb54c3c, 0xb54c3c, 0xa8463a, 0xc2574a, 0xcc6352, 0x9c3f33, 0xd9705f, 0xe8d3c2],
  dark: [0xd9705f, 0xd9705f, 0xe38472, 0xc8604f, 0xb54c3c, 0xf0c9bb, 0xf6eee4],
};

/**
 * One folded paper flake: a dart lying in the XZ plane (normal +Y), nose toward +Z,
 * with both wings lifted off the centre crease so the two halves catch the light differently.
 */
export function flakeGeometry(size: number) {
  const s = size;
  const lift = s * 0.14;
  const nose = [0, 0, 0.6 * s];
  const tail = [0, 0, -0.4 * s];
  const left = [-0.5 * s, lift, -0.25 * s];
  const right = [0.5 * s, lift, -0.25 * s];
  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.Float32BufferAttribute([...nose, ...tail, ...left, ...nose, ...right, ...tail], 3));
  geo.translate(0, -lift / 2, 0.075 * s);
  geo.computeVertexNormals(); // unshared vertices, so each half gets its own flat normal
  return geo;
}

export type LogoPoint = [x: number, y: number, z: number];

const cache = new Map<string, LogoPoint[]>();

/**
 * Evenly spaced points covering the Murmur mark, centred on the origin and `width` units wide.
 * Rasterises the vector mark, then dart-throws over its filled pixels so the flakes tile it without clumping.
 */
export function logoPoints(count: number, width: number, seed = 11): LogoPoint[] {
  const key = `${count}:${width}:${seed}`;
  const hit = cache.get(key);
  if (hit) return hit;

  const S = 600;
  const H = Math.round((S * MARK_H) / MARK_W);
  const cv = document.createElement('canvas');
  cv.width = S;
  cv.height = H;
  const g = cv.getContext('2d', { willReadFrequently: true })!;
  g.scale(S / MARK_W, H / MARK_H);
  g.fill(new Path2D(MARK_PATH), 'evenodd');
  const alpha = g.getImageData(0, 0, S, H).data;

  const cand: number[] = [];
  for (let i = 0; i < S * H; i++) if (alpha[i * 4 + 3] > 127) cand.push(i);
  const R = rng(seed);
  for (let i = cand.length - 1; i > 0; i--) {
    const j = Math.floor(R() * (i + 1));
    [cand[i], cand[j]] = [cand[j], cand[i]];
  }

  // Random sequential packing reaches roughly 0.7·area/r² points; shrink r until we have enough.
  const xy: number[] = [];
  let r = Math.sqrt((0.7 * cand.length) / count);
  while (xy.length / 2 < count && r >= 0.5) {
    const cell = r / Math.SQRT2;
    const gw = Math.ceil(S / cell) + 1;
    const gh = Math.ceil(H / cell) + 1;
    const grid = new Int32Array(gw * gh).fill(-1);
    const put = (k: number) => {
      grid[Math.floor(xy[k * 2 + 1] / cell) * gw + Math.floor(xy[k * 2] / cell)] = k;
    };
    for (let k = 0; k < xy.length / 2; k++) put(k);
    const r2 = r * r;
    for (const idx of cand) {
      if (xy.length / 2 >= count) break;
      const x = (idx % S) + R();
      const y = Math.floor(idx / S) + R();
      const gx = Math.floor(x / cell);
      const gy = Math.floor(y / cell);
      let ok = true;
      for (let yy = Math.max(0, gy - 2); ok && yy <= Math.min(gh - 1, gy + 2); yy++) {
        for (let xx = Math.max(0, gx - 2); xx <= Math.min(gw - 1, gx + 2); xx++) {
          const k = grid[yy * gw + xx];
          if (k < 0) continue;
          const dx = xy[k * 2] - x;
          const dy = xy[k * 2 + 1] - y;
          if (dx * dx + dy * dy < r2) {
            ok = false;
            break;
          }
        }
      }
      if (ok) {
        xy.push(x, y);
        put(xy.length / 2 - 1);
      }
    }
    r *= 0.9;
  }

  const unit = width / S;
  const pts: LogoPoint[] = [];
  for (let k = 0; k < xy.length / 2; k++) {
    pts.push([(xy[k * 2] - S / 2) * unit, -(xy[k * 2 + 1] - H / 2) * unit, (R() - 0.5) * 0.012]);
  }
  cache.set(key, pts);
  return pts;
}
