// TotemBar - tools/gen_ui_textures.js
// Rev 4 UI-chrome texture pass (.superpowers/sdd/rev4-ui-brief.md): panel
// border (edgeFile strip), panel background (tileable), and a small UI sheet
// (shadow plate / emblem / divider). Zero dependencies. Copies the TGA-writer
// pattern from tools/gen_ring_textures.js (read-only reference, NOT modified
// or required here - same reimplementation approach tools/gen_icons.js uses).
// Run: node tools/gen_ui_textures.js
"use strict";

const fs = require("fs");
const path = require("path");

// ---------------------------------------------------------------------
// Shared small-number helpers
// ---------------------------------------------------------------------
function clamp(v, lo, hi) { return v < lo ? lo : (v > hi ? hi : v); }
function lerp(a, b, t) { return a + (b - a) * t; }
function sdfCoverage(d, falloff) { return clamp(0.5 - d / falloff, 0, 1); }

function sdBoxAt(dx, dy, cx, cy, hx, hy) {
  const px = Math.abs(dx - cx) - hx;
  const py = Math.abs(dy - cy) - hy;
  const ox = Math.max(px, 0), oy = Math.max(py, 0);
  return Math.hypot(ox, oy) + Math.min(Math.max(px, py), 0);
}
function sdRoundedBoxAt(dx, dy, cx, cy, hx, hy, r) {
  return sdBoxAt(dx, dy, cx, cy, hx - r, hy - r) - r;
}
// Cheap ellipse pseudo-SDF (scale-normalized radial distance * min axis) -
// exact on the boundary, approximate off it (same helper as tools/gen_icons.js).
function sdEllipseApprox(dx, dy, cx, cy, rx, ry) {
  const nx = (dx - cx) / rx, ny = (dy - cy) / ry;
  const n = Math.hypot(nx, ny);
  const minAxis = Math.min(rx, ry);
  return n < 1e-9 ? -minAxis : (n - 1) * minAxis;
}
// Straight-alpha "A over B" compositing (same recipe as tools/gen_icons.js).
function overStraight(baseRGBA, topRGB, topA01) {
  const a = clamp(topA01, 0, 1);
  const baseA01 = baseRGBA[3] / 255;
  const outA01 = a + baseA01 * (1 - a);
  if (outA01 <= 0) return [0, 0, 0, 0];
  const outR = (topRGB[0] * a + baseRGBA[0] * baseA01 * (1 - a)) / outA01;
  const outG = (topRGB[1] * a + baseRGBA[1] * baseA01 * (1 - a)) / outA01;
  const outB = (topRGB[2] * a + baseRGBA[2] * baseA01 * (1 - a)) / outA01;
  return [outR, outG, outB, outA01 * 255];
}
// Angle in degrees, 0 at straight up (12 o'clock), increasing clockwise.
function angleFromTopDeg(dx, dy) {
  let a = Math.atan2(dx, -dy) * 180 / Math.PI;
  if (a < 0) a += 360;
  return a;
}

// ===========================================================================
// Generic sheet renderer + TGA writer (same format/pattern as
// tools/gen_ring_textures.js: 18-byte header, type 2, 32bpp, descriptor 0x08
// bottom-up BGRA - reimplemented locally, that file is untouched).
// ===========================================================================
function renderSheet(w, h, cellSize, cols, rows, cellShader) {
  const img = Buffer.alloc(w * h * 4);
  const totalCells = cols * rows;
  for (let cell = 0; cell < totalCells; cell++) {
    const col = cell % cols;
    const row = Math.floor(cell / cols);
    for (let py = 0; py < cellSize; py++) {
      for (let px = 0; px < cellSize; px++) {
        const rgba = cellShader(cell, px, py);
        const x = col * cellSize + px;
        const y = row * cellSize + py;
        const o = (y * w + x) * 4;
        img[o] = rgba[2]; img[o + 1] = rgba[1]; img[o + 2] = rgba[0]; img[o + 3] = rgba[3]; // BGRA
      }
    }
  }
  return img;
}

function writeTGA(filePath, w, h, img) {
  const header = Buffer.alloc(18);
  header[2] = 2; // uncompressed truecolor
  header[12] = w & 255; header[13] = w >> 8;
  header[14] = h & 255; header[15] = h >> 8;
  header[16] = 32;
  header[17] = 0x08; // bottom-up rows + 8 alpha bits
  const rows = [];
  for (let y = h - 1; y >= 0; y--) {
    rows.push(img.subarray(y * w * 4, (y + 1) * w * 4));
  }
  const out = Buffer.concat([header, ...rows]);
  fs.writeFileSync(filePath, out);
  return out.length;
}

// ===========================================================================
// A. textures/panel_border.tga - 128x16 edgeFile strip (edgeSize 16)
//
// 8 segments of 16x16, horizontal order: [L][R][T][B][TL][TR][BL][BR].
//
// CRITICAL orientation facts (KG-verified against C:\dev\Parsec's in-game-
// proven window-border.tga, whose L/T segments are byte-identical and whose
// R/B segments are byte-identical - confirming "T stored same as L, B stored
// same as R" is the real client convention, not a guess):
//   - L/R are vertical strips, no rotation; L's outer side is local x=0, R's
//     outer side is local x=15.
//   - T/B are ALSO stored as vertical-strip patterns (function of x only,
//     constant down each column) - the client rotates them CW at render
//     time. T reuses L's x-pattern verbatim, B reuses R's x-pattern verbatim.
//   - Corners are stored unrotated, rounded via a radial profile around a
//     pivot on the cell's INNER corner (16px in from both outer sides, i.e.
//     cell-local (16,16) when the outer corner is (0,0)), quarter-arc radius
//     16: d = 16 - distance-to-pivot through the SAME 0..16 profile as the
//     edges; dist > 16 is fully transparent (rounded outer corner, radius 16
//     - standard rounded-rect look). [Rev 4 iteration 2: the brief's original
//     pivot-12/radius-12 geometry could never reach the edges' fade zone -
//     coordinator-corrected to pivot 16/radius 16.]
// ===========================================================================
const BORDER_CELL = 16;
const BORDER_SEGMENTS = 8;
const BORDER_W = BORDER_CELL * BORDER_SEGMENTS; // 128
const BORDER_H = BORDER_CELL; // 16
const BORDER_SS = 3; // "3x supersampling" per brief

// Radial profile across the 16px border thickness, d: 0 (outer) .. 16 (inner,
// fully faded). All-grey (monochrome bevel), matching the ring band's own
// frameGreyAt style in tools/gen_ring_textures.js.
const PROFILE = {
  outlineEnd: 0.9, outlineGrey: 14,
  highlightEnd: 3.2, highlightStart: 115, highlightStop: 62,
  bodyEnd: 11, bodyStart: 46, bodyStop: 38,
  shadowEnd: 12.5, shadowGrey: 24,
  catchEnd: 14, catchGrey: 78,
  fadeEnd: 16,
};
function profileAt(d) {
  if (d < 0) d = 0;
  if (d < PROFILE.outlineEnd) return [PROFILE.outlineGrey, 255];
  if (d < PROFILE.highlightEnd) {
    const t = (d - PROFILE.outlineEnd) / (PROFILE.highlightEnd - PROFILE.outlineEnd);
    return [Math.round(lerp(PROFILE.highlightStart, PROFILE.highlightStop, t)), 255];
  }
  if (d < PROFILE.bodyEnd) {
    const t = (d - PROFILE.highlightEnd) / (PROFILE.bodyEnd - PROFILE.highlightEnd);
    return [Math.round(lerp(PROFILE.bodyStart, PROFILE.bodyStop, t)), 255];
  }
  // Inclusive shadowEnd (<=, unlike the other zone checks): the 3x
  // supersample grid puts one edge-cell subsample at EXACTLY d = 12.5
  // (x + 1/2 at column x = 12), while the corner's radial d at the matching
  // boundary location is infinitesimally smaller (~0.03 less). An exclusive
  // boundary would classify those two into different zones (catch-light 78
  // vs shadow 24) and shift that single pixel's average by ~18 grey levels
  // across the corner/edge seam; the inclusive tie-break keeps straight and
  // radial sampling in exact agreement. No other zone boundary (0.9 / 3.2 /
  // 11 / 14) coincides with a subsample position, so only this one needs it.
  if (d <= PROFILE.shadowEnd) return [PROFILE.shadowGrey, 255];
  if (d < PROFILE.catchEnd) return [PROFILE.catchGrey, 255];
  if (d <= PROFILE.fadeEnd) {
    const t = (d - PROFILE.catchEnd) / (PROFILE.fadeEnd - PROFILE.catchEnd);
    return [PROFILE.catchGrey, Math.round(lerp(255, 0, t))];
  }
  return [PROFILE.catchGrey, 0];
}

// Straight edge cells: pattern is a pure function of local x (continuous,
// 0..16 spans the full profile), constant down every column. kind "LT" =
// L/T's own pattern (outer at x=0); kind "RB" = R/B's pattern (outer at
// x=15, i.e. mirrored: d = 16 - x).
function sampleEdgeCellPixel(kind, px) {
  let sumGreyPremult = 0, sumAlpha = 0;
  for (let i = 0; i < BORDER_SS; i++) {
    const xc = px + (i + 0.5) / BORDER_SS;
    const d = kind === "LT" ? xc : (16 - xc);
    const [grey, alpha] = profileAt(d);
    sumGreyPremult += grey * (alpha / 255);
    sumAlpha += alpha;
  }
  const avgAlpha = sumAlpha / BORDER_SS;
  if (avgAlpha <= 0) return [0, 0, 0, 0];
  const grey = Math.round(clamp((sumGreyPremult / BORDER_SS) * 255 / avgAlpha, 0, 255));
  return [grey, grey, grey, Math.round(clamp(avgAlpha, 0, 255))];
}

// Rounded corner cells: pivot on the cell's INNER corner (16px in from both
// outer sides, continuous cell coords - e.g. (16,16) for TL whose outer
// corner is (0,0)), quarter-arc radius 16. d = CORNER_RADIUS - distance-to-
// pivot, fed into EXACTLY the same profileAt() the straight edges use
// (outline, highlight, body, inner shadow, catch-light, alpha fade 14..16);
// dist > 16 is fully transparent (rounded outer corner, radius 16). At the
// cell boundary the radial d deviates from the straight edge's linear d by
// at most ~0.4px at the innermost (already heavily faded) pixel - continuity
// in the solid region is asserted by seamCheck().
const CORNER_RADIUS = 16;
function sampleCornerCellPixel(pivotX, pivotY, px, py) {
  let sumGreyPremult = 0, sumAlpha = 0;
  for (let j = 0; j < BORDER_SS; j++) {
    for (let i = 0; i < BORDER_SS; i++) {
      const xc = px + (i + 0.5) / BORDER_SS;
      const yc = py + (j + 0.5) / BORDER_SS;
      const dist = Math.hypot(xc - pivotX, yc - pivotY);
      let grey = 0, alpha = 0;
      if (dist <= CORNER_RADIUS) {
        const d = CORNER_RADIUS - dist;
        [grey, alpha] = profileAt(d);
      }
      sumGreyPremult += grey * (alpha / 255);
      sumAlpha += alpha;
    }
  }
  const n = BORDER_SS * BORDER_SS;
  const avgAlpha = sumAlpha / n;
  if (avgAlpha <= 0) return [0, 0, 0, 0];
  const grey = Math.round(clamp((sumGreyPremult / n) * 255 / avgAlpha, 0, 255));
  return [grey, grey, grey, Math.round(clamp(avgAlpha, 0, 255))];
}

// Pivots: on each corner cell's INNER corner, 16px in from both outer sides,
// in continuous cell coordinates (image top-down coords - the writer flips
// rows to bottom-up on write, same as every other sheet generator in this repo).
const CORNER_PIVOTS = {
  TL: [16, 16], // outer corner at (0,0) -> pivot at the cell's bottom-right corner point
  TR: [0, 16],  // outer corner at (16,0) -> pivot at the cell's bottom-left corner point
  BL: [16, 0],  // outer corner at (0,16) -> pivot at the cell's top-right corner point
  BR: [0, 0],   // outer corner at (16,16) -> pivot at the cell's top-left corner point
};

function shadeBorderCell(cellIndex, px, py) {
  switch (cellIndex) {
    case 0: return sampleEdgeCellPixel("LT", px); // L
    case 1: return sampleEdgeCellPixel("RB", px); // R
    case 2: return sampleEdgeCellPixel("LT", px); // T (same x-pattern as L; client rotates CW at render)
    case 3: return sampleEdgeCellPixel("RB", px); // B (same x-pattern as R; client rotates CW at render)
    case 4: return sampleCornerCellPixel(CORNER_PIVOTS.TL[0], CORNER_PIVOTS.TL[1], px, py);
    case 5: return sampleCornerCellPixel(CORNER_PIVOTS.TR[0], CORNER_PIVOTS.TR[1], px, py);
    case 6: return sampleCornerCellPixel(CORNER_PIVOTS.BL[0], CORNER_PIVOTS.BL[1], px, py);
    case 7: return sampleCornerCellPixel(CORNER_PIVOTS.BR[0], CORNER_PIVOTS.BR[1], px, py);
    default: return [0, 0, 0, 0];
  }
}

// ===========================================================================
// B. textures/panel_bg.tga - 128x128 tileable background
// Near-flat dark base rgb(19,17,14), fully opaque, with deterministic
// per-pixel noise (+/-3 on each channel, hash of (x%128,y%128) - image size
// equals the hash period so it tiles perfectly edge-to-edge with no seam:
// noise has no spatial gradient, so adjacent tile copies just abut two
// independently-hashed columns, which is seamless for pure per-pixel noise).
// ===========================================================================
const BG_SIZE = 128;
const BG_BASE = [19, 17, 14];
function hashNoise(x, y) {
  let h = (x * 374761393 + y * 668265263) | 0;
  h = (h ^ (h >>> 13)) * 1274126177 | 0;
  h = (h ^ (h >>> 16)) >>> 0;
  return (((h % 7) + 7) % 7) - 3; // -3..3, normalized-positive modulo first
}
function shadeBg(px, py) {
  const n = hashNoise(px % BG_SIZE, py % BG_SIZE);
  return [clamp(BG_BASE[0] + n, 0, 255), clamp(BG_BASE[1] + n, 0, 255), clamp(BG_BASE[2] + n, 0, 255), 255];
}

// ===========================================================================
// C. textures/ui.tga - 256x256, 2x2 grid of 128px cells
// ===========================================================================
const UI_CELL = 128;
const UI_GRID = 2;
const UI_SIZE = UI_CELL * UI_GRID; // 256
const UI_SS = 3;
const UI_FALLOFF = 1.5;
const CELL_SHADOW = 0, CELL_EMBLEM = 1, CELL_DIVIDER = 2, CELL_SPARE = 3;

// --- Cell 1: shadow plate -------------------------------------------------
const SHADOW = { sigma: 34, peak: 150, windowStart: 55, windowEnd: 60 };
function shadeShadow(dx, dy) {
  const r = Math.hypot(dx, dy);
  if (r >= SHADOW.windowEnd) return [0, 0, 0, 0];
  let a = SHADOW.peak * Math.exp(-Math.pow(r / SHADOW.sigma, 2));
  const w = clamp((SHADOW.windowEnd - r) / (SHADOW.windowEnd - SHADOW.windowStart), 0, 1);
  a *= w;
  return [0, 0, 0, Math.round(clamp(a, 0, 255))];
}

// --- Cell 2: emblem (totem silhouette + elemental dot arc) ----------------
// Same stacked-rounded-segments-plus-dome silhouette style as tools/gen_icons.js's
// MINIMAP glyph (independently reimplemented here at this cell's own scale
// target, height ~76, per the brief - not imported/shared with that file).
const EMBLEM_SEGS_RAW = [ { w: 24, h: 14 }, { w: 31, h: 17 }, { w: 40, h: 19 } ]; // top,mid,bottom
const EMBLEM_GAP = 3.5;
const EMBLEM_DOME_H = 19;
const EMBLEM_CORNER_R = 6;
const EMBLEM_OUTLINE_W = 1;
const EMBLEM_TOTAL_H = EMBLEM_SEGS_RAW[0].h + EMBLEM_GAP + EMBLEM_SEGS_RAW[1].h + EMBLEM_GAP + EMBLEM_SEGS_RAW[2].h + EMBLEM_DOME_H; // 76
const EMBLEM_TOP_Y = -EMBLEM_TOTAL_H / 2; // -38
const EMBLEM_S1_TOP = EMBLEM_TOP_Y + EMBLEM_DOME_H;
const EMBLEM_S1_BOTTOM = EMBLEM_S1_TOP + EMBLEM_SEGS_RAW[0].h;
const EMBLEM_S2_TOP = EMBLEM_S1_BOTTOM + EMBLEM_GAP;
const EMBLEM_S2_BOTTOM = EMBLEM_S2_TOP + EMBLEM_SEGS_RAW[1].h;
const EMBLEM_S3_TOP = EMBLEM_S2_BOTTOM + EMBLEM_GAP;
const EMBLEM_S3_BOTTOM = EMBLEM_S3_TOP + EMBLEM_SEGS_RAW[2].h; // = EMBLEM_TOTAL_H/2 (38)
const EMBLEM_SEGS = [
  { cy: (EMBLEM_S1_TOP + EMBLEM_S1_BOTTOM) / 2, hw: EMBLEM_SEGS_RAW[0].w / 2, hh: EMBLEM_SEGS_RAW[0].h / 2 },
  { cy: (EMBLEM_S2_TOP + EMBLEM_S2_BOTTOM) / 2, hw: EMBLEM_SEGS_RAW[1].w / 2, hh: EMBLEM_SEGS_RAW[1].h / 2 },
  { cy: (EMBLEM_S3_TOP + EMBLEM_S3_BOTTOM) / 2, hw: EMBLEM_SEGS_RAW[2].w / 2, hh: EMBLEM_SEGS_RAW[2].h / 2 },
];
const EMBLEM_DOME = { cy: EMBLEM_S1_TOP, rx: EMBLEM_SEGS_RAW[0].w / 2, ry: EMBLEM_DOME_H };
const EMBLEM_TOP_COLOR = [230, 190, 110];
const EMBLEM_BOT_COLOR = [140, 95, 45];
const EMBLEM_OUTLINE_COLOR = [45, 30, 16];

function emblemShapeD(dx, dy) {
  let d = Infinity;
  for (const s of EMBLEM_SEGS) {
    const sd = sdRoundedBoxAt(dx, dy, 0, s.cy, s.hw, s.hh, EMBLEM_CORNER_R);
    if (sd < d) d = sd;
  }
  if (dy <= EMBLEM_DOME.cy) {
    const ed = sdEllipseApprox(dx, dy, 0, EMBLEM_DOME.cy, EMBLEM_DOME.rx, EMBLEM_DOME.ry);
    if (ed < d) d = ed;
  }
  return d;
}
function emblemColorAt(dy) {
  const t = clamp((dy - EMBLEM_TOP_Y) / EMBLEM_TOTAL_H, 0, 1);
  return [lerp(EMBLEM_TOP_COLOR[0], EMBLEM_BOT_COLOR[0], t), lerp(EMBLEM_TOP_COLOR[1], EMBLEM_BOT_COLOR[1], t), lerp(EMBLEM_TOP_COLOR[2], EMBLEM_BOT_COLOR[2], t)];
}

// Arc of four dots at 10/11/1/2 o'clock, radius 48 from the cell center,
// r=7, colored Fire/Earth/Water/Air (brief's listed order, mapped 1:1 to the
// listed clock positions), with a tiny white specular highlight each.
const ELEMENT_DOT_R = 7;
const ELEMENT_DOT_RADIUS_FROM_CENTER = 48;
const ELEMENT_DOT_SPEC_OFFSET = [-2, -2];
const ELEMENT_DOT_SPEC_R = 1.8;
const ELEMENT_DOT_SPEC_ALPHA = 180;
const ELEMENT_DOT_CLOCK_POSITIONS = [10, 11, 1, 2];
const ELEMENT_DOT_COLORS = [
  [255, 115, 25],  // Fire
  [102, 217, 77],  // Earth
  [64, 153, 255],  // Water
  [179, 140, 255], // Air
];
const ELEMENT_DOTS = ELEMENT_DOT_CLOCK_POSITIONS.map((hour, i) => {
  const angleDeg = (hour % 12) * 30;
  const rad = angleDeg * Math.PI / 180;
  return {
    x: ELEMENT_DOT_RADIUS_FROM_CENTER * Math.sin(rad),
    y: -ELEMENT_DOT_RADIUS_FROM_CENTER * Math.cos(rad),
    color: ELEMENT_DOT_COLORS[i],
  };
});

function shadeEmblem(dx, dy) {
  let c = [0, 0, 0, 0];
  const d = emblemShapeD(dx, dy);
  const outlineCov = sdfCoverage(d - EMBLEM_OUTLINE_W, UI_FALLOFF);
  if (outlineCov > 0) c = overStraight(c, EMBLEM_OUTLINE_COLOR, outlineCov);
  const mainCov = sdfCoverage(d, UI_FALLOFF);
  if (mainCov > 0) c = overStraight(c, emblemColorAt(dy), mainCov);
  for (const dot of ELEMENT_DOTS) {
    const ddx = dx - dot.x, ddy = dy - dot.y;
    const dd = Math.hypot(ddx, ddy) - ELEMENT_DOT_R;
    const cov = sdfCoverage(dd, UI_FALLOFF);
    if (cov > 0) {
      c = overStraight(c, dot.color, cov);
      const sdx = ddx - ELEMENT_DOT_SPEC_OFFSET[0], sdy = ddy - ELEMENT_DOT_SPEC_OFFSET[1];
      const sd = Math.hypot(sdx, sdy) - ELEMENT_DOT_SPEC_R;
      const scov = sdfCoverage(sd, UI_FALLOFF) * cov;
      if (scov > 0) c = overStraight(c, [255, 255, 255], scov * (ELEMENT_DOT_SPEC_ALPHA / 255));
    }
  }
  return c;
}

// --- Cell 3: divider hairline ----------------------------------------------
// 2px-core line at vertical middle, grey 110 peak at horizontal center fading
// to alpha 0 at both cell ends via a raised-cosine window, plus 1px soft
// vertical falloff above/below the core.
const DIVIDER_GREY = 110;
const DIVIDER_HALF_CORE = 1; // 2px core = +/-1px around center row
const DIVIDER_V_FALLOFF = 1; // additional 1px soft falloff
function shadeDivider(dx, dy) {
  const t = clamp(Math.abs(dx) / (UI_CELL / 2), 0, 1);
  const hWindow = Math.cos(t * Math.PI / 2); // 1 at center, 0 at cell ends
  const ady = Math.abs(dy);
  const vWeight = clamp(1 - Math.max(0, ady - DIVIDER_HALF_CORE) / DIVIDER_V_FALLOFF, 0, 1);
  const alpha = 255 * hWindow * vWeight;
  return [DIVIDER_GREY, DIVIDER_GREY, DIVIDER_GREY, Math.round(clamp(alpha, 0, 255))];
}

// --- Cell dispatcher + supersampled renderer -------------------------------
function shadeUiCellFull(cellIndex, dx, dy) {
  switch (cellIndex) {
    case CELL_SHADOW: return shadeShadow(dx, dy);
    case CELL_EMBLEM: return shadeEmblem(dx, dy);
    case CELL_DIVIDER: return shadeDivider(dx, dy);
    default: return [0, 0, 0, 0]; // cell 4: fully transparent (spare)
  }
}
function shadeUiCellPixel(cellIndex, px, py) {
  const c = UI_CELL / 2;
  let sumR = 0, sumG = 0, sumB = 0, sumA = 0;
  for (let sy = 0; sy < UI_SS; sy++) {
    for (let sx = 0; sx < UI_SS; sx++) {
      const dx = px + (sx + 0.5) / UI_SS - c;
      const dy = py + (sy + 0.5) / UI_SS - c;
      const [r, g, b, a] = shadeUiCellFull(cellIndex, dx, dy);
      const af = a / 255;
      sumR += r * af; sumG += g * af; sumB += b * af; sumA += a;
    }
  }
  const n = UI_SS * UI_SS;
  const avgA = sumA / n;
  if (avgA <= 0.0001) return [0, 0, 0, 0];
  const invA = 255 / avgA;
  return [
    Math.round(clamp((sumR / n) * invA, 0, 255)),
    Math.round(clamp((sumG / n) * invA, 0, 255)),
    Math.round(clamp((sumB / n) * invA, 0, 255)),
    Math.round(clamp(avgA, 0, 255)),
  ];
}

// ===========================================================================
// E. Verify: header sizes + seam check
// ===========================================================================
function verifyHeader(filePath, expectW, expectH, expectBytes) {
  const buf = fs.readFileSync(filePath);
  const w = buf[12] | (buf[13] << 8);
  const h = buf[14] | (buf[15] << 8);
  const type = buf[2], bpp = buf[16], descriptor = buf[17];
  const ok = buf.length === expectBytes && w === expectW && h === expectH && type === 2 && bpp === 32 && descriptor === 0x08;
  console.log((ok ? "OK  " : "FAIL") + " " + path.basename(filePath) + ": " + buf.length + "B " + w + "x" + h + " type=" + type + " bpp=" + bpp + " descriptor=0x" + descriptor.toString(16) + (ok ? "" : " (expected " + expectBytes + "B " + expectW + "x" + expectH + ")"));
  return ok;
}

// Seam check (Rev 4 iteration 2 rules): the TL corner's bottom row (y=15)
// borders the L edge tiled directly below it; the L edge is y-constant, so
// per-column comparison of that boundary row against the L profile checks
// the corner/edge seam pixel-for-pixel. In the SOLID region (pixel-center
// straight d = x + 0.5 < SEAM_SOLID_D_MAX) the values are asserted: alpha
// must be exactly 255 on both sides and |grey difference| <= SEAM_GREY_TOL.
// In the fade region (d >= 13) the radial-vs-linear d deviation (max ~0.4px
// at the innermost, already heavily faded pixel) is expected - those values
// are printed informationally only, not asserted.
const SEAM_SOLID_D_MAX = 13;
const SEAM_GREY_TOL = 2;
function seamCheck() {
  let pass = true;
  const lines = [];
  for (let x = 0; x < BORDER_CELL; x++) {
    const edge = sampleEdgeCellPixel("LT", x); // L-edge column x (y-independent)
    const corner = sampleCornerCellPixel(CORNER_PIVOTS.TL[0], CORNER_PIVOTS.TL[1], x, 15); // TL corner boundary row y=15
    const dCenter = x + 0.5;
    const solid = dCenter < SEAM_SOLID_D_MAX;
    const greyDiff = Math.abs(edge[0] - corner[0]);
    let verdict;
    if (solid) {
      const ok = edge[3] === 255 && corner[3] === 255 && greyDiff <= SEAM_GREY_TOL;
      if (!ok) pass = false;
      verdict = ok ? "OK" : "FAIL";
    } else {
      verdict = "info (fade)";
    }
    lines.push("  x=" + String(x).padStart(2) + " d=" + dCenter.toFixed(1).padStart(4)
      + "  L-edge grey/a=" + String(edge[0]).padStart(3) + "/" + String(edge[3]).padStart(3)
      + "  TL-corner grey/a=" + String(corner[0]).padStart(3) + "/" + String(corner[3]).padStart(3)
      + "  dGrey=" + String(greyDiff).padStart(2) + "  " + verdict);
  }
  console.log("seam check: TL-corner bottom row (y=15) vs L-edge profile, per column");
  console.log("  solid region d < " + SEAM_SOLID_D_MAX + " asserted (alpha==255, |dGrey| <= " + SEAM_GREY_TOL + "); fade region informational:");
  for (const line of lines) console.log(line);
  console.log("seam check (solid region): " + (pass ? "PASS" : "FAIL"));
  return pass;
}

// ===========================================================================
// Main
// ===========================================================================
function generate() {
  const dir = path.join(__dirname, "..", "textures");
  if (!fs.existsSync(dir)) fs.mkdirSync(dir);

  const borderImg = renderSheet(BORDER_W, BORDER_H, BORDER_CELL, BORDER_SEGMENTS, 1, shadeBorderCell);
  const borderFile = path.join(dir, "panel_border.tga");
  const borderBytes = writeTGA(borderFile, BORDER_W, BORDER_H, borderImg);
  console.log("wrote " + borderFile + " (" + borderBytes + " bytes)");

  const bgImg = renderSheet(BG_SIZE, BG_SIZE, BG_SIZE, 1, 1, (cell, px, py) => shadeBg(px, py));
  const bgFile = path.join(dir, "panel_bg.tga");
  const bgBytes = writeTGA(bgFile, BG_SIZE, BG_SIZE, bgImg);
  console.log("wrote " + bgFile + " (" + bgBytes + " bytes)");

  const uiImg = renderSheet(UI_SIZE, UI_SIZE, UI_CELL, UI_GRID, UI_GRID, shadeUiCellPixel);
  const uiFile = path.join(dir, "ui.tga");
  const uiBytes = writeTGA(uiFile, UI_SIZE, UI_SIZE, uiImg);
  console.log("wrote " + uiFile + " (" + uiBytes + " bytes)");

  console.log("");
  verifyHeader(borderFile, BORDER_W, BORDER_H, 18 + BORDER_W * BORDER_H * 4);
  verifyHeader(bgFile, BG_SIZE, BG_SIZE, 18 + BG_SIZE * BG_SIZE * 4);
  verifyHeader(uiFile, UI_SIZE, UI_SIZE, 18 + UI_SIZE * UI_SIZE * 4);
  console.log("");
  seamCheck();

  return { borderFile, bgFile, uiFile };
}

module.exports = {
  clamp, lerp, sdfCoverage, sdBoxAt, sdRoundedBoxAt, sdEllipseApprox, overStraight, angleFromTopDeg,
  renderSheet, writeTGA,
  BORDER_CELL, BORDER_SEGMENTS, BORDER_W, BORDER_H, BORDER_SS, PROFILE, profileAt,
  sampleEdgeCellPixel, sampleCornerCellPixel, CORNER_PIVOTS, CORNER_RADIUS,
  SEAM_SOLID_D_MAX, SEAM_GREY_TOL, shadeBorderCell,
  BG_SIZE, BG_BASE, hashNoise, shadeBg,
  UI_CELL, UI_GRID, UI_SIZE, UI_SS, UI_FALLOFF,
  CELL_SHADOW, CELL_EMBLEM, CELL_DIVIDER, CELL_SPARE,
  SHADOW, shadeShadow,
  EMBLEM_TOTAL_H, EMBLEM_TOP_Y, EMBLEM_TOP_COLOR, EMBLEM_BOT_COLOR, EMBLEM_OUTLINE_COLOR,
  ELEMENT_DOTS, ELEMENT_DOT_R, shadeEmblem,
  DIVIDER_GREY, shadeDivider,
  shadeUiCellFull, shadeUiCellPixel,
  verifyHeader, seamCheck, generate,
};

if (require.main === module) {
  generate();
}
