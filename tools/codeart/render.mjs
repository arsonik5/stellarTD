// Renders a code-drawn Stellar TD sprite into its layers (pivot-2d.md section 6):
//   <name>.png        albedo, ground-level part (no lean)
//   <name>_top.png    albedo, raised part (leans with the camera, Unfallen-style), if the sprite has one
//   <name>_h.png      height map, all parts (-> normal map via tools/sprite_pipeline.py lit --height)
//   <name>_e.png      glow mask (windows, lamps, furnace mouths)
//   <name>_sheet.png  4x preview of the layers on a ground colour
// Usage: node tools/codeart/render.mjs art_src/codeart/smelter.mjs [--out art_src/codeart/out]

import { pathToFileURL } from "node:url";
import { resolve, basename, join } from "node:path";
import { mkdirSync, writeFileSync } from "node:fs";
import { createFrame, painterFor, composite } from "./vendor/pixelfx/core/index.js";
import { encodePNG } from "./vendor/pixelfx/png.mjs";
import { makeKit } from "./kit.mjs";

const args = process.argv.slice(2);
const file = args.find((a) => !a.startsWith("--"));
const outDir = args.includes("--out") ? args[args.indexOf("--out") + 1] : "art_src/codeart/out";
if (!file) {
  console.error("usage: node tools/codeart/render.mjs <sprite.mjs> [--out dir]");
  process.exit(2);
}
const mod = await import(pathToFileURL(resolve(file)).href);
const [W, Hh] = mod.meta.size;
const name = mod.meta.name ?? basename(file, ".mjs");

const frames = { base: createFrame(W, Hh), top: mod.meta.top ? createFrame(W, Hh) : null, h: createFrame(W, Hh), e: createFrame(W, Hh) };
const L = {};
for (const k of Object.keys(frames)) L[k] = frames[k] ? painterFor(frames[k]).place(0, 0) : null;
mod.draw(makeKit(L));

const rgba = (f) => composite(f, new Uint8ClampedArray(f.w * f.h * 4), null);
mkdirSync(outDir, { recursive: true });
const write = (suffix, f) => {
  const p = join(outDir, `${name}${suffix}.png`);
  writeFileSync(p, encodePNG(W, Hh, rgba(f)));
  return p;
};
const written = [write("", frames.base)];
if (frames.top) written.push(write("_top", frames.top));
written.push(write("_h", frames.h), write("_e", frames.e));

// preview: base+top composed, height, glow - 4x, on a ground colour
const Z = 4, gap = 8, panels = 4, PW = W * Z, PH = Hh * Z;
const sheet = new Uint8ClampedArray((PW * panels + gap * (panels + 1)) * (PH + gap * 2) * 4);
const SW = PW * panels + gap * (panels + 1), SH = PH + gap * 2;
for (let i = 0; i < SW * SH; i++) sheet.set([24, 24, 30, 255], i * 4);
const ground = [116, 104, 92];
const comp = (layers, bg) => {
  const out = new Uint8ClampedArray(W * Hh * 4);
  for (let i = 0; i < W * Hh; i++) out.set(bg ? [...bg, 255] : [0, 0, 0, 0], i * 4);
  for (const l of layers) {
    const d = rgba(l);
    for (let i = 0; i < W * Hh; i++) {
      const a = d[i * 4 + 3] / 255;
      if (a <= 0) continue;
      for (let c = 0; c < 3; c++) out[i * 4 + c] = d[i * 4 + c] * a + out[i * 4 + c] * (1 - a);
      out[i * 4 + 3] = 255;
    }
  }
  return out;
};
const panelsData = [
  comp([frames.base, ...(frames.top ? [frames.top] : [])], ground),
  comp([frames.base, ...(frames.top ? [frames.top] : [])], [40, 40, 52]),
  comp([frames.h], [0, 0, 0]),
  comp([frames.e], [0, 0, 0]),
];
panelsData.forEach((d, k) => {
  const ox = gap + k * (PW + gap), oy = gap;
  for (let y = 0; y < PH; y++)
    for (let x = 0; x < PW; x++) {
      const s = ((y / Z | 0) * W + (x / Z | 0)) * 4, t = ((oy + y) * SW + ox + x) * 4;
      sheet.set(d.subarray(s, s + 4), t);
    }
});
const sp = join(outDir, `${name}_sheet.png`);
writeFileSync(sp, encodePNG(SW, SH, sheet));
console.log("codeart:", [...written, sp].join("  "));
