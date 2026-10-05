import type { CSSProperties } from 'react';

type Props = { d: string; size?: number; fill?: boolean; stroke?: number; className?: string; style?: CSSProperties };

/** A decorative 24×24 path icon, stroked by default. */
export function Icon({ d, size = 16, fill = false, stroke = 1.6, className, style }: Props) {
  const paint: CSSProperties = fill
    ? { fill: 'currentColor' }
    : { fill: 'none', stroke: 'currentColor', strokeWidth: stroke, strokeLinecap: 'round', strokeLinejoin: 'round' };
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" aria-hidden="true" className={className} style={{ ...paint, ...style }}>
      <path d={d} />
    </svg>
  );
}
