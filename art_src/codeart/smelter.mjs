// Smelter, 2x2 tiles (64 x 64 px at 32 px per tile). Seen straight down; the raised housing is the `top` layer,
// which leans with the camera in game. Drawn with tools/codeart/kit.mjs.
export const meta = { name: "smelter", size: [64, 64], top: true };

export function draw(k) {
  const { PAL } = k;
  // --- ground level: base plate, ports, hazard edge
  k.box(2, 2, 60, 60, { r: 5, ramp: PAL.metal, tone: 2, z: 0.15, bevel: 2 });
  k.box(0, 25, 7, 14, { r: 1, ramp: PAL.metal, tone: 1, z: 0.2 });          // input port (west)
  k.box(57, 25, 7, 14, { r: 1, ramp: PAL.metal, tone: 1, z: 0.2 });         // output port (east)
  k.paint(2, 29, 3, 6, PAL.ink);
  k.paint(59, 29, 3, 6, PAL.ink);
  k.paint(60, 30, 1, 4, PAL.orange[3]);                                     // output marker
  k.hazard(10, 56, 44, 3);
  for (const [x, y] of [[6, 6], [56, 6], [6, 56], [56, 56]]) k.bolt(x, y);
  k.grime(3, 38, 58, 23, 0.45);

  // --- raised housing (leans)
  const top = { layer: "top" };
  k.box(10, 8, 44, 46, { ...top, r: 9, ramp: PAL.hull, tone: 3, z: 0.75, z0: 0.15, bevel: 3 });
  k.box(13, 22, 38, 4, { ...top, flat: PAL.orange[2], outline: false, z: 0.75 });   // accent band
  k.paint(13, 22, 38, 1, PAL.orange[3], top);
  // intake hopper
  k.box(15, 10, 18, 11, { ...top, r: 2, ramp: PAL.metal, tone: 3, z: 0.88, z0: 0.75 });
  k.box(18, 13, 12, 5, { ...top, flat: PAL.ink, outline: false, z: 0.8 });
  k.paint(19, 14, 10, 1, PAL.orange[1], top);                                       // ore glints in the hopper
  // chimney
  k.disc(43, 15, 6, { ...top, ramp: PAL.metal, tone: 2, z: 1.0, z0: 0.75, bevel: 2 });
  k.disc(43, 15, 3, { ...top, flat: PAL.ink, outline: false, z: 0.9 });
  k.lamp(43, 15, PAL.fire, top);
  // vents and the furnace window
  k.vent(15, 29, 12, 3, { ...top, z: 0.75 });
  k.vent(37, 29, 12, 3, { ...top, z: 0.75 });
  k.window(20, 38, 24, 8, PAL.fire, { ...top, z: 0.75 });
  k.lamp(48, 49, PAL.teal, top);
  for (const [x, y] of [[14, 48], [49, 12]]) k.bolt(x, y, { ...top, ramp: PAL.hull });
  k.grime(11, 42, 42, 12, 0.4, { ...top, seed: 2 });
}
