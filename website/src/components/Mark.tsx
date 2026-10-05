import type { CSSProperties } from 'react';
import { MARK_H, MARK_PATH, MARK_W } from '../brand/mark';

type Props = { height: number; label?: string; className?: string; style?: CSSProperties };

/** The Murmur mark in `currentColor`. Decorative unless given a label. */
export function Mark({ height, label, className, style }: Props) {
  return (
    <svg
      viewBox={`0 0 ${MARK_W} ${MARK_H}`}
      width={Math.round(((height * MARK_W) / MARK_H) * 10) / 10}
      height={height}
      role={label ? 'img' : undefined}
      aria-label={label}
      aria-hidden={label ? undefined : true}
      className={className}
      style={style}
    >
      <path d={MARK_PATH} fill="currentColor" fillRule="evenodd" />
    </svg>
  );
}
