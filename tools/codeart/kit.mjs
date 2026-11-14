// Stellar TD code-drawn sprite kit (pivot-2d.md section 6). Every building is described ONCE as shapes; each shape
// writes its colour (albedo layer), its height (height layer, for exact normal maps) and its glow (emit layer) at
// the same time, so the lighting always matches the drawing. Drawing uses pixelfx's painter (vendor/, MIT).
//
// Rules every sprite follows (so all buildings belong together, Mindustry-style):
//   - light from the top-left: up/left bevels one step lighter, down/right bevels one step darker
//   - a 1 px INK outline on every solid part
//   - flat faces use few tones from one ramp; no gradients, no speckle noise inside shapes
//   - heights 0..1: 0 = ground, ~0.15 base plates, 0.4-0.9 housings, 1 = the tallest part

import { hex, rgb } from "./vendor/pixelfx/core/index.js";

const H = (s) => hex(s);

// Palette ramps, dark -> light. Futuristic, Astroneer-ish hulls on Mindustry-like muted metal.
export const PAL = {
  ink: H("#16161f"),
  hull: ["#33364a", "#565a70", "#868a9e", "#b8bccb", "#e4e6ee", "#ffffff"].map(H),     // painted white panels
  metal: ["#23242e", "#3b3d4b", "#5c5f70", "#858899", "#aeb1bf"].map(H),               // bare frames, plates
  orange: ["#5e2618", "#a8432a", "#e4703a", "#ffa65c", "#ffd9a0"].map(H),
  teal: ["#123038", "#1f6a70", "#36b0aa", "#7ae8d8", "#d4fff6"].map(H),
  yellow: ["#5a4214", "#a07c22", "#e6c040", "#fff08a"].map(H),
  glass: ["#141c2a", "#22324a", "#3a5574"].map(H),
  fire: ["#7a1e10", "#d8481c", "#ff8a2a", "#ffc860", "#fff2c0"].map(H),
  dirt: ["#2e2620", "#4a3c30", "#6e5a46"].map(H),
};

export const gray = (v) => {
  const g = Math.max(0, Math.min(255, Math.round(v * 255)));
  return rgb(g, g, g);
};

// signed distance to a rounded rectangle (negative inside)
function sdBox(px, py, x, y, w, h, r) {
  const cx = x + w / 2, cy = y + h / 2;
  const qx = Math.abs(px - cx) - (w / 2 - r), qy = Math.abs(py - cy) - (h / 2 - r);
  return Math.hypot(Math.max(qx, 0), Math.max(qy, 0)) + Math.min(Math.max(qx, qy), 0) - r;
}
const sdDisc = (px, py, cx, cy, r) => Math.hypot(px - cx, py - cy) - r;

/**
 * A kit bound to the layers of one sprite: { base, top, h, e } painters (top may be null).
 * layer "base" = sits on the ground (no lean); "top" = raised part that leans with the camera.
 */
export function makeKit(L) {
  const col = (layer) => (layer === "top" && L.top ? L.top : L.base);

  // generic solid: sd(x, y) < 0 inside. Paints albedo with bevel lighting + outline, and height.
  function solid(sd, bbox, { layer = "base", ramp = PAL.hull, tone = 3, z = 0.5, z0 = 0, bevel = 2, outline = true, flat = null }) {
    const [x0, y0, x1, y1] = bbox;
    const p = col(layer);
    const eps = 0.5;
    p.shade(x0, y0, x1, y1, (x, y) => {
      const d = sd(x, y);
      if (d >= 0) return;
      const e = -d;
      if (outline && e < 1) return PAL.ink;
      if (flat) return flat;
      if (e < bevel + (outline ? 1 : 0)) {
        const nx = sd(x + eps, y) - sd(x - eps, y), ny = sd(x, y + eps) - sd(x, y - eps);
        const lit = (-nx - ny) / (Math.hypot(nx, ny) * Math.SQRT2 || 1);
        if (lit > 0.3) return ramp[Math.min(tone + 1, ramp.length - 1)];
        if (lit < -0.3) return ramp[Math.max(tone - 1, 0)];
      }
      return ramp[tone];
    });
    L.h.shade(x0, y0, x1, y1, (x, y) => {
      const d = sd(x, y);
      if (d >= 0) return;
      const t = Math.min(1, -d / (bevel + 1.5));
      return gray(z0 + (z - z0) * (0.35 + 0.65 * Math.sin(t * Math.PI / 2)));
    });
  }

  return {
    PAL,
    /** Rounded box. */
    box(x, y, w, h, o = {}) {
      const r = o.r ?? 0;
      solid((px, py) => sdBox(px, py, x, y, w, h, r), [x - 1, y - 1, x + w + 1, y + h + 1], o);
    },
    /** Disc (pipes seen end-on, tanks, chimneys, drill heads). */
    disc(cx, cy, r, o = {}) {
      solid((px, py) => sdDisc(px, py, cx, cy, r), [cx - r - 1, cy - r - 1, cx + r + 1, cy + r + 1], o);
    },
    /** Paint on a face without changing its height (stripes, decals, markings). */
    paint(x, y, w, h, c, { layer = "base" } = {}) {
      col(layer).rect(x, y, w, h, c);
    },
    /** A recessed window that glows: dark frame, emissive fill (emit layer), a light glint. */
    window(x, y, w, h, glowRamp, { layer = "base", z = 0.5 } = {}) {
      const p = col(layer);
      p.rect(x, y, w, h, PAL.ink);
      p.rect(x + 1, y + 1, w - 2, h - 2, glowRamp[2]);
      p.rect(x + 1, y + 1, w - 2, 1, glowRamp[3]);
      p.rect(x + 2, y + 2, Math.max(1, w - 4), Math.max(1, h - 4), glowRamp[Math.min(4, glowRamp.length - 1)]);
      L.e.rect(x + 1, y + 1, w - 2, h - 2, glowRamp[3]);
      L.h.rect(x, y, w, h, gray(z - 0.08));
    },
    /** Status light: one bright pixel cluster + glow. */
    lamp(x, y, ramp, { layer = "base" } = {}) {
      const p = col(layer);
      p.rect(x - 1, y, 3, 1, ramp[2]);
      p.rect(x, y - 1, 1, 3, ramp[2]);
      p.px(x, y, ramp[ramp.length - 1]);
      L.e.rect(x - 1, y - 1, 3, 3, ramp[3]);
    },
    /** Bolt/rivet: highlight pixel with a shadow pixel below-right. */
    bolt(x, y, { layer = "base", ramp = PAL.metal } = {}) {
      const p = col(layer);
      p.px(x, y, ramp[ramp.length - 1]);
      p.px(x + 1, y + 1, ramp[0]);
    },
    /** Vent slats (horizontal), recessed. */
    vent(x, y, w, n, { layer = "base", ramp = PAL.metal, z = 0.5 } = {}) {
      const p = col(layer);
      for (let i = 0; i < n; i++) {
        p.rect(x, y + i * 2, w, 1, PAL.ink);
        p.rect(x, y + i * 2 + 1, w, 1, ramp[3]);
        L.h.rect(x, y + i * 2, w, 1, gray(z - 0.06));
      }
    },
    /** Baked wear: clumps of dirt that thicken toward the bottom of a region (2x2-pixel cells from a fixed hash,
     *  so it reads as grime, not speckle). amount 0..1. */
    grime(x, y, w, h, amount = 0.35, { layer = "base", seed = 1 } = {}) {
      const p = col(layer);
      const cell = (cx, cy) => (((cx * 73856093) ^ (cy * 19349663) ^ (seed * 83492791)) >>> 0) % 1000 / 1000;
      for (let yy = y; yy < y + h; yy++)
        for (let xx = x; xx < x + w; xx++) {
          const c = p.get(xx, yy);
          if (!c || c === PAL.ink) continue;
          const k = Math.pow((yy - y) / Math.max(1, h - 1), 1.5);
          // a clump: this 2x2 cell and its neighbour both under the threshold
          const v = (cell(xx >> 1, yy >> 1) + cell((xx >> 1) + 1, yy >> 1) * 0.5) / 1.5;
          if (v < k * amount) p.px(xx, yy, PAL.dirt[v < k * amount * 0.4 ? 0 : 1]);
        }
    },
    /** Diagonal hazard stripes inside a rectangle. */
    hazard(x, y, w, h, { layer = "base", a = PAL.yellow[2], b = PAL.ink, period = 6 } = {}) {
      const p = col(layer);
      for (let yy = y; yy < y + h; yy++)
        for (let xx = x; xx < x + w; xx++) p.px(xx, yy, ((xx + yy) % period) < period / 2 ? a : b);
    },
  };
}
