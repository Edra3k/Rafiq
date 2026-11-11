// Rafiq's look, in one place (port of RafiqLook.swift): a dome that rises to a point,
// like a lantern's cap, on a soft, squarer base; ivory to sand; a golden crescent
// on top; warm golden cheeks. The engine, the outfits and the greeting draw from here.

/** How far the dome rises above the base, in units of the half height. */
export const DOME_HEIGHT = 1.3;
const DOME_TAPER = 2.0;
const DOME_CURVE = 1.4;
const BASE_EXPONENT = 3.2;

export const BODY_TOP: [number, number, number] = [0.984, 0.965, 0.925]; // #FBF6EC
export const BODY_BOTTOM: [number, number, number] = [0.871, 0.804, 0.69]; // #DECDB0
export const BODY_TOP_CSS = "rgb(251,246,236)";
export const BODY_BOTTOM_CSS = "rgb(222,205,176)";
export const INK_CSS = "rgb(19,33,63)"; // #13213F
export const GOLD_CSS = "rgb(232,182,74)"; // #E8B64A
export const GOLD_RGB = "232,182,74";

/** Inside the silhouette, centred on the origin, y down. */
export function contains(x: number, y: number, rx: number, ry: number): boolean {
  if (rx <= 0 || ry <= 0) return false;
  if (y >= 0) return Math.pow(Math.abs(x / rx), BASE_EXPONENT) + Math.pow(Math.abs(y / ry), BASE_EXPONENT) <= 1;
  const t = -y / (ry * DOME_HEIGHT);
  if (t >= 1) return false;
  return Math.abs(x) <= rx * Math.pow(1 - Math.pow(t, DOME_TAPER), DOME_CURVE);
}

/** The edge in the direction (ca, sa): every ray from the centre crosses it once. */
export function edgePoint(ca: number, sa: number, rx: number, ry: number): { x: number; y: number } {
  let lo = 0;
  let hi = Math.max(rx, ry * DOME_HEIGHT) * 1.05;
  for (let i = 0; i < 18; i++) {
    const mid = (lo + hi) / 2;
    if (contains(ca * mid, sa * mid, rx, ry)) lo = mid;
    else hi = mid;
  }
  return { x: ca * lo, y: sa * lo };
}

/** The closed silhouette. */
export function silhouette(rx: number, ry: number, points = 96): Path2D {
  const p = new Path2D();
  for (let i = 0; i <= points; i++) {
    const a = (i / points) * Math.PI * 2;
    const pt = edgePoint(Math.cos(a), Math.sin(a), rx, ry);
    if (i === 0) p.moveTo(pt.x, pt.y);
    else p.lineTo(pt.x, pt.y);
  }
  p.closePath();
  return p;
}

/** The golden ball and crescent above the point of the dome, in body coordinates. */
export function drawFinial(x: CanvasRenderingContext2D, ry: number, R: number, opacity = 1) {
  if (opacity <= 0.01) return;
  const tipY = -ry * DOME_HEIGHT;
  x.save();
  x.globalAlpha *= opacity;
  x.fillStyle = GOLD_CSS;
  const ball = R * 0.075;
  x.beginPath();
  x.arc(0, tipY - R * 0.05 - ball, ball, 0, Math.PI * 2);
  x.fill();
  // Large enough to read on the small Rafiqs (compact island, pills), as on the Mac.
  const r = R * 0.2;
  const cy = tipY - R * 0.38;
  // A disc with a smaller disc taken out (even-odd inside a clip of the disc).
  x.beginPath();
  x.arc(0, cy, r, 0, Math.PI * 2);
  x.clip();
  x.beginPath();
  x.rect(-r * 2, cy - r * 2, r * 4, r * 4);
  x.arc(r * 0.55, cy - r * 0.2, r * 0.82, 0, Math.PI * 2);
  x.fill("evenodd");
  x.restore();
}
