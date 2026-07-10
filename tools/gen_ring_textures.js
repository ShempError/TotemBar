// TotemBar - tools/gen_ring_textures.js
// Generates the Pulse UI ring flipbook textures: bevel frame band, neon
// duration arc with rounded caps + comet tip, windowed asymmetric ripple,
// a fx sheet for glow/hover/pushed/flash cells, and a second thin inner arc
// sheet for the pulse countdown.
//
// textures/ring_round.tga - 512x512, 8x8 grid of 64x64 cells (center 32):
//   cells 0..61 (62 states) - duration arc fill frames, fraction f = i/61,
//     clockwise from 12 o'clock, neon radial profile, rounded caps, comet tip
//   cell 62  - wave ring: asymmetric ripple (steep outer front, soft inner
//     tail) + faint secondary inner ripple, hard-windowed to 0 before the
//     cell edge (no square artifact at any runtime scale)
//   cell 63  - decorative bevel frame band ("schicker Rahmen"): opaque metal
//     ring (outline / outer highlight / shaded+top-lit body / inner groove /
//     inner catch-light rim), same corner-cover bounds [19, 30.5] as v2.
//     Session-76: SHADOW is the only look now (grey/gold retired - see
//     below); the band reads as an unobtrusive dark rim shadow.
//
// textures/ring_fx.tga - 256x256, 2x2 grid of 128x128 cells (center 64):
//   cell 0 "glow", cell 1 "hover", cell 2 "pushed", cell 3 "flash"
//
// textures/ring_pulsearc.tga - 512x512, 8x8 grid of 64x64 cells (center 32):
//   cells 0..61 (62 states) - pulse-countdown arc fill frames, fraction
//     f = i/61, clockwise from 12 o'clock, thin white neon band INSIDE the
//     duration arc's radius (own radial zone, no overlap - see PULSE below),
//     rounded caps, NO comet tip (calmer than the duration arc on purpose).
//   cells 62/63 - unused, fully transparent (spare, mirrors ring_round.tga's
//     layout so both sheets can share the same cell-index math at runtime).
//
// All files: 32-bit uncompressed TGA, bottom-up rows (descriptor 0x08) -
// exactly the header pfUI's own TGAs use (verified to render on 1.12).
// Zero dependencies. Run: node tools/gen_ring_textures.js
//
// --- Session 76 texture rebuild (user decisions) --------------------------
// (1) SHADOW is the only frame-band look. The Session-75 grey/gold/shadow
//     variant comparison (`--variant <name>`) and the Rev 5 ring-skin picker
//     (`tracks` target -> textures/ring_tracks.tga, cells for grey/gold/
//     shadow selectable at runtime) are RETIRED - that machinery is gone
//     from this file and textures/ring_tracks.tga has been deleted from
//     disk. Cell 63 of ring_round.tga now renders the shadow profile
//     directly (previously reachable only via `--variant shadow`) as the
//     ONLY frame band, unconditionally. Radial zone boundaries in FRAME are
//     UNCHANGED (corner-cover contract: opaque band still spans exactly
//     [19, 30.5]) - only the color source collapsed from a per-variant table
//     to one fixed FRAME_COLORS set.
// (2) The duration arc (cells 0..61 of ring_round.tga) got thinner and moved
//     outward: radii 24.2..27.6 (was 22..27.6), so it now sits right against
//     the frame band's outer edge with the pulse arc's own band living
//     further inside, with a clean gap between them (see PULSE below - the
//     verification point is that r in (22.5, 24.2) is 0 alpha on BOTH arc
//     sheets, i.e. no overlap).
// (3) NEW ring_pulsearc.tga sheet: the pulse-to-next-tick countdown, formerly
//     planned as a linear bar under the icon (see
//     docs/superpowers/sdd/... pulse-ui-design.md), is now a second circular
//     arc drawn INSIDE the duration arc, occupying its own thin radial band
//     (19.5..22.5) with a calmer (no comet tip) white neon profile.
// ---------------------------------------------------------------------------

const fs = require("fs");
const path = require("path");

// ---------------------------------------------------------------------
// Shared small-number helpers
// ---------------------------------------------------------------------
function clamp(v, lo, hi) { return v < lo ? lo : (v > hi ? hi : v); }
function lerp(a, b, t) { return a + (b - a) * t; }
function smoothstep(t) { const c = clamp(t, 0, 1); return c * c * (3 - 2 * c); }

// Angular fraction 0..1 clockwise from 12 o'clock for offsets (dx, dy),
// image coords (y grows downward).
function angFrac(dx, dy) {
  let a = Math.atan2(dx, -dy); // 0 at top, positive clockwise
  if (a < 0) a += 2 * Math.PI;
  return a / (2 * Math.PI);
}

// ===========================================================================
// ring_round.tga - 512x512, 8x8 grid of 64x64 cells
// ===========================================================================
const CELL = 64;          // px per grid cell
const GRID = 8;            // 8x8 cells
const SIZE = CELL * GRID;  // 512
const ARC_FRAMES = 62;     // duration-arc fill states, cells 0..61
const WAVE_CELL = 62;
const FRAME_CELL = 63;
const SS = 5;              // supersampling factor per axis (25 samples/px; bumped from 4 for smoother arcs)

// --- B. Duration arc v4 ("neon tube", thinner + moved outward against the
// frame's outer edge - Session 76) ------------------------------------------
const ARC = {
  inner: 24.2,
  outer: 27.6,
  centerR: 25.9,        // r_c: neon profile peak / cap-center radial line
  neonSigma: 1.15,      // gaussian width of the neon falloff off the center line
  neonBase: 110,        // alpha floor at the band edges
  neonPeak: 145,        // additional alpha at the center line (base+peak = 255)
  capRadius: (27.6 - 24.2) / 2, // 1.7: rounded-cap disc radius (= half band width)
  cometDeg: 14,         // degrees before the leading end that get comet-hot
};

// --- NEW: pulse-countdown arc ("circular inner arc on the band" -
// Session 76 replaces the earlier linear-bar-under-icon plan). Own thin
// radial band strictly INSIDE the duration arc's inner edge (22.5 < 24.2,
// a clean >=1.7-unit gap - see the header comment + rev verification: r in
// (22.5, 24.2) must read 0 alpha on both sheets). No comet tip - meant to
// read calmer than the duration arc.
const PULSE = {
  inner: 19.5,
  outer: 22.5,
  centerR: 21.0,
  neonSigma: 1.0,
  neonBase: 100,
  neonPeak: 155,
  capRadius: (22.5 - 19.5) / 2, // 1.5
};

// --- C. Wave v3 (real ripple, windowed to kill the square artifact) -------
const WAVE = {
  center: 26,            // r_c of the asymmetric ring
  outerSigma: 1.7,       // steep OUTER front (r >= center)
  innerSigma: 4.6,       // soft INNER tail (r < center)
  secondaryCenter: 18.5, // faint secondary inner trailing ripple
  secondarySigma: 2.2,
  secondaryWeight: 0.33,
  windowStart: 31,       // alpha is EXACTLY 0 for every r >= windowStart
  windowWidth: 1.5,
};

// --- A. Frame band v4 ("schicker Rahmen", real metal bevel) ---------------
// Opaque band bounds unchanged (corner-cover contract): r in [inner, outer].
// Radial zone boundaries are unchanged from v3; only the color source
// collapsed to one fixed set (FRAME_COLORS below) now that shadow is the
// only look (Session 76 - see header comment).
const FRAME = {
  inner: 19.0, outer: 30.5,
  rimStart: 19.0,      // [rimStart, grooveStart): inner catch-light rim
  grooveStart: 19.9,   // [grooveStart, bodyInner): inner shadow groove
  bodyInner: 20.9,     // [bodyInner, outerHiStart): body (radial shade + top-light)
  outerHiStart: 28.6,  // [outerHiStart, outlineStart): outer highlight gradient
  outlineStart: 30.1,  // [outlineStart, outer]: near-black outline
  topLightMax: 22,     // top-light bias amplitude added at 12 o'clock (0 at the bottom)
};

// Fixed RGB stops for FRAME's radial zones - the shadow profile (formerly
// reachable only via `--variant shadow`), now the ONLY frame-band look
// (Session 76: "the grey/gold frame reads as an unwanted border" -> user
// picked shadow permanently). Minimal/unobtrusive: no bright outer
// highlight, everything very dark - reads as a dark rim shadow rather than
// a visible frame.
const FRAME_COLORS = {
  rimColor: [48, 46, 42],
  grooveColor: [10, 9, 8],
  bodyInnerColor: [16, 15, 13],
  bodyOuterColor: [16, 15, 13],
  outerHiInnerColor: [16, 15, 13],
  outerHiOuterColor: [10, 9, 8],
  outlineColor: [8, 8, 8],
};

const ARC_RGBA = [255, 255, 255, 255]; // white, runtime-tinted via SetVertexColor

function lerp3(a, b, t) {
  return [Math.round(lerp(a[0], b[0], t)), Math.round(lerp(a[1], b[1], t)), Math.round(lerp(a[2], b[2], t))];
}

// Continuous frame color formula (r, dx, dy in cell-space units, center at
// origin), returns [r,g,b] 0..255. Exported separately from the discrete
// per-pixel shader so it can be probed at exact (dx,dy) offsets that don't
// land on pixel centers (see shadeFrame below and the rev verification).
function frameColorAt(r, dx, dy) {
  const v = FRAME_COLORS;
  const rr = r < 1e-6 ? 1e-6 : r;
  const bias = Math.round(FRAME.topLightMax * Math.max(0, -dy / rr));
  const withBias = (c) => [clamp(c[0] + bias, 0, 255), clamp(c[1] + bias, 0, 255), clamp(c[2] + bias, 0, 255)];
  if (r >= FRAME.outlineStart) {
    return v.outlineColor.slice(); // fixed near-black outline, not lit
  }
  if (r >= FRAME.outerHiStart) {
    const t = clamp((r - FRAME.outerHiStart) / (FRAME.outlineStart - FRAME.outerHiStart), 0, 1);
    return withBias(lerp3(v.outerHiInnerColor, v.outerHiOuterColor, t));
  }
  if (r >= FRAME.bodyInner) {
    const t = clamp((r - FRAME.bodyInner) / (FRAME.outerHiStart - FRAME.bodyInner), 0, 1);
    return withBias(lerp3(v.bodyInnerColor, v.bodyOuterColor, t));
  }
  if (r >= FRAME.grooveStart) {
    return withBias(v.grooveColor);
  }
  // r in [rimStart, grooveStart), or below rimStart (out-of-band fallback -
  // alpha is 0 there anyway via the coverage test, this just avoids an
  // undefined color for partially-covered edge pixels near r ~ inner).
  return withBias(v.rimColor);
}

// Continuous wave amplitude formula (0..1), probed directly by rev
// verification at exact r values (r=31, r=32 must both yield 0).
function waveAmplitudeAtR(r) {
  let primary;
  if (r >= WAVE.center) {
    const t = (r - WAVE.center) / WAVE.outerSigma;
    primary = Math.exp(-(t * t));
  } else {
    const t = (WAVE.center - r) / WAVE.innerSigma;
    primary = Math.exp(-(t * t));
  }
  const t2 = (r - WAVE.secondaryCenter) / WAVE.secondarySigma;
  const secondary = WAVE.secondaryWeight * Math.exp(-(t2 * t2));
  const w = clamp((WAVE.windowStart - r) / WAVE.windowWidth, 0, 1);
  const a = (primary + secondary) * w;
  return clamp(a, 0, 1);
}

// Shared engine for both the duration arc (cfg=ARC, cometDeg=ARC.cometDeg)
// and the pulse arc (cfg=PULSE, cometDeg=0 - no hot leading tip, meant to
// read calmer): angular fill 0..f clockwise from 12 o'clock, rounded caps at
// both ends, radial gaussian neon falloff off cfg.centerR. Supersampled so
// the shape boundary (radial edges, cap discs, leading/trailing cut) gets a
// smooth coverage-blended alpha instead of a hard edge.
function shadeArcGeneric(cfg, cometDeg, f, px, py) {
  const c = CELL / 2;
  let sumAlpha = 0;
  const startDx = 0, startDy = -cfg.centerR; // fixed cap center at angle 0 (12 o'clock)
  let endDx = 0, endDy = -cfg.centerR;
  if (f > 0) {
    const endAngle = f * 2 * Math.PI;
    endDx = cfg.centerR * Math.sin(endAngle);
    endDy = -cfg.centerR * Math.cos(endAngle);
  }
  for (let sy = 0; sy < SS; sy++) {
    for (let sx = 0; sx < SS; sx++) {
      const dx = px + (sx + 0.5) / SS - c;
      const dy = py + (sy + 0.5) / SS - c;
      const r = Math.sqrt(dx * dx + dy * dy);
      const af = angFrac(dx, dy);
      let inside = false;
      if (f > 0) {
        if (r >= cfg.inner && r <= cfg.outer && af <= f) inside = true;
        if (!inside) {
          const dStart = Math.hypot(dx - startDx, dy - startDy);
          const dEnd = Math.hypot(dx - endDx, dy - endDy);
          if (dStart <= cfg.capRadius || dEnd <= cfg.capRadius) inside = true;
        }
      }
      if (!inside) continue;
      const t = (r - cfg.centerR) / cfg.neonSigma;
      let a = cfg.neonBase + cfg.neonPeak * Math.exp(-(t * t));
      if (cometDeg && af <= f) {
        const deltaDeg = (f - af) * 360;
        if (deltaDeg >= 0 && deltaDeg <= cometDeg) {
          const t2 = 1 - deltaDeg / cometDeg; // 0 at cometDeg away, 1 at the tip
          a = a + (255 - a) * t2;
        }
      }
      sumAlpha += clamp(a, 0, 255);
    }
  }
  const avgAlpha = sumAlpha / (SS * SS);
  if (avgAlpha <= 0) return [0, 0, 0, 0];
  return [ARC_RGBA[0], ARC_RGBA[1], ARC_RGBA[2], Math.round(avgAlpha)];
}

// Cells 0..61 of ring_round.tga: duration arc, comet tip enabled.
function shadeArc(f, px, py) {
  return shadeArcGeneric(ARC, ARC.cometDeg, f, px, py);
}

// Cells 0..61 of ring_pulsearc.tga: pulse-countdown arc, no comet tip.
function shadePulseArc(f, px, py) {
  return shadeArcGeneric(PULSE, 0, f, px, py);
}

// Cell 62: analytic radial profile (waveAmplitudeAtR), sampled once at the
// pixel center - a smooth continuous, hard-windowed function needs no
// coverage supersampling.
function shadeWave(px, py) {
  const c = CELL / 2;
  const dx = px + 0.5 - c;
  const dy = py + 0.5 - c;
  const r = Math.sqrt(dx * dx + dy * dy);
  const a = waveAmplitudeAtR(r);
  return [255, 255, 255, Math.round(255 * a)];
}

// Cell 63: opaque bevel frame band (shadow profile - the only look, see
// header comment). Alpha comes from supersampled coverage of the full band
// [FRAME.inner, FRAME.outer] (anti-aliases the true transparent/opaque
// edges); the color is picked from frameColorAt at the pixel center
// (continuous radial profile + top-light bias, no AA needed there since
// it's a smooth gradient, not a hard edge).
function shadeFrame(px, py) {
  const c = CELL / 2;
  let inside = 0;
  for (let sy = 0; sy < SS; sy++) {
    for (let sx = 0; sx < SS; sx++) {
      const dx = px + (sx + 0.5) / SS - c;
      const dy = py + (sy + 0.5) / SS - c;
      const r = Math.sqrt(dx * dx + dy * dy);
      if (r <= FRAME.outer && r >= FRAME.inner) {
        inside++;
      }
    }
  }
  if (inside <= 0) return [0, 0, 0, 0];
  const alpha = Math.round(255 * (inside / (SS * SS)));
  const cdx = px + 0.5 - c;
  const cdy = py + 0.5 - c;
  const r = Math.sqrt(cdx * cdx + cdy * cdy);
  const [rr, gg, bb] = frameColorAt(r, cdx, cdy);
  return [rr, gg, bb, alpha];
}

function shadeRing(cellIndex, px, py) {
  if (cellIndex < ARC_FRAMES) {
    return shadeArc(cellIndex / (ARC_FRAMES - 1), px, py);
  } else if (cellIndex === WAVE_CELL) {
    return shadeWave(px, py);
  } else if (cellIndex === FRAME_CELL) {
    return shadeFrame(px, py);
  }
  return [0, 0, 0, 0]; // defensive: the 64-cell grid has no spare cells left
}

// ===========================================================================
// D. ring_fx.tga - 256x256, 2x2 grid of 128x128 cells (center 64, max r 64)
// ===========================================================================
const FX_CELL = 128;
const FX_GRID_COLS = 2;
const FX_GRID_ROWS = 2;
const FX_SIZE = FX_CELL * FX_GRID_COLS; // 256
const FX_CELL_GLOW = 0;
const FX_CELL_HOVER = 1;
const FX_CELL_PUSHED = 2;
const FX_CELL_FLASH = 3;

// Glow (cell 0) is an ANNULAR halo hugging the ring from OUTSIDE (iteration
// 2): in-game the glow sits on the BACKGROUND layer, so only the part
// outside the opaque band (band outer = 22.9px at 48px draw) is visible.
// Drawn at 64px screen size the peak lands at 50/64*32 = 25px, ~2px outside
// the band edge. The inner hole (< innerHoleR) keeps the sheet clean - that
// region is invisible under the icon/band anyway.
const FX_GLOW = {
  centerR: 50, sigma: 7, peak: 190,
  windowStart: 59, windowEnd: 62, // linear outer window 1 -> 0 over [59, 62]
  innerHoleR: 40,                 // alpha exactly 0 for every r <= innerHoleR
  innerRampWidth: 6,              // smoothstep 0 -> 1 over [innerHoleR, innerHoleR + 6]
};
const FX_HOVER = { centerR: 58, sigma: 1.6, peak: 150, windowStart: 63, windowWidth: 3 };
const FX_PUSHED = { flatR: 40, falloffR: 46, peak: 90 };
const FX_FLASH = { sigma: 24, peak: 235, windowStart: 52, windowWidth: 3 };

function fxGlowAlphaAtR(r) {
  const wOut = clamp((FX_GLOW.windowEnd - r) / (FX_GLOW.windowEnd - FX_GLOW.windowStart), 0, 1);
  const wIn = smoothstep((r - FX_GLOW.innerHoleR) / FX_GLOW.innerRampWidth);
  const t = (r - FX_GLOW.centerR) / FX_GLOW.sigma;
  return clamp(FX_GLOW.peak * Math.exp(-(t * t)) * wOut * wIn, 0, 255);
}
function fxHoverAlphaAtR(r) {
  const w = clamp((FX_HOVER.windowStart - r) / FX_HOVER.windowWidth, 0, 1);
  const t = (r - FX_HOVER.centerR) / FX_HOVER.sigma;
  return clamp(FX_HOVER.peak * Math.exp(-(t * t)) * w, 0, 255);
}
function fxPushedAlphaAtR(r) {
  if (r <= FX_PUSHED.flatR) return FX_PUSHED.peak;
  if (r >= FX_PUSHED.falloffR) return 0;
  const t = (r - FX_PUSHED.flatR) / (FX_PUSHED.falloffR - FX_PUSHED.flatR);
  return FX_PUSHED.peak * (1 - smoothstep(t));
}
function fxFlashAlphaAtR(r) {
  const w = clamp((FX_FLASH.windowStart - r) / FX_FLASH.windowWidth, 0, 1);
  return clamp(FX_FLASH.peak * Math.exp(-Math.pow(r / FX_FLASH.sigma, 2)) * w, 0, 255);
}

function shadeFx(cellIndex, px, py) {
  const c = FX_CELL / 2;
  const dx = px + 0.5 - c, dy = py + 0.5 - c;
  const r = Math.sqrt(dx * dx + dy * dy);
  let a;
  switch (cellIndex) {
    case FX_CELL_GLOW: a = fxGlowAlphaAtR(r); break;
    case FX_CELL_HOVER: a = fxHoverAlphaAtR(r); break;
    case FX_CELL_PUSHED: a = fxPushedAlphaAtR(r); break;
    case FX_CELL_FLASH: a = fxFlashAlphaAtR(r); break;
    default: a = 0;
  }
  return [255, 255, 255, Math.round(a)];
}

// ===========================================================================
// E. ring_pulsearc.tga - 512x512, 8x8 grid of 64x64 cells (same geometry as
// ring_round.tga so runtime cell-index math can be shared). Cells 0..61 =
// pulse-countdown arc frames (shadePulseArc); cells 62/63 unused/spare.
// ===========================================================================
const PULSE_CELL = CELL;         // 64
const PULSE_GRID = GRID;         // 8
const PULSE_SIZE = SIZE;         // 512
const PULSE_ARC_FRAMES = 62;     // cells 0..61

function shadePulseSheet(cellIndex, px, py) {
  if (cellIndex < PULSE_ARC_FRAMES) {
    return shadePulseArc(cellIndex / (PULSE_ARC_FRAMES - 1), px, py);
  }
  return [0, 0, 0, 0]; // cells 62/63: spare, fully transparent
}

// ===========================================================================
// Generic sheet renderer + TGA writer (shared, format unchanged from v2)
// ===========================================================================
function renderSheet(size, cellSize, cols, rows, cellShader) {
  const img = Buffer.alloc(size * size * 4);
  const totalCells = cols * rows;
  for (let cell = 0; cell < totalCells; cell++) {
    const col = cell % cols;
    const row = Math.floor(cell / cols);
    for (let py = 0; py < cellSize; py++) {
      for (let px = 0; px < cellSize; px++) {
        const rgba = cellShader(cell, px, py);
        const x = col * cellSize + px;
        const y = row * cellSize + py;
        const o = (y * size + x) * 4;
        img[o] = rgba[2]; img[o + 1] = rgba[1]; img[o + 2] = rgba[0]; img[o + 3] = rgba[3]; // BGRA
      }
    }
  }
  return img;
}

// TGA: 18-byte header, type 2 (uncompressed truecolor), 32bpp, descriptor
// 0x08 = bottom-up rows + 8 alpha bits (pfUI-proven format). img is a
// top-down RGBA buffer (row 0 = top image row); this flips it to bottom-up
// on write, exactly as v1/v2 did.
function writeTGA(filePath, size, img) {
  const header = Buffer.alloc(18);
  header[2] = 2;
  header[12] = size & 255; header[13] = size >> 8;
  header[14] = size & 255; header[15] = size >> 8;
  header[16] = 32;
  header[17] = 0x08;
  const rows = [];
  for (let y = size - 1; y >= 0; y--) {
    rows.push(img.subarray(y * size * 4, (y + 1) * size * 4));
  }
  const out = Buffer.concat([header, ...rows]);
  fs.writeFileSync(filePath, out);
  return out.length;
}

// which: undefined/"all" = ring+fx+pulsearc sheets, "ring" = ring_round.tga
// only, "fx" = ring_fx.tga only, "pulsearc" = ring_pulsearc.tga only. CLI:
// node tools/gen_ring_textures.js [ring|fx|pulsearc|all].
// Selective regeneration keeps the untouched sheet's file byte-identical
// (no pointless mtime churn when only one sheet's recipe changed).
function generate(which) {
  const doRing = which === undefined || which === "all" || which === "ring";
  const doFx = which === undefined || which === "all" || which === "fx";
  const doPulse = which === undefined || which === "all" || which === "pulsearc";
  if (!doRing && !doFx && !doPulse) throw new Error("gen_ring_textures: unknown target '" + which + "' (use ring|fx|pulsearc|all)");
  const dir = path.join(__dirname, "..", "textures");
  if (!fs.existsSync(dir)) fs.mkdirSync(dir);

  if (doRing) {
    const ringImg = renderSheet(SIZE, CELL, GRID, GRID, shadeRing);
    const ringFile = path.join(dir, "ring_round.tga");
    const ringBytes = writeTGA(ringFile, SIZE, ringImg);
    console.log("wrote " + ringFile + " (" + ringBytes + " bytes)");
  }

  if (doFx) {
    const fxImg = renderSheet(FX_SIZE, FX_CELL, FX_GRID_COLS, FX_GRID_ROWS, shadeFx);
    const fxFile = path.join(dir, "ring_fx.tga");
    const fxBytes = writeTGA(fxFile, FX_SIZE, fxImg);
    console.log("wrote " + fxFile + " (" + fxBytes + " bytes)");
  }

  if (doPulse) {
    const pulseImg = renderSheet(PULSE_SIZE, PULSE_CELL, PULSE_GRID, PULSE_GRID, shadePulseSheet);
    const pulseFile = path.join(dir, "ring_pulsearc.tga");
    const pulseBytes = writeTGA(pulseFile, PULSE_SIZE, pulseImg);
    console.log("wrote " + pulseFile + " (" + pulseBytes + " bytes)");
  }
}

// Parses `[ring|fx|pulsearc|all]` from argv (already sliced past
// `node script.js`).
function parseArgs(argv) {
  let which;
  for (let i = 0; i < argv.length; i++) {
    if (which === undefined) which = argv[i];
  }
  return { which };
}

module.exports = {
  CELL, GRID, SIZE, ARC_FRAMES, WAVE_CELL, FRAME_CELL, SS,
  ARC, PULSE, WAVE, FRAME, FRAME_COLORS,
  FX_CELL, FX_GRID_COLS, FX_GRID_ROWS, FX_SIZE,
  FX_CELL_GLOW, FX_CELL_HOVER, FX_CELL_PUSHED, FX_CELL_FLASH,
  FX_GLOW, FX_HOVER, FX_PUSHED, FX_FLASH,
  PULSE_CELL, PULSE_GRID, PULSE_SIZE, PULSE_ARC_FRAMES,
  angFrac, clamp, lerp, lerp3,
  frameColorAt, waveAmplitudeAtR,
  fxGlowAlphaAtR, fxHoverAlphaAtR, fxPushedAlphaAtR, fxFlashAlphaAtR,
  shadeArcGeneric, shadeArc, shadePulseArc, shadeWave, shadeFrame, shadeFx,
  shadePulseSheet, shadeRing,
  renderSheet, writeTGA, generate, parseArgs,
};

if (require.main === module) {
  const { which } = parseArgs(process.argv.slice(2));
  generate(which);
}
