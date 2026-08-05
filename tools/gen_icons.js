// TotemBar - tools/gen_icons.js
// Generates the Rev 3 custom icon sheet (docs/superpowers/sdd/rev3-icons-brief.md):
// element glyph icons (replace INV_Misc_QuestionMark on empty slots), the Recall
// spiral icon (replaces Spell_Nature_AstralRecal), the DropSet diamond icon
// (replaces Spell_Nature_TremorTotem), and a transparent-background minimap totem
// glyph (drawn inside the existing golden TrackingBorder).
//
// textures/icons.tga - 512x512, 4x4 grid of 128x128 cells (1-based cell numbers
// below match the brief):
//   1 FIRE   - flame: union of two teardrop lobes, hot-core radial gradient,
//              soft outer glow, opaque backing.
//   2 EARTH  - mountain: rounded-corner triangle + smaller peak behind, top-left
//              facet highlight, darker baseline bar, opaque backing.
//   3 WATER  - droplet: circle+cusp teardrop, specular highlight, two wave arcs,
//              opaque backing.
//   4 AIR    - wind swirl: three concentric tapered arc swooshes, opaque backing.
//   5 RECALL - inward spiral arrow ending in a solid arrowhead + center dot,
//              opaque backing (fallback/identity icon for the Recall button).
//   6 DROPSET- four-dot elemental diamond + soft chevron underlay, opaque backing.
//   7 MINIMAP- totem silhouette (stacked rounded segments + dome cap), TRANSPARENT
//              background (composited inside the minimap button's TrackingBorder).
//   8-16     - fully transparent (unused).
//
// All glyphs are rendered via smooth distance-field (SDF) math: each shape
// exposes a signed-distance function (negative = inside), converted to a
// 0..1 coverage value with a soft edge falloff, combined with 4x4-per-pixel
// supersampling (full premultiplied-color average per pixel) for smooth,
// alias-free curves - no hard-edged shapes anywhere on this sheet.
//
// 32-bit uncompressed TGA, bottom-up rows (descriptor 0x08) - the same header
// pfUI's own TGAs use (verified to render on 1.12). Zero dependencies.
// Copies the TGA-writer pattern from tools/gen_ring_textures.js (read-only
// reference; that file is NOT modified or required here).
// Run: node tools/gen_icons.js
"use strict";

const fs = require("fs");
const path = require("path");

// ===========================================================================
// Sheet layout
// ===========================================================================
const CELL = 128;         // px per grid cell
const GRID = 4;           // 4x4 cells
const SIZE = CELL * GRID; // 512
const SS = 4;             // supersampling factor per axis (4x4=16 samples/px),
                           // per the brief's "4x supersampling"
const EDGE_FALLOFF_PX = 1.5; // distance-field edge soft-falloff width, per brief

// 0-based cell indices (row-major, matches the brief's 1-based numbering - 1)
const CELL_FIRE = 0;
const CELL_EARTH = 1;
const CELL_WATER = 2;
const CELL_AIR = 3;
const CELL_RECALL = 4;
const CELL_DROPSET = 5;
const CELL_MINIMAP = 6;
// cells 7..15 (0-based) = brief's cells 8-16 = fully transparent

// ---------------------------------------------------------------------
// Small-number helpers
// ---------------------------------------------------------------------
function clamp(v, lo, hi) { return v < lo ? lo : (v > hi ? hi : v); }
function lerp(a, b, t) { return a + (b - a) * t; }
function lerp3(c1, c2, t) { return [lerp(c1[0], c2[0], t), lerp(c1[1], c2[1], t), lerp(c1[2], c2[2], t)]; }
function addBrightness(col, amt) { return [clamp(col[0] + amt, 0, 255), clamp(col[1] + amt, 0, 255), clamp(col[2] + amt, 0, 255)]; }
function mulColor(col, factor) { return [clamp(col[0] * factor, 0, 255), clamp(col[1] * factor, 0, 255), clamp(col[2] * factor, 0, 255)]; }
function toRgb255(r, g, b) { return [Math.round(r * 255), Math.round(g * 255), Math.round(b * 255)]; }

// Angle in degrees, 0 at straight up, increasing clockwise (image y grows down).
function angleFromTopDeg(dx, dy) {
  let a = Math.atan2(dx, -dy) * 180 / Math.PI;
  if (a < 0) a += 360;
  return a;
}

// Converts a signed distance (negative = inside) to a 0..1 coverage value
// with a soft transition band of width EDGE_FALLOFF_PX centered on d=0.
function sdfCoverage(d, falloff) {
  return clamp(0.5 - d / falloff, 0, 1);
}

// ---------------------------------------------------------------------
// Generic 2D SDF primitives (negative = inside)
// ---------------------------------------------------------------------
function sdCircleAt(dx, dy, cx, cy, r) {
  return Math.hypot(dx - cx, dy - cy) - r;
}

function sdBoxAt(dx, dy, cx, cy, hx, hy) {
  const px = Math.abs(dx - cx) - hx;
  const py = Math.abs(dy - cy) - hy;
  const ox = Math.max(px, 0), oy = Math.max(py, 0);
  return Math.hypot(ox, oy) + Math.min(Math.max(px, py), 0);
}

function sdRoundedBoxAt(dx, dy, cx, cy, hx, hy, r) {
  return sdBoxAt(dx, dy, cx, cy, hx - r, hy - r) - r;
}

// Standard generic-polygon SDF (Inigo Quilez's well-known 2D distance-field
// formula: min edge-segment distance + crossing-number sign test). Works for
// any simple (non-self-intersecting) polygon regardless of winding order.
// Dilating the result by a negative offset (d - r) rounds every convex corner
// by radius r (Minkowski dilation of the polygon by a disc of radius r) -
// used for the rounded-corner triangle (EARTH) and arrowhead (RECALL).
function sdPolygon(verts, px, py) {
  const n = verts.length;
  let d = (px - verts[0][0]) * (px - verts[0][0]) + (py - verts[0][1]) * (py - verts[0][1]);
  let s = 1;
  for (let i = 0, j = n - 1; i < n; j = i, i++) {
    const vix = verts[i][0], viy = verts[i][1];
    const vjx = verts[j][0], vjy = verts[j][1];
    const ex = vjx - vix, ey = vjy - viy;
    const wx = px - vix, wy = py - viy;
    const eDotE = ex * ex + ey * ey;
    const t = clamp(eDotE > 0 ? (wx * ex + wy * ey) / eDotE : 0, 0, 1);
    const bx = wx - ex * t, by = wy - ey * t;
    const bd = bx * bx + by * by;
    if (bd < d) d = bd;
    const c1 = py >= viy, c2 = py < vjy, c3 = (ex * wy - ey * wx) > 0;
    if ((c1 && c2 && c3) || (!c1 && !c2 && !c3)) s = -s;
  }
  return s * Math.sqrt(d);
}

// Distance to a line segment [a,b] (unsigned - used only for open strokes).
function sdSegment(dx, dy, ax, ay, bx, by) {
  const pxv = dx - ax, pyv = dy - ay, bxv = bx - ax, byv = by - ay;
  const eDotE = bxv * bxv + byv * byv;
  const h = clamp(eDotE > 0 ? (pxv * bxv + pyv * byv) / eDotE : 0, 0, 1);
  const cx = pxv - bxv * h, cy = pyv - byv * h;
  return Math.hypot(cx, cy);
}

// Cheap ellipse pseudo-SDF (scale-normalized radial distance * min axis) -
// exact on the boundary, approximate off it; adequate for AA of small
// decorative highlights/domes at this falloff width.
function sdEllipseApprox(dx, dy, cx, cy, rx, ry) {
  const nx = (dx - cx) / rx, ny = (dy - cy) / ry;
  const n = Math.hypot(nx, ny);
  const minAxis = Math.min(rx, ry);
  return n < 1e-9 ? -minAxis : (n - 1) * minAxis;
}

// Rotated variant: rotates the query point into the ellipse's local frame
// (by -angleDeg) before applying sdEllipseApprox.
function sdEllipseRotated(dx, dy, cx, cy, rx, ry, angleDeg) {
  const rad = -angleDeg * Math.PI / 180;
  const px = dx - cx, py = dy - cy;
  const cos = Math.cos(rad), sin = Math.sin(rad);
  const lx = px * cos - py * sin, ly = px * sin + py * cos;
  return sdEllipseApprox(lx, ly, 0, 0, rx, ry);
}

// "Teardrop lobe": a circle of radius r centered at `center`, warped toward
// a cusp point (the brief's "circle... warped upward into a cusp... via a
// quadratic bend"). Implemented as the convex hull of the circle and the
// cusp point - i.e. the circle unioned with the solid triangle formed by the
// cusp and its two tangent points on the circle. This is the standard exact
// construction for a circle-to-point "ice cream cone" silhouette: the
// boundary follows the circle, transitions smoothly (tangentially, zero
// curvature discontinuity) into two straight tangent lines, and those lines
// meet at `cusp` at a genuine sharp point (a quadratic *radius-vs-angle*
// bulge, tried first, only ever produces a smooth rounded bump - a parabola
// has zero slope at its own peak - so it can't form an actual cusp; the
// tangent-line construction below is what actually reads as a pointed
// flame/droplet tip and is used instead. See rev3-icons-report.md deviations).
// Tangent points derived once per lobe (`computeTangentTriangle`), not
// per-pixel: for a circle of radius r at C and an external point T at
// distance d from C, the two tangent points lie at (r^2/d) along the C->T
// axis, offset by (r/d)*sqrt(d^2-r^2) perpendicular to it (standard
// circle/external-point tangent-length geometry).
function computeTangentTriangle(center, r, cusp) {
  const cdx = cusp[0] - center[0], cdy = cusp[1] - center[1];
  const d = Math.hypot(cdx, cdy);
  if (d <= r) return null; // cusp inside/on the circle: no tangent wedge needed
  const ux = cdx / d, uy = cdy / d;       // unit vector center -> cusp
  const perpx = -uy, perpy = ux;          // perpendicular unit vector
  const tangentLen = Math.sqrt(d * d - r * r);
  const alongDist = (r * r) / d;          // distance along `u` to the tangent points
  const acrossDist = (r / d) * tangentLen; // perpendicular offset of the tangent points
  const t1 = [center[0] + alongDist * ux + acrossDist * perpx, center[1] + alongDist * uy + acrossDist * perpy];
  const t2 = [center[0] + alongDist * ux - acrossDist * perpx, center[1] + alongDist * uy - acrossDist * perpy];
  return [t1, cusp, t2];
}
function lobeSDF(dx, dy, center, r, cusp, tangentTriangle) {
  const dCircle = sdCircleAt(dx, dy, center[0], center[1], r);
  if (!tangentTriangle) return dCircle;
  const dWedge = sdPolygon(tangentTriangle, dx, dy);
  return Math.min(dCircle, dWedge);
}

// Gaussian glow/halo alpha (0..1), hard-windowed to exactly 0 past
// windowStart (same "exp falloff + linear window" recipe as
// tools/gen_ring_textures.js's fx cells, reimplemented locally here).
function haloAlpha01(d, cfg) {
  if (d <= 0) return 0;
  const w = clamp((cfg.windowStart - d) / cfg.windowWidth, 0, 1);
  return clamp((cfg.peakAlpha / 255) * Math.exp(-Math.pow(d / cfg.widthPx, 2)) * w, 0, 1);
}

// Standard straight-alpha "A over B" compositing.
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

// ===========================================================================
// Shared opaque backing (cells 1-6): radial gradient, opaque corner-to-corner
// so a normal ring/frame band can cover the corners like any WoW icon.
// ===========================================================================
const BACKING = {
  centerColor: [30, 28, 26],
  edgeColor: [11, 11, 11],
  radiusPx: Math.sqrt(2) * (CELL / 2), // reaches full edgeColor exactly at the cell corner
};
function backingColorAt(dx, dy) {
  const t = clamp(Math.hypot(dx, dy) / BACKING.radiusPx, 0, 1);
  return lerp3(BACKING.centerColor, BACKING.edgeColor, t);
}

// ===========================================================================
// Cell 1 - FIRE (flame)
// ===========================================================================
const FIRE = {
  mainCenter: [0, 10], mainR: 30, mainCusp: [0, -38],
  subCenter: [12, -2], subR: 16, subCusp: [-4, -30],
  coreColor: [255, 236, 150], midColor: [255, 150, 40], edgeColor: [200, 60, 10],
  halo: { widthPx: 8, peakAlpha: 150, windowStart: 16, windowWidth: 3, color: [255, 150, 40] },
};
const FIRE_MAIN_TRIANGLE = computeTangentTriangle(FIRE.mainCenter, FIRE.mainR, FIRE.mainCusp);
const FIRE_SUB_TRIANGLE = computeTangentTriangle(FIRE.subCenter, FIRE.subR, FIRE.subCusp);
function fireFlameD(dx, dy) {
  const d1 = lobeSDF(dx, dy, FIRE.mainCenter, FIRE.mainR, FIRE.mainCusp, FIRE_MAIN_TRIANGLE);
  const d2 = lobeSDF(dx, dy, FIRE.subCenter, FIRE.subR, FIRE.subCusp, FIRE_SUB_TRIANGLE);
  return Math.min(d1, d2);
}
function fireColorAt(dx, dy) {
  const rx = dx - FIRE.mainCenter[0], ry = dy - FIRE.mainCenter[1];
  const dist = Math.hypot(rx, ry);
  const maxDist = Math.hypot(FIRE.mainCusp[0] - FIRE.mainCenter[0], FIRE.mainCusp[1] - FIRE.mainCenter[1]);
  const t = clamp(dist / maxDist, 0, 1);
  return t < 0.5 ? lerp3(FIRE.coreColor, FIRE.midColor, t * 2) : lerp3(FIRE.midColor, FIRE.edgeColor, (t - 0.5) * 2);
}
function shadeFire(dx, dy) {
  let c = [BACKING.centerColor[0], BACKING.centerColor[1], BACKING.centerColor[2], 255];
  c[0] = backingColorAt(dx, dy)[0]; c[1] = backingColorAt(dx, dy)[1]; c[2] = backingColorAt(dx, dy)[2];
  const d = fireFlameD(dx, dy);
  if (d > 0) {
    const a = haloAlpha01(d, FIRE.halo);
    if (a > 0) c = overStraight(c, FIRE.halo.color, a);
  }
  const cov = sdfCoverage(d, EDGE_FALLOFF_PX);
  if (cov > 0) c = overStraight(c, fireColorAt(dx, dy), cov);
  return c;
}

// ===========================================================================
// Cell 2 - EARTH (mountain)
// ===========================================================================
const EARTH = {
  frontVerts: [[-34, 28], [34, 28], [0, -30]],
  cornerRadius: 8,
  backOffsetX: 16, backHeightScale: 0.7, backDarkenFactor: 0.72, // "darker" - assumption, named
  facetBrightAdd: 14,
  baseColor: [92, 138, 58], edgeColor: [44, 72, 30],
  baselineBar: { height: 6, halfWidth: 44, color: [26, 40, 18] }, // assumption, named
};
const EARTH_BASE_Y = EARTH.frontVerts[0][1];
const EARTH_APEX_Y = EARTH.frontVerts[2][1];
const EARTH_BACK_APEX_Y = EARTH_BASE_Y - EARTH.backHeightScale * (EARTH_BASE_Y - EARTH_APEX_Y);
const EARTH_BACK_VERTS = [
  [EARTH.frontVerts[0][0] + EARTH.backOffsetX, EARTH_BASE_Y],
  [EARTH.frontVerts[1][0] + EARTH.backOffsetX, EARTH_BASE_Y],
  [EARTH.frontVerts[2][0] + EARTH.backOffsetX, EARTH_BACK_APEX_Y],
];
const EARTH_FRONT_APEX_X = EARTH.frontVerts[2][0];
const EARTH_BACK_APEX_X = EARTH_BACK_VERTS[2][0];
function earthColorAt(dy) {
  const t = clamp((dy - EARTH_APEX_Y) / (EARTH_BASE_Y - EARTH_APEX_Y), 0, 1);
  return lerp3(EARTH.edgeColor, EARTH.baseColor, t); // edge (darker) at apex/top, base (brighter) at bottom
}
function shadeEarth(dx, dy) {
  let c = [...backingColorAt(dx, dy), 255];
  const bar = EARTH.baselineBar;
  const barD = sdBoxAt(dx, dy, 0, EARTH_BASE_Y + bar.height / 2, bar.halfWidth, bar.height / 2);
  const barCov = sdfCoverage(barD, EDGE_FALLOFF_PX);
  if (barCov > 0) c = overStraight(c, bar.color, barCov);

  const backD = sdPolygon(EARTH_BACK_VERTS, dx, dy) - EARTH.cornerRadius;
  const backCov = sdfCoverage(backD, EDGE_FALLOFF_PX);
  if (backCov > 0) {
    let col = mulColor(earthColorAt(dy), EARTH.backDarkenFactor);
    if (dx < EARTH_BACK_APEX_X) col = addBrightness(col, EARTH.facetBrightAdd);
    c = overStraight(c, col, backCov);
  }

  const frontD = sdPolygon(EARTH.frontVerts, dx, dy) - EARTH.cornerRadius;
  const frontCov = sdfCoverage(frontD, EDGE_FALLOFF_PX);
  if (frontCov > 0) {
    let col = earthColorAt(dy);
    if (dx < EARTH_FRONT_APEX_X) col = addBrightness(col, EARTH.facetBrightAdd);
    c = overStraight(c, col, frontCov);
  }
  return c;
}

// ===========================================================================
// Cell 3 - WATER (droplet)
// ===========================================================================
const WATER = {
  center: [0, 8], r: 26, cusp: [0, -36],
  coreColor: [60, 140, 240], edgeColor: [20, 70, 160],
  specular: { center: [-9, -2], halfW: 3.5, halfH: 5.5, angleDeg: -25, color: [210, 240, 255], alpha: 200 },
  waveArcRadius: 90, waveArcStrokeHalfWidth: 1.1, waveAlpha: 90, waveColor: [230, 250, 255],
  waveArcs: [ { sagY: 16, xHalfSpan: 14 }, { sagY: 24, xHalfSpan: 11 } ], // "lower third", assumption
};
const WATER_TRIANGLE = computeTangentTriangle(WATER.center, WATER.r, WATER.cusp);
function waterDropD(dx, dy) {
  return lobeSDF(dx, dy, WATER.center, WATER.r, WATER.cusp, WATER_TRIANGLE);
}
function waterColorAt(dx, dy) {
  const dist = Math.hypot(dx - WATER.center[0], dy - WATER.center[1]);
  const maxDist = Math.hypot(WATER.cusp[0] - WATER.center[0], WATER.cusp[1] - WATER.center[1]);
  return lerp3(WATER.coreColor, WATER.edgeColor, clamp(dist / maxDist, 0, 1));
}
function waveArcCoverage(dx, dy, arc) {
  const circleCy = arc.sagY - WATER.waveArcRadius;
  const rd = Math.hypot(dx, dy - circleCy);
  const bandD = Math.abs(rd - WATER.waveArcRadius) - WATER.waveArcStrokeHalfWidth;
  let cov = sdfCoverage(bandD, EDGE_FALLOFF_PX);
  cov *= sdfCoverage(Math.abs(dx) - arc.xHalfSpan, EDGE_FALLOFF_PX);
  return cov;
}
function shadeWater(dx, dy) {
  let c = [...backingColorAt(dx, dy), 255];
  const d = waterDropD(dx, dy);
  const cov = sdfCoverage(d, EDGE_FALLOFF_PX);
  if (cov > 0) {
    c = overStraight(c, waterColorAt(dx, dy), cov);
    const sp = WATER.specular;
    const specD = sdEllipseRotated(dx, dy, sp.center[0], sp.center[1], sp.halfW, sp.halfH, sp.angleDeg);
    const specCov = sdfCoverage(specD, EDGE_FALLOFF_PX) * cov;
    if (specCov > 0) c = overStraight(c, sp.color, specCov * (sp.alpha / 255));
    for (const arc of WATER.waveArcs) {
      const arcCov = waveArcCoverage(dx, dy, arc) * cov;
      if (arcCov > 0) c = overStraight(c, WATER.waveColor, arcCov * (WATER.waveAlpha / 255));
    }
  }
  return c;
}

// ===========================================================================
// Cell 4 - AIR (wind swirl)
// ===========================================================================
const AIR = {
  radii: [30, 22, 14],
  spanDeg: 200,
  baseTailDeg: 0, tailStepDeg: 25, // "each arc's tail offset +25deg from the previous"
  strokeMaxWidth: 7, // iteration-2 fix: +40% thicker (was 5) so the swirl reads at 30px in-game
  headAlpha: 255, tailAlpha: 90, // iteration-2 fix: tail raised from 40 (was near-invisible on the dark backing)
  headColor: [235, 225, 255], tailColor: [150, 130, 220], // iteration-2 fix: near-white heads, brighter tails
  glow: { widthPx: 6, peakAlpha: 110, windowStart: 14, windowWidth: 3, color: [160, 140, 240] }, // iteration-2 fix: subtle violet outer glow behind the swooshes (same recipe as FIRE's halo)
};
// Signed distance to arc i's tapered annulus band (negative = inside), plus
// the 0..1 head-fraction along the arc; null when the query angle is outside
// the arc's angular span. The distance is reused for both the swoosh fill
// coverage and the outer glow falloff.
function airArcDist(dx, dy, i) {
  const rI = AIR.radii[i];
  const tailDeg = AIR.baseTailDeg + i * AIR.tailStepDeg;
  const rad = Math.hypot(dx, dy);
  const af = angleFromTopDeg(dx, dy);
  const rel = ((af - tailDeg) % 360 + 360) % 360;
  if (rel > AIR.spanDeg) return null;
  const widthFrac = rel / AIR.spanDeg; // 0 tail .. 1 head
  const width = AIR.strokeMaxWidth * Math.sin(Math.PI * widthFrac); // tapers to a point at both ends
  return { d: Math.abs(rad - rI) - width / 2, widthFrac };
}
function airArcShade(dx, dy, i) {
  const hit = airArcDist(dx, dy, i);
  if (!hit) return null;
  const cov = sdfCoverage(hit.d, EDGE_FALLOFF_PX);
  if (cov <= 0) return null;
  return { cov, alpha01: lerp(AIR.tailAlpha, AIR.headAlpha, hit.widthFrac) / 255, color: lerp3(AIR.tailColor, AIR.headColor, hit.widthFrac) };
}
function shadeAir(dx, dy) {
  let c = [...backingColorAt(dx, dy), 255];
  // Glow layer first (painted behind the swooshes): gaussian halo off the
  // nearest arc band, weighted by that arc's own head->tail alpha ramp so
  // the glow follows the swoosh's fade instead of forming a uniform ring.
  let glowA = 0;
  for (let i = 0; i < AIR.radii.length; i++) {
    const hit = airArcDist(dx, dy, i);
    if (!hit || hit.d <= 0) continue;
    const rampMul = lerp(AIR.tailAlpha, AIR.headAlpha, hit.widthFrac) / 255;
    const a = haloAlpha01(hit.d, AIR.glow) * rampMul;
    if (a > glowA) glowA = a;
  }
  if (glowA > 0) c = overStraight(c, AIR.glow.color, glowA);
  for (let i = 0; i < AIR.radii.length; i++) {
    const s = airArcShade(dx, dy, i);
    if (s) c = overStraight(c, s.color, s.cov * s.alpha01);
  }
  return c;
}

// ===========================================================================
// Cell 5 - RECALL (inward spiral arrow)
// ===========================================================================
const RECALL = {
  rStart: 34, rEnd: 12, spiralTotalDeg: 540, strokeHalfWidth: 3.5,
  outerCapCenter: [0, -34], // theta=0 (top), r=rStart
  arrowLength: 16, arrowBaseHalfWidth: 7, // tip at center (0,0), base at r=arrowLength, theta=180 (bottom)
  centerDotR: 5,
  brightGold: [255, 215, 120], darkGold: [190, 140, 40],
  glow: { widthPx: 6, peakAlpha: 110, windowStart: 14, windowWidth: 3, color: [255, 215, 120] },
};
const RECALL_ARROW_VERTS = [[0, 0], [-RECALL.arrowBaseHalfWidth, RECALL.arrowLength], [RECALL.arrowBaseHalfWidth, RECALL.arrowLength]];
function spiralBandD(dx, dy) {
  const rad = Math.hypot(dx, dy);
  const af = angleFromTopDeg(dx, dy);
  let best = Infinity;
  for (const cand of [af, af + 360]) {
    if (cand < 0 || cand > RECALL.spiralTotalDeg) continue;
    const t = cand / RECALL.spiralTotalDeg;
    const rTheta = lerp(RECALL.rStart, RECALL.rEnd, t);
    const dd = Math.abs(rad - rTheta) - RECALL.strokeHalfWidth;
    if (dd < best) best = dd;
  }
  return best;
}
function recallColorAt(dx, dy) {
  const rad = Math.hypot(dx, dy);
  const af = angleFromTopDeg(dx, dy);
  let bestT = 1, bestDiff = Infinity;
  for (const cand of [af, af + 360]) {
    if (cand < 0 || cand > RECALL.spiralTotalDeg) continue;
    const t = cand / RECALL.spiralTotalDeg;
    const rTheta = lerp(RECALL.rStart, RECALL.rEnd, t);
    const diff = Math.abs(rad - rTheta);
    if (diff < bestDiff) { bestDiff = diff; bestT = t; }
  }
  return lerp3(RECALL.brightGold, RECALL.darkGold, bestT);
}
function shadeRecall(dx, dy) {
  let c = [...backingColorAt(dx, dy), 255];
  const spiralD = spiralBandD(dx, dy);
  const capD = sdCircleAt(dx, dy, RECALL.outerCapCenter[0], RECALL.outerCapCenter[1], RECALL.strokeHalfWidth);
  const arrowD = sdPolygon(RECALL_ARROW_VERTS, dx, dy);
  const dotD = sdCircleAt(dx, dy, 0, 0, RECALL.centerDotR);
  const shapeD = Math.min(spiralD, capD, arrowD, dotD);
  if (shapeD > 0) {
    const a = haloAlpha01(shapeD, RECALL.glow);
    if (a > 0) c = overStraight(c, RECALL.glow.color, a);
  }
  const tubeD = Math.min(spiralD, capD, arrowD);
  const tubeCov = sdfCoverage(tubeD, EDGE_FALLOFF_PX);
  if (tubeCov > 0) c = overStraight(c, recallColorAt(dx, dy), tubeCov);
  const dotCov = sdfCoverage(dotD, EDGE_FALLOFF_PX);
  if (dotCov > 0) c = overStraight(c, RECALL.darkGold, dotCov);
  return c;
}

// ===========================================================================
// Cell 6 - DROPSET (four-dot elemental diamond + chevron)
// ===========================================================================
const DROPSET = {
  dotR: 11, // iteration-2 fix: was 9 (more presence)
  spec: { offset: [-3, -3], r: 2.8, color: [255, 255, 255], alpha: 180 }, // assumption, named
  dots: [ // offsets 24 (iteration-2 fix: was 22)
    { offset: [0, -24], color: toRgb255(1.00, 0.45, 0.10) }, // Fire, top
    { offset: [24, 0], color: toRgb255(0.70, 0.55, 1.00) },  // Air, right
    { offset: [0, 24], color: toRgb255(0.25, 0.60, 1.00) },  // Water, bottom
    { offset: [-24, 0], color: toRgb255(0.40, 0.85, 0.30) }, // Earth, left
  ],
  chevron: {
    vertex: [0, 6], armEndX: 16, armEndY: 6 - 12, // assumption, named (span not given numerically)
    halfWidth: 3.5, alpha: 120, color: [255, 255, 255],
  },
};
const DROPSET_CHEVRON_SEGS = [
  { a: DROPSET.chevron.vertex, b: [-DROPSET.chevron.armEndX, DROPSET.chevron.armEndY] },
  { a: DROPSET.chevron.vertex, b: [DROPSET.chevron.armEndX, DROPSET.chevron.armEndY] },
];
function shadeDropSet(dx, dy) {
  let c = [...backingColorAt(dx, dy), 255];
  for (const seg of DROPSET_CHEVRON_SEGS) {
    const d = sdSegment(dx, dy, seg.a[0], seg.a[1], seg.b[0], seg.b[1]) - DROPSET.chevron.halfWidth;
    const cov = sdfCoverage(d, EDGE_FALLOFF_PX);
    if (cov > 0) c = overStraight(c, DROPSET.chevron.color, cov * (DROPSET.chevron.alpha / 255));
  }
  for (const dot of DROPSET.dots) {
    const d = sdCircleAt(dx, dy, dot.offset[0], dot.offset[1], DROPSET.dotR);
    const cov = sdfCoverage(d, EDGE_FALLOFF_PX);
    if (cov > 0) {
      c = overStraight(c, dot.color, cov);
      const sp = DROPSET.spec;
      const sd = sdCircleAt(dx, dy, dot.offset[0] + sp.offset[0], dot.offset[1] + sp.offset[1], sp.r);
      const scov = sdfCoverage(sd, EDGE_FALLOFF_PX) * cov;
      if (scov > 0) c = overStraight(c, sp.color, scov * (sp.alpha / 255));
    }
  }
  return c;
}

// ===========================================================================
// Cell 7 - MINIMAP (totem silhouette, TRANSPARENT background)
// ===========================================================================
const MINIMAP_SEG1 = { w: 20, h: 12 }; // top (narrowest)
const MINIMAP_SEG2 = { w: 26, h: 14 }; // middle
const MINIMAP_SEG3 = { w: 34, h: 16 }; // bottom (widest, base)
const MINIMAP_GAP = 3;
const MINIMAP_DOME_H = 16;
const MINIMAP_CORNER_R = 5;
const MINIMAP_OUTLINE_WIDTH = 1;
const MINIMAP_TOTAL_H = MINIMAP_SEG1.h + MINIMAP_GAP + MINIMAP_SEG2.h + MINIMAP_GAP + MINIMAP_SEG3.h + MINIMAP_DOME_H; // 64
const MINIMAP_TOP_Y = -MINIMAP_TOTAL_H / 2; // -32
const MINIMAP_SEG1_TOP = MINIMAP_TOP_Y + MINIMAP_DOME_H;
const MINIMAP_SEG1_BOTTOM = MINIMAP_SEG1_TOP + MINIMAP_SEG1.h;
const MINIMAP_SEG2_TOP = MINIMAP_SEG1_BOTTOM + MINIMAP_GAP;
const MINIMAP_SEG2_BOTTOM = MINIMAP_SEG2_TOP + MINIMAP_SEG2.h;
const MINIMAP_SEG3_TOP = MINIMAP_SEG2_BOTTOM + MINIMAP_GAP;
const MINIMAP_SEG3_BOTTOM = MINIMAP_SEG3_TOP + MINIMAP_SEG3.h; // = MINIMAP_TOTAL_H/2 (32)
const MINIMAP_SEGS = [
  { cy: (MINIMAP_SEG1_TOP + MINIMAP_SEG1_BOTTOM) / 2, hw: MINIMAP_SEG1.w / 2, hh: MINIMAP_SEG1.h / 2 },
  { cy: (MINIMAP_SEG2_TOP + MINIMAP_SEG2_BOTTOM) / 2, hw: MINIMAP_SEG2.w / 2, hh: MINIMAP_SEG2.h / 2 },
  { cy: (MINIMAP_SEG3_TOP + MINIMAP_SEG3_BOTTOM) / 2, hw: MINIMAP_SEG3.w / 2, hh: MINIMAP_SEG3.h / 2 },
];
const MINIMAP_DOME = { cy: MINIMAP_SEG1_TOP, rx: MINIMAP_SEG1.w / 2, ry: MINIMAP_DOME_H };
const MINIMAP_TOP_COLOR = [230, 190, 110];
const MINIMAP_BOTTOM_COLOR = [140, 95, 45];
const MINIMAP_OUTLINE_COLOR = [45, 30, 16]; // assumption, named ("1px darker outline")

function totemUnionD(dx, dy) {
  let d = Infinity;
  for (const seg of MINIMAP_SEGS) {
    const sd = sdRoundedBoxAt(dx, dy, 0, seg.cy, seg.hw, seg.hh, MINIMAP_CORNER_R);
    if (sd < d) d = sd;
  }
  if (dy <= MINIMAP_DOME.cy) {
    const ed = sdEllipseApprox(dx, dy, 0, MINIMAP_DOME.cy, MINIMAP_DOME.rx, MINIMAP_DOME.ry);
    if (ed < d) d = ed;
  }
  return d;
}
function minimapColorAt(dy) {
  const t = clamp((dy - MINIMAP_TOP_Y) / MINIMAP_TOTAL_H, 0, 1);
  return lerp3(MINIMAP_TOP_COLOR, MINIMAP_BOTTOM_COLOR, t);
}
function shadeMinimap(dx, dy) {
  let c = [0, 0, 0, 0];
  const mainD = totemUnionD(dx, dy);
  const outlineD = mainD - MINIMAP_OUTLINE_WIDTH;
  const outlineCov = sdfCoverage(outlineD, EDGE_FALLOFF_PX);
  if (outlineCov > 0) c = overStraight(c, MINIMAP_OUTLINE_COLOR, outlineCov);
  const mainCov = sdfCoverage(mainD, EDGE_FALLOFF_PX);
  if (mainCov > 0) c = overStraight(c, minimapColorAt(dy), mainCov);
  return c;
}

// ===========================================================================
// Dispatcher + supersampled renderer
// ===========================================================================
function shadeIconCellFull(cellIndex, dx, dy) {
  switch (cellIndex) {
    case CELL_FIRE: return shadeFire(dx, dy);
    case CELL_EARTH: return shadeEarth(dx, dy);
    case CELL_WATER: return shadeWater(dx, dy);
    case CELL_AIR: return shadeAir(dx, dy);
    case CELL_RECALL: return shadeRecall(dx, dy);
    case CELL_DROPSET: return shadeDropSet(dx, dy);
    case CELL_MINIMAP: return shadeMinimap(dx, dy);
    default: return [0, 0, 0, 0]; // cells 8-16 (0-based 7..15): fully transparent
  }
}

// Supersamples SSxSS sub-pixel positions per output pixel, accumulating
// PREMULTIPLIED color + straight alpha, then un-premultiplies the average -
// avoids dark/light fringing at antialiased edges (same technique
// tools/preview_ring.js uses when resampling cells).
function shadeIconCellPixel(cellIndex, px, py) {
  const c = CELL / 2;
  let sumR = 0, sumG = 0, sumB = 0, sumA = 0;
  for (let sy = 0; sy < SS; sy++) {
    for (let sx = 0; sx < SS; sx++) {
      const dx = px + (sx + 0.5) / SS - c;
      const dy = py + (sy + 0.5) / SS - c;
      const [r, g, b, a] = shadeIconCellFull(cellIndex, dx, dy);
      const af = a / 255;
      sumR += r * af; sumG += g * af; sumB += b * af; sumA += a;
    }
  }
  const n = SS * SS;
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
// Generic sheet renderer + TGA writer (same format/pattern as
// tools/gen_ring_textures.js: 18-byte header, type 2, 32bpp, descriptor 0x08
// bottom-up BGRA - reimplemented locally, that file is untouched).
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

function generate() {
  const dir = path.join(__dirname, "..", "textures");
  if (!fs.existsSync(dir)) fs.mkdirSync(dir);
  const img = renderSheet(SIZE, CELL, GRID, GRID, shadeIconCellPixel);
  const file = path.join(dir, "icons.tga");
  const bytes = writeTGA(file, SIZE, img);
  console.log("wrote " + file + " (" + bytes + " bytes)");
  return { file, bytes };
}

module.exports = {
  CELL, GRID, SIZE, SS, EDGE_FALLOFF_PX,
  CELL_FIRE, CELL_EARTH, CELL_WATER, CELL_AIR, CELL_RECALL, CELL_DROPSET, CELL_MINIMAP,
  BACKING, FIRE, EARTH, WATER, AIR, RECALL, DROPSET,
  MINIMAP_SEGS, MINIMAP_DOME, MINIMAP_TOTAL_H, MINIMAP_TOP_COLOR, MINIMAP_BOTTOM_COLOR, MINIMAP_OUTLINE_COLOR,
  clamp, lerp, lerp3, sdfCoverage, sdCircleAt, sdBoxAt, sdRoundedBoxAt, sdPolygon, sdSegment,
  sdEllipseApprox, sdEllipseRotated, lobeSDF, computeTangentTriangle, angleFromTopDeg, haloAlpha01, overStraight,
  backingColorAt, fireFlameD, fireColorAt, earthColorAt, waterDropD, waterColorAt,
  spiralBandD, recallColorAt, totemUnionD, minimapColorAt,
  shadeIconCellFull, shadeIconCellPixel, renderSheet, writeTGA, generate,
};

if (require.main === module) {
  generate();
}
