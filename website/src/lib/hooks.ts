import { useCallback, useEffect, useRef, useState, useSyncExternalStore, type RefObject } from 'react';

const REDUCED = '(prefers-reduced-motion: reduce)';

export function prefersReducedMotion() {
  return window.matchMedia(REDUCED).matches;
}

export function usePrefersReducedMotion() {
  return useSyncExternalStore(
    (cb) => {
      const mq = window.matchMedia(REDUCED);
      mq.addEventListener('change', cb);
      return () => mq.removeEventListener('change', cb);
    },
    prefersReducedMotion,
  );
}

/** True while at least `threshold` of the element is on screen. */
export function useInView(ref: RefObject<Element | null>, threshold: number) {
  const [inView, setInView] = useState(false);
  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const io = new IntersectionObserver(
      (entries) => entries.forEach((e) => setInView(e.intersectionRatio >= threshold)),
      { threshold: [0, threshold, 0.6] },
    );
    io.observe(el);
    return () => io.disconnect();
  }, [ref, threshold]);
  return inView;
}

/** Calls `onFrame(dt)` every animation frame while `active`. dt is in seconds, capped at 50 ms. */
export function useFrame(active: boolean, onFrame: (dt: number) => void) {
  const cb = useRef(onFrame);
  useEffect(() => {
    cb.current = onFrame;
  });
  useEffect(() => {
    if (!active) return;
    let raf = 0;
    let last = 0;
    const loop = (now: number) => {
      const dt = last ? Math.min(0.05, (now - last) / 1000) : 0;
      last = now;
      cb.current(dt);
      raf = requestAnimationFrame(loop);
    };
    raf = requestAnimationFrame(loop);
    return () => cancelAnimationFrame(raf);
  }, [active]);
}

/** Copy text; `copied` stays true for 1.5 s so the icon can show a check. */
export function useCopy() {
  const [copied, setCopied] = useState(false);
  const timer = useRef(0);
  useEffect(() => () => clearTimeout(timer.current), []);
  const copy = useCallback((text: string) => {
    navigator.clipboard?.writeText(text).catch(() => {});
    setCopied(true);
    clearTimeout(timer.current);
    timer.current = window.setTimeout(() => setCopied(false), 1500);
  }, []);
  return [copied, copy] as const;
}

export type RepoInfo = { stars: number | null; license: string | null; pushed: string | null; tag: string | null };

/** Live stars, license, latest tag and last push from the GitHub API. Null until loaded or if the repo is private. */
export function useRepoInfo(githubUrl: string) {
  const [info, setInfo] = useState<RepoInfo | null>(null);
  useEffect(() => {
    const gh = githubUrl.match(/github\.com\/([^/]+)\/([^/#?]+)/);
    if (!gh || gh[1] === 'your-org') return;
    const base = `https://api.github.com/repos/${gh[1]}/${gh[2]}`;
    const get = (url: string) => fetch(url).then((r) => (r.ok ? r.json() : null)).catch(() => null);
    let live = true;
    Promise.all([get(base), get(`${base}/releases/latest`)]).then(([repo, rel]) => {
      if (live && repo) {
        setInfo({ stars: repo.stargazers_count ?? null, license: repo.license?.spdx_id ?? null, pushed: repo.pushed_at ?? null, tag: rel?.tag_name ?? null });
      }
    });
    return () => {
      live = false;
    };
  }, [githubUrl]);
  return info;
}
