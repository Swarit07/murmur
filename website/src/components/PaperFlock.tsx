import { useEffect, useRef, useState } from 'react';
import * as THREE from 'three';
import { flakeGeometry, logoPoints, PALETTE, rng } from '../lib/murmur-flock';
import { prefersReducedMotion } from '../lib/hooks';
import { Mark } from './Mark';

type Still = 'swirl' | 'wave' | 'logo';
type Props = {
  label: string;
  className?: string;
  /** Lighting and colors for a dark surface. */
  dark?: boolean;
  /** Freeze on one beat of the loop instead of animating. Reduced motion freezes on the logo. */
  still?: Still;
  /** Restart the loop from the swirl each time the flock scrolls into view. */
  replayOnEnter?: boolean;
};

// 15 s loop: swirl, sweep into a voice wave at 2.4 s, settle into the logo at 5.8 s, release at 13.1 s.
const PERIOD = 15;
const T_WAVE = 2.4;
const D_WAVE = 1.5;
const T_LOGO = 5.8;
const D_LOGO = 1.7;
const FIXED: Record<Still, number> = { swirl: 1.2, wave: 4.6, logo: 11 };

type Flake = {
  logo: [number, number, number];
  th: number; w: number; rad: number; off: [number, number, number]; ph: number; v: number;
  roll: number; tx: number; ty: number; sc: number; d1: number; d2: number; wx: number;
};

const ease = (x: number) => (x <= 0 ? 0 : x >= 1 ? 1 : x * x * (3 - 2 * x));

function swirl(p: Flake, t: number, out: THREE.Vector3) {
  const a = p.th + t * p.w;
  const Rr = 0.21 * p.rad;
  const dx = Math.sin(t * 0.5) * 0.02;
  return out.set(
    Math.sin(a) * Rr * 0.95 + p.off[0] + dx,
    Math.sin(2 * a) * Rr * 0.42 + p.off[1] + Math.sin(t * 1.7 + p.ph) * 0.015,
    Math.cos(a) * Rr * 0.45 + p.off[2] * 0.6,
  );
}

function wave(p: Flake, t: number, out: THREE.Vector3) {
  const x = p.wx;
  const env = Math.pow(Math.max(0, Math.sin((Math.PI * (x + 0.31)) / 0.62)), 0.8);
  const A = 0.12 * env * Math.pow(Math.abs(Math.sin(x * 64 - t * 3.2)), 1.5) + 0.005;
  return out.set(x, A * p.v, p.logo[2] + Math.sin(t * 2 + p.ph) * 0.004);
}

/** Folded-paper murmuration that sweeps into a voice wave and settles into the Murmur logo. */
export function PaperFlock({ label, className, dark = false, still, replayOnEnter = false }: Props) {
  const host = useRef<HTMLDivElement>(null);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    const el = host.current;
    if (!el) return;
    const fixed = still ? FIXED[still] : prefersReducedMotion() ? FIXED.logo : undefined;

    let renderer: THREE.WebGLRenderer;
    try {
      renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true });
    } catch {
      setFailed(true);
      return;
    }
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    renderer.outputColorSpace = THREE.SRGBColorSpace;
    const canvas = renderer.domElement;
    el.appendChild(canvas);

    const scene = new THREE.Scene();
    const camera = new THREE.PerspectiveCamera(30, 1, 0.01, 10);
    scene.add(new THREE.HemisphereLight(dark ? 0xf6eee4 : 0xfff8ee, dark ? 0x3a3633 : 0xcfc4b4, dark ? 2.0 : 2.4));
    const key = new THREE.DirectionalLight(0xfff3e6, 1.6);
    key.position.set(0.3, 0.5, 0.8);
    scene.add(key);

    const pts = logoPoints(1300, 0.6);
    const N = pts.length;
    const R = rng(5);
    const geometry = flakeGeometry(0.0155);
    const material = new THREE.MeshStandardMaterial({ color: 0xffffff, roughness: 0.95, metalness: 0, side: THREE.DoubleSide });
    const mesh = new THREE.InstancedMesh(geometry, material, N);
    const pal = dark ? PALETTE.dark : PALETTE.light;
    const col = new THREE.Color();
    const P: Flake[] = pts.map((p, i) => {
      mesh.setColorAt(i, col.setHex(pal[Math.floor(R() * pal.length)]));
      return {
        logo: p, th: R() * Math.PI * 2, w: 0.75 + R() * 0.5, rad: 0.7 + R() * 0.45,
        off: [(R() - 0.5) * 0.09, (R() - 0.5) * 0.07, (R() - 0.5) * 0.1], ph: R() * 6.28, v: R() * 2 - 1,
        roll: R() * 6.28, tx: (R() - 0.5) * 0.4, ty: (R() - 0.5) * 0.4, sc: 0.8 + R() * 0.4,
        d1: ((p[0] + 0.3) / 0.6) * 0.9 + R() * 0.25, d2: R() * 0.7, wx: 0,
      };
    });
    // Spread the flakes evenly along the wave in the same left-to-right order they hold in the logo.
    const order = P.map((_, i) => i).sort((i, j) => P[i].logo[0] - P[j].logo[0]);
    order.forEach((idx, r) => {
      P[idx].wx = -0.3 + (r / (N - 1)) * 0.6 + (R() - 0.5) * 0.004;
    });
    scene.add(mesh);

    const dummy = new THREE.Object3D();
    const a = new THREE.Vector3();
    const b = new THREE.Vector3();
    const c = new THREE.Vector3();
    const nx = new THREE.Vector3();
    const qFly = new THREE.Quaternion();
    const qFace = new THREE.Quaternion();
    const e = new THREE.Euler();

    // Cursor: flakes within 0.06 units of the pointer's spot on the z = 0 plane drift away from it.
    const ray = new THREE.Raycaster();
    const plane = new THREE.Plane(new THREE.Vector3(0, 0, 1), 0);
    const hitPt = new THREE.Vector3(9, 9, 0);
    const mouse = new THREE.Vector2();
    const push = new Float32Array(N * 3);
    let pointer: { x: number; y: number } | null = null;

    let t0 = performance.now();
    let raf = 0;
    let visible = false;

    function frame() {
      const t = fixed ?? (performance.now() - t0) / 1000;
      const tt = fixed ?? t % PERIOD;
      const rect = canvas.getBoundingClientRect();
      const mx = pointer ? (pointer.x - rect.left) / rect.width : -1;
      const my = pointer ? (pointer.y - rect.top) / rect.height : -1;
      if (mx >= 0 && mx <= 1 && my >= 0 && my <= 1) {
        ray.setFromCamera(mouse.set(mx * 2 - 1, -my * 2 + 1), camera);
        ray.ray.intersectPlane(plane, hitPt);
      } else hitPt.set(9, 9, 0);

      for (let i = 0; i < N; i++) {
        const p = P[i];
        const rel = ease((tt - (PERIOD - 1.9) - p.d2 * 0.6) / 1.2);
        const w1 = ease((tt - T_WAVE - p.d1) / D_WAVE) * (1 - rel);
        const w2 = ease((tt - T_LOGO - p.d2) / D_LOGO) * (1 - rel);
        swirl(p, t, a);
        swirl(p, t + 0.03, nx);
        wave(p, tt, b);
        c.set(p.logo[0], p.logo[1], p.logo[2] + Math.sin(t * 1.6 + p.ph) * 0.002 * w2);
        dummy.position.copy(a);
        dummy.lookAt(nx);
        dummy.position.copy(a).lerp(b, w1).lerp(c, w2);

        const dx = dummy.position.x - hitPt.x;
        const dy = dummy.position.y - hitPt.y;
        const d2 = dx * dx + dy * dy;
        let tx = 0;
        let ty = 0;
        let tz = 0;
        if (d2 < 0.0036) {
          const d = Math.sqrt(d2) + 1e-4;
          const f = 1 - d / 0.06;
          tx = (dx / d) * f * 0.035;
          ty = (dy / d) * f * 0.035;
          tz = f * 0.04;
        }
        const j = i * 3;
        push[j] += (tx - push[j]) * 0.12;
        push[j + 1] += (ty - push[j + 1]) * 0.12;
        push[j + 2] += (tz - push[j + 2]) * 0.12;
        dummy.position.x += push[j];
        dummy.position.y += push[j + 1];
        dummy.position.z += push[j + 2];

        // Fly nose-first during the swirl, then turn to face the viewer with a little flutter.
        qFly.copy(dummy.quaternion);
        const flut = (1 - w2) * 0.35 + 0.06;
        e.set(Math.PI / 2 + Math.sin(t * 2.3 + p.ph) * flut + p.tx * 0.6, p.roll, Math.cos(t * 1.9 + p.ph) * flut + p.ty * 0.6);
        qFace.setFromEuler(e);
        dummy.quaternion.copy(qFly).slerp(qFace, w1);
        dummy.scale.setScalar(p.sc);
        dummy.updateMatrix();
        mesh.setMatrixAt(i, dummy.matrix);
      }
      mesh.instanceMatrix.needsUpdate = true;
      renderer.render(scene, camera);
    }

    const tick = () => {
      raf = 0;
      frame();
      if (visible) raf = requestAnimationFrame(tick);
    };
    const start = () => {
      if (fixed === undefined && !raf) raf = requestAnimationFrame(tick);
    };
    const replay = () => {
      t0 = performance.now();
      if (fixed !== undefined) frame();
    };

    function resize() {
      const w = el!.clientWidth;
      const h = el!.clientHeight;
      if (!w || !h) return;
      const asp = w / h;
      const tan = Math.tan(THREE.MathUtils.degToRad(15));
      camera.aspect = asp;
      const dist = Math.max(0.34 / (tan * asp), 0.22 / tan);
      camera.position.set(0, 0.02, dist);
      camera.lookAt(0, 0, 0);
      camera.updateProjectionMatrix();
      renderer.setSize(w, h, false);
      if (fixed !== undefined || !visible) frame();
    }

    const ro = new ResizeObserver(resize);
    ro.observe(el);
    resize();

    const io = new IntersectionObserver(([entry]) => {
      const was = visible;
      visible = entry.isIntersecting;
      if (visible && !was && replayOnEnter) replay();
      if (visible) start();
    });
    io.observe(el);

    const onMove = (ev: PointerEvent) => {
      pointer = { x: ev.clientX, y: ev.clientY };
    };
    const onLeave = () => {
      pointer = null;
    };
    window.addEventListener('pointermove', onMove, { passive: true });
    document.documentElement.addEventListener('pointerleave', onLeave);
    canvas.addEventListener('click', replay);

    return () => {
      cancelAnimationFrame(raf);
      visible = false;
      ro.disconnect();
      io.disconnect();
      window.removeEventListener('pointermove', onMove);
      document.documentElement.removeEventListener('pointerleave', onLeave);
      canvas.removeEventListener('click', replay);
      geometry.dispose();
      material.dispose();
      mesh.dispose();
      renderer.dispose();
      renderer.forceContextLoss();
      canvas.remove();
    };
  }, [dark, still, replayOnEnter]);

  return (
    <div ref={host} className={`flock${className ? ` ${className}` : ''}`} role="img" aria-label={label}>
      {failed && <Mark height={96} className="flock-fallback" />}
    </div>
  );
}
