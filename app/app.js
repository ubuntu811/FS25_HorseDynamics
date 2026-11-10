(function () {
'use strict';
// ====================== data ======================
const nodes = DATA.nodes, NN = nodes.length;
const idxOf = {}; nodes.forEach((n, i) => { idxOf[n.name] = i; });
const MESH_NAMES = ['body', 'maneTail', 'saddle', 'reins'];

// ====================== 4x4 matrices (row-major, Float64Array) ======================
const I4 = () => new Float64Array([1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1]);
function mul(a, b) {
  const o = new Float64Array(16);
  for (let i = 0; i < 4; i++) for (let j = 0; j < 4; j++) {
    o[i*4+j] = a[i*4]*b[j] + a[i*4+1]*b[4+j] + a[i*4+2]*b[8+j] + a[i*4+3]*b[12+j];
  }
  return o;
}
function Tm(x, y, z) { const m = I4(); m[3] = x; m[7] = y; m[11] = z; return m; }
function Rx(a) { const c = Math.cos(a), s = Math.sin(a); return new Float64Array([1,0,0,0, 0,c,-s,0, 0,s,c,0, 0,0,0,1]); }
function Ry(a) { const c = Math.cos(a), s = Math.sin(a); return new Float64Array([c,0,s,0, 0,1,0,0, -s,0,c,0, 0,0,0,1]); }
function Rz(a) { const c = Math.cos(a), s = Math.sin(a); return new Float64Array([c,-s,0,0, s,c,0,0, 0,0,1,0, 0,0,0,1]); }
function Sm(x, y, z) { return new Float64Array([x,0,0,0, 0,y,0,0, 0,0,z,0, 0,0,0,1]); }
function TR(t, r) { return mul(Tm(t[0], t[1], t[2]), mul(Rz(r[2]), mul(Ry(r[1]), Rx(r[0])))); }
function rigidInv(m) {
  const o = I4();
  for (let i = 0; i < 3; i++) for (let j = 0; j < 3; j++) o[i*4+j] = m[j*4+i];
  for (let i = 0; i < 3; i++) o[i*4+3] = -(o[i*4]*m[3] + o[i*4+1]*m[7] + o[i*4+2]*m[11]);
  return o;
}
const rad = d => d * Math.PI / 180;
// a rotation about z applied after the translation, before the node's own rotation: T * Rz * (T^-1 * L)
function preRotZ(L, a) {
  const R = Float64Array.from(L); R[3] = 0; R[7] = 0; R[11] = 0;
  return mul(Tm(L[3], L[7], L[11]), mul(Rz(a), R));
}
const MX = Rx(Math.PI / 2), MXI = rigidInv(MX);         // i3d y-up -> mesh z-up (+90 about x)

// rest pose of the skeleton
const restLocal = nodes.map(n => TR(n.t, n.r));
function fkWorld(localOf) {
  const W = new Array(NN);
  for (let i = 0; i < NN; i++) { const p = nodes[i].parent; W[i] = p >= 0 ? mul(W[p], localOf(i)) : localOf(i); }
  return W;
}
const Wrest = fkWorld(i => restLocal[i]);
const WrestInv = Wrest.map(rigidInv);
const restPos = nodes.map(n => n.p || [0, 0, 0]);

// ====================== meshes ======================
const mesh = {};
MESH_NAMES.forEach(n => {
  const m = DATA.meshes[n];
  mesh[n] = { pos0: Float32Array.from(m.pos), idx: Uint32Array.from(m.idx), jn: Uint8Array.from(m.jn), wt: Float32Array.from(m.wt), nv: m.pos.length / 3 };
});
const headIdx = [];                              // body vertices that mostly follow the head / jaw (for the nose tip)
{
  const b = mesh.body, h = idxOf.Head_M, j = idxOf.Jaw_M;
  for (let v = 0; v < b.nv; v++) {
    let w = 0;
    for (let k = 0; k < 4; k++) { const ji = b.jn[v*4+k]; if (ji === h || ji === j) w += b.wt[v*4+k]; }
    if (w > 0.2) headIdx.push(v);
  }
}

// skin around each eye: follows the eye when it is moved (the eyelid ring is already carried by the lid bones)
const socket = (() => {
  const b = mesh.body, isUnder = i => { for (let a = i; a >= 0; a = nodes[a].parent) if (a === idxOf.Head_M) return true; return false; };
  const head = nodes.map((n, i) => isUnder(i)), eyeLid = nodes.map(n => n.name.startsWith('Eye_') || n.name.startsWith('lid'));
  const cen = {};
  ['R', 'L'].forEach(sd => {
    const e = idxOf['Eye_' + sd], c = [0, 0, 0]; let n = 0;
    for (let v = 0; v < b.nv; v++) { let w = 0; for (let k = 0; k < 4; k++) if (b.jn[v*4+k] === e) w += b.wt[v*4+k]; if (w > 0.5) { for (let a = 0; a < 3; a++) c[a] += b.pos0[v*3+a]; n++; } }
    cen[sd] = c.map(x => x / n);
  });
  const list = [];                                // vertices within the widest reach (0.2 m) of an eye
  for (let v = 0; v < b.nv; v++) {
    let hw = 0, ew = 0;
    for (let k = 0; k < 4; k++) { const j = b.jn[v*4+k], w = b.wt[v*4+k]; if (head[j]) hw += w; if (eyeLid[j]) ew += w; }
    if (hw < 0.5) continue;
    for (const sd of ['R', 'L']) {
      const c = cen[sd], d = Math.hypot(b.pos0[v*3]-c[0], b.pos0[v*3+1]-c[1], b.pos0[v*3+2]-c[2]);
      if (d < 0.2) list.push({ v, side: sd, d, k: hw * (1 - Math.min(1, ew)) });
    }
  }
  return { list };
})();
function applySocket(P, pos, jointsNow, jointsBase) {
  if (!(P.socket > 0) || !(P.eye_down || P.eye_fwd || P.eye_out)) return;
  const dl = {};
  ['R', 'L'].forEach(sd => { const i = idxOf['Eye_' + sd]; dl[sd] = [0, 1, 2].map(a => jointsNow[i][a] - jointsBase[i][a]); });
  const R = P.socket, r0 = R * 0.35;
  for (const e of socket.list) {
    if (e.d >= R) continue;
    let t = e.d <= r0 ? 1 : 1 - (e.d - r0) / (R - r0); t = t * t * (3 - 2 * t);
    const f = t * e.k, d = dl[e.side];
    pos[e.v*3] += d[0] * f; pos[e.v*3+1] += d[1] * f; pos[e.v*3+2] += d[2] * f;
  }
}

// head top / bottom line: skin above the ear-base-to-nose chord moves with "top", skin below it with "bottom"
const headLine = (() => {
  const b = mesh.body, E = [0, 1, 2].map(a => (restPos[idxOf.ear1_R][a] + restPos[idxOf.ear1_L][a]) / 2);
  let ni = headIdx[0]; for (const v of headIdx) if (b.pos0[v*3+1] < b.pos0[ni*3+1]) ni = v;
  const N = [b.pos0[ni*3], b.pos0[ni*3+1], b.pos0[ni*3+2]], c = [N[0]-E[0], N[1]-E[1], N[2]-E[2]], cl = Math.hypot(c[0], c[1], c[2]), ch = c.map(x => x / cl);
  let up = [0, 0, 1]; const dp = up[0]*ch[0] + up[1]*ch[1] + up[2]*ch[2]; up = up.map((x, i) => x - dp * ch[i]); const ul = Math.hypot(up[0], up[1], up[2]); up = up.map(x => x / ul);
  const head = nodes.map((n, i) => { for (let a = i; a >= 0; a = nodes[a].parent) if (a === idxOf.Head_M) return true; return false; });
  const eyeLid = nodes.map(n => n.name.startsWith('Eye_') || n.name.startsWith('lid'));
  const eyeC = {};
  ['R', 'L'].forEach(sd => { const e = idxOf['Eye_' + sd]; eyeC[sd] = restPos[e]; });
  const sOf = (x, y, z) => (x - E[0]) * up[0] + (y - E[1]) * up[1] + (z - E[2]) * up[2];
  const list = [];
  for (let v = 0; v < b.nv; v++) {
    let hw = 0, ew = 0, side = 'R';
    for (let k = 0; k < 4; k++) { const j = b.jn[v*4+k], w = b.wt[v*4+k]; if (head[j]) hw += w; if (eyeLid[j]) ew += w; }
    if (hw < 0.02) continue;
    let s = sOf(b.pos0[v*3], b.pos0[v*3+1], b.pos0[v*3+2]);
    if (ew > 0.5) { const e = b.pos0[v*3] < 0 ? eyeC.R : eyeC.L; s = sOf(e[0], e[1], e[2]); }   // eyeball and lids move as one piece
    list.push({ v, s, hw: Math.min(1, hw) });
  }
  return { list, up };
})();
function applyHeadLine(P, pos, Db) {
  if (!P.head_top && !P.head_bot) return 0;
  const d = Db[idxOf.Head_M], u = headLine.up;
  let x = d[0]*u[0] + d[1]*u[1] + d[2]*u[2], y = d[4]*u[0] + d[5]*u[1] + d[6]*u[2], z = d[8]*u[0] + d[9]*u[1] + d[10]*u[2];
  const l = Math.hypot(x, y, z); x /= l; y /= l; z /= l;
  let maxZ = -Infinity;
  for (const e of headLine.list) {
    const t = Math.max(-1, Math.min(1, e.s / 0.04)), up = t > 0, a = Math.abs(t), f = a * a * (3 - 2 * a);
    const amt = (up ? P.head_top : P.head_bot) * f * e.hw;
    pos[e.v*3] += x * amt; pos[e.v*3+1] += y * amt; pos[e.v*3+2] += z * amt;
    if (pos[e.v*3+2] > maxZ) maxZ = pos[e.v*3+2];
  }
  return maxZ;
}

// ====================== parameters ======================
// [key, label, min, max, step, adult default, group, unit]
const PARAMS = [
  ['B',         'Overall size',        0.40, 1.10, 0.01, 1,     'Body',  'x'],
  ['torso',     'Torso',               0.80, 1.10, 0.01, 1,     'Body',  'x'],
  ['rump',      'Rump (hindquarter) size', 0.60, 1.20, 0.01, 1, 'Body',  'x'],
  ['neck_len',  'Neck length',         0.60, 1.80, 0.01, 1,     'Neck',  'x'],
  ['neck_th',   'Neck thickness',      0.60, 1.30, 0.01, 1,     'Neck',  'x'],
  ['head_d',    'Head depth',          0.70, 1.70, 0.01, 1,     'Head',  'x'],
  ['head_l',    'Head length',         0.40, 1.50, 0.01, 1,     'Head',  'x'],
  ['head_top',  'Top line (forehead) up/down', -0.05, 0.08, 0.002, 0, 'Head', 'm'],
  ['head_bot',  'Bottom line (jaw) up/down',  -0.08, 0.05, 0.002, 0, 'Head', 'm'],
  ['head_w',    'Head width',          0.70, 1.70, 0.01, 1,     'Head',  'x'],
  ['jaw_d',     'Jaw depth (cheek)',   0.70, 1.30, 0.01, 1,     'Head',  'x'],
  ['jaw_l',     'Jaw length',          0.70, 1.30, 0.01, 1,     'Head',  'x'],
  ['jaw_w',     'Jaw width',           0.70, 1.30, 0.01, 1,     'Head',  'x'],
  ['lipw',      'Nose width',          0.90, 1.40, 0.01, 1,     'Head',  'x'],
  ['head_pitch','Nose forward',        -10,  40,   0.5,  0,     'Head',  '°'],
  ['ear',       'Ear size',            0.50, 2.20, 0.01, 1,     'Ears',  'x'],
  ['ear_tilt',  'Ear tilt (− = upright)', -60, 30, 1,    0,     'Ears',  '°'],
  ['ear_fwd',   'Ears forward',        -0.02, 0.06, 0.002, 0,   'Ears',  'm'],
  ['ear_in',    'Ears closer together', -0.01, 0.04, 0.002, 0,  'Ears',  'm'],
  ['eyes',      'Eye size',            0.80, 2.20, 0.01, 1,     'Eyes',  'x'],
  ['eye_down',  'Eyes down',           -0.02, 0.07, 0.002, 0,   'Eyes',  'm'],
  ['eye_fwd',   'Eyes forward',        -0.02, 0.04, 0.002, 0,   'Eyes',  'm'],
  ['eye_out',   'Eyes outward',        -0.01, 0.03, 0.002, 0,   'Eyes',  'm'],
  ['socket',    'Socket reach (skin follows)', 0, 0.20, 0.005, 0.12, 'Eyes', 'm'],
  ['leg_len',   'Leg length',          0.80, 1.80, 0.01, 1,     'Legs & tail', 'x'],
  ['leg_th',    'Leg thickness',       0.50, 1.60, 0.01, 1,     'Legs & tail', 'x'],
  ['hip_th',    'Hind thigh thickness',   0.50, 1.30, 0.01, 1,  'Legs & tail', 'x'],
  ['hoof',      'Hooves',              0.50, 1.60, 0.01, 1,     'Legs & tail', 'x'],
  ['tail',      'Tail',                0.40, 1.30, 0.01, 1,     'Legs & tail', 'x'],
];
const DEF = {}; PARAMS.forEach(p => { DEF[p[0]] = p[5]; });
function mk(o) { return Object.assign({}, DEF, o); }
function adultHead(k) { return mk({ head_d: k, head_l: k, head_w: k, eyes: 1 + (k - 1) * 0.5, ear: 1 + (k - 1) * 0.5 }); }
const A_BODY = { B: 0.65, torso: 0.93, neck_len: 0.88, neck_th: 0.88, ear: 1.15, eyes: 1.12, leg_len: 1.30, leg_th: 0.85, hoof: 0.88, tail: 0.85 };
const Q = Object.assign({}, A_BODY, { head_d: 1.5, head_l: 1.25, head_w: 1.5, jaw_l: 0.92, ear: 1.9, neck_th: 0.98 });
const PRESETS = [
  ['adult',     'Game adult',       'as it ships',           mk({})],
  ['adult15',   'Adult, bigger head', 'head +15%',            adultHead(1.15)],
  ['foal',      'Foal (current)',   'uniform head, ears up',  mk({ B: 0.62, torso: 0.93, neck_len: 1.2, neck_th: 0.95, head_d: 1.2, head_l: 1.2, head_w: 1.2, ear: 1.12, ear_tilt: -30, ear_fwd: 0.02, eyes: 1.3, eye_down: 0.015, leg_len: 1.3, leg_th: 1.25, rump: 0.75, hip_th: 0.85, hoof: 1.2, tail: 0.85 })],
  ['q3',        'Q3',               'big head, sturdy legs', mk(Object.assign({}, Q, { ear: 1.7, leg_th: 1.25, rump: 0.75, hip_th: 0.85, hoof: 1.2 }))],
  ['n4',        'N4',               'long neck, small body', mk(Object.assign({}, Q, { B: 0.54, head_d: 1.4, head_l: 1.3, head_w: 0.95, neck_len: 1.45, neck_th: 0.82, ear: 1.9 }))],
  ['month1',    '1 month',          '~64% of adult',         mk({ B: 0.50, torso: 0.95, neck_len: 1.45, neck_th: 0.82, head_d: 1.3, head_l: 1.3, head_w: 1.2, ear: 1.1, ear_tilt: -30, eyes: 1.4, eye_down: 0.02, leg_len: 1.5, leg_th: 1.15, rump: 0.75, hip_th: 0.85, hoof: 1.1, tail: 0.9 })],
];
// reference values from the Blender runs (idle pose, ground to top of the head), used by the self-test
const LEGACY = [
  ['adult', mk({}), 2.28],
  ['adult head +15%', adultHead(1.15), 2.29],
  ['Q3 (old legs)', mk(Object.assign({}, Q, { ear: 1.7 })), 1.74],
  ['N4 (old legs)', mk(Object.assign({}, Q, { B: 0.54, head_d: 1.4, head_l: 1.3, head_w: 0.95, neck_len: 1.45, neck_th: 0.82, ear: 1.9 })), 1.67],
];

// ====================== posing ======================
const HIPS = new Set(['frontHip_R', 'frontHip_L', 'backHip_R', 'backHip_L']);
const LOWER_BACK = new Set(['backKnee_R', 'backKnee_L', 'backAnkle_R', 'backAnkle_L', 'backFoot_R', 'backFoot_L', 'backAnkleCorner1_R', 'backAnkleCorner1_L', 'backKneeCorner1_R', 'backKneeCorner1_L']);
const TORSO = new Set(['RootPart1_M', 'Spine1_M', 'Chest_M', 'Spine1Part1_M', 'belly1_M']);
function localScales(P) {
  const B = P.B;
  const rule = name => {
    if (name === 'Root_M') { const r = B * P.rump; return [r, r, r]; }
    if (TORSO.has(name)) { const s = B * P.torso; return [s, s, s]; }
    if (name === 'Neck_M') return [B * P.neck_len, B * P.neck_th, B * P.neck_th];
    if (name === 'Head_M') return [B * P.head_d, B * P.head_l, B * P.head_w];
    if (name.startsWith('ear')) { const s = B * P.ear; return [s, s, s]; }
    if (name.startsWith('lipMid') || name.startsWith('lipCorner')) return [B * P.head_d, B * P.head_l, B * P.head_w * P.lipw];
    if (name === 'Jaw_M') return [B * P.head_d * P.jaw_d, B * P.head_l * P.jaw_l, B * P.head_w * P.jaw_w];
    if (name.startsWith('Eye_') || name.startsWith('lid')) { const s = B * P.eyes; return [s, s, s]; }
    if (name.startsWith('backHip')) return [B * P.leg_len, B * P.leg_th, B * P.leg_th];
    if (HIPS.has(name) || LOWER_BACK.has(name)) return [B * P.leg_len, B * P.leg_th, B * P.leg_th];
    if (name.includes('Toes') || name.startsWith('hoof')) { const s = B * P.hoof; return [s, s, s]; }
    if (name === 'Tail0_M') { const s = B * P.tail; return [s, s, s]; }
    return null;
  };
  const out = new Array(NN), cum = new Array(NN);
  for (let i = 0; i < NN; i++) {
    const p = nodes[i].parent, ps = p >= 0 ? cum[p] : [1, 1, 1];
    const S = rule(nodes[i].name) || ps;
    out[i] = [S[0] / ps[0], S[1] / ps[1], S[2] / ps[2]]; cum[i] = S;
  }
  return out;
}
// skinning matrices (mesh frame) for params P at a key of a clip (clip null = rest)
function skinMatrices(P, clip, key) {
  const sc = localScales(P);
  const tracks = clip ? DATA.clips[clip].tracks : null;
  const W = fkWorld(i => {
    let L;
    const tr = tracks && tracks[i];
    if (tr) { const k = tr[Math.min(key, tr.length - 1)]; L = TR([k[0], k[1], k[2]], [k[3], k[4], k[5]]); } else L = restLocal[i];
    const name = nodes[i].name;
    if (name === 'Head_M' && P.head_pitch) L = preRotZ(L, -rad(P.head_pitch));
    if (name.startsWith('ear')) {
      const t = P.ear_tilt + P.head_pitch;
      if (t) L = preRotZ(L, rad(t));
      if (P.ear_fwd) L = mul(Tm(0, P.ear_fwd, 0), L);
      if (P.ear_in) L = mul(Tm(0, 0, name.endsWith('_R') ? P.ear_in : -P.ear_in), L);
    }
    if (name.startsWith('Eye_') || name.startsWith('lid')) {
      if (P.eye_down || P.eye_fwd || P.eye_out) L = mul(Tm(-P.eye_down, P.eye_fwd, name.endsWith('_R') ? -P.eye_out : P.eye_out), L);
    }
    if (P.rump !== 1 && nodes[i].parent === idxOf.Root_M) { const k = 1 / P.rump; L = L.slice(); L[3] *= k; L[7] *= k; L[11] *= k; }   // keep hips, spine and tail where they were
    const s = sc[i];
    return (s[0] === 1 && s[1] === 1 && s[2] === 1) ? L : mul(L, Sm(s[0], s[1], s[2]));
  });
  if (P.hip_th !== 1) ['backHip_R', 'backHip_L'].forEach(n => { const i = idxOf[n]; W[i] = mul(W[i], Sm(1, P.hip_th, P.hip_th)); });   // thigh skin only: the leg below keeps its pose
  return W.map((w, i) => mul(MX, mul(mul(w, WrestInv[i]), MXI)));
}
function skin(P, clip, key, want) {
  const Db = skinMatrices(P, clip, key);
  const out = {}, names = want || MESH_NAMES;
  let minZ = Infinity, maxZ = -Infinity;
  names.forEach(name => {
    const m = mesh[name], pos = new Float32Array(m.nv * 3);
    for (let v = 0; v < m.nv; v++) {
      const x = m.pos0[v*3], y = m.pos0[v*3+1], z = m.pos0[v*3+2];
      let ox = 0, oy = 0, oz = 0;
      for (let k = 0; k < 4; k++) {
        const w = m.wt[v*4+k]; if (w === 0) continue;
        const d = Db[m.jn[v*4+k]];
        ox += w * (d[0]*x + d[1]*y + d[2]*z + d[3]);
        oy += w * (d[4]*x + d[5]*y + d[6]*z + d[7]);
        oz += w * (d[8]*x + d[9]*y + d[10]*z + d[11]);
      }
      pos[v*3] = ox; pos[v*3+1] = oy; pos[v*3+2] = oz;
      if (name === 'body') { if (oz < minZ) minZ = oz; if (oz > maxZ) maxZ = oz; }
    }
    out[name] = pos;
  });
  if (out.body) { const mz = applyHeadLine(P, out.body, Db); if (mz > maxZ) maxZ = mz; }
  let jointsBase = null;
  if (out.body && P.socket > 0 && (P.eye_down || P.eye_fwd || P.eye_out)) {
    const D0 = skinMatrices(Object.assign({}, P, { eye_down: 0, eye_fwd: 0, eye_out: 0 }), clip, key);
    const jb = nodes.map((n, i) => { const d = D0[i], r = restPos[i]; return [d[0]*r[0]+d[1]*r[1]+d[2]*r[2]+d[3], d[4]*r[0]+d[5]*r[1]+d[6]*r[2]+d[7], d[8]*r[0]+d[9]*r[1]+d[10]*r[2]+d[11]]; });
    const jn = nodes.map((n, i) => { const d = Db[i], r = restPos[i]; return [d[0]*r[0]+d[1]*r[1]+d[2]*r[2]+d[3], d[4]*r[0]+d[5]*r[1]+d[6]*r[2]+d[7], d[8]*r[0]+d[9]*r[1]+d[10]*r[2]+d[11]]; });
    applySocket(P, out.body, jn, jb);
  }
  names.forEach(name => { const p = out[name]; for (let v = 2; v < p.length; v += 3) p[v] -= minZ; });   // ground
  const joints = nodes.map((n, i) => { const d = Db[i], r = restPos[i]; return [d[0]*r[0]+d[1]*r[1]+d[2]*r[2]+d[3], d[4]*r[0]+d[5]*r[1]+d[6]*r[2]+d[7], d[8]*r[0]+d[9]*r[1]+d[10]*r[2]+d[11] - minZ]; });
  return { pos: out, joints, height: maxZ - minZ, minZ };
}
function landmarks(res) {
  const j = res.joints, E = [0,1,2].map(a => (j[idxOf.ear1_R][a] + j[idxOf.ear1_L][a]) / 2), Y = [0,1,2].map(a => (j[idxOf.Eye_R][a] + j[idxOf.Eye_L][a]) / 2);
  const b = res.pos.body; let ni = headIdx[0];
  for (const v of headIdx) if (b[v*3+1] < b[ni*3+1]) ni = v;
  const N = [b[ni*3], b[ni*3+1], b[ni*3+2]];
  const sub = (a, c) => [a[0]-c[0], a[1]-c[1], a[2]-c[2]], len = a => Math.hypot(a[0], a[1], a[2]);
  const L = len(sub(N, E)), eyeFrac = len(sub(Y, E)) / L;
  const u = sub(E, Y), v2 = sub(N, Y), cosA = (u[0]*v2[0]+u[1]*v2[1]+u[2]*v2[2]) / (len(u) * len(v2));
  return { E, Y, N, chord: L, eyeFrac, angle: Math.acos(Math.max(-1, Math.min(1, cosA))) * 180 / Math.PI };
}

// ====================== state ======================
const state = { P: Object.assign({}, DEF), clip: 'rest', time: 0, speed: 1, preset: 'adult', view: 'side',
  show: { mane: true, saddle: false, reins: false, wire: false, ghost: true, dots: false, bones: false } };
const adultRef = { cache: {} };
function adultAt(clip, key) {
  const id = clip + ':' + key;
  if (!adultRef.cache[id]) { adultRef.cache = {}; adultRef.cache[id] = skin(DEF, clip === 'rest' ? null : clip, key, ['body']); }
  return adultRef.cache[id];
}
function keyFor() {
  if (state.clip === 'rest') return 0;
  const n = DATA.clips[state.clip].tracks[0] ? DATA.clips[state.clip].tracks[Object.keys(DATA.clips[state.clip].tracks)[0]].length : 1;
  return Math.floor(state.time * 30) % n;
}

// ====================== self-test (headless) ======================
function selfTest() {
  const lines = []; let ok = true;
  LEGACY.forEach(([name, P, want]) => {
    const h = skin(P, 'idle', 0, ['body']).height, pass = Math.abs(h - want) < 0.03;
    ok = ok && pass; lines.push((pass ? 'PASS ' : 'FAIL ') + name + ': height ' + h.toFixed(3) + ' m (Blender ' + want.toFixed(2) + ' m)');
  });
  const lm = landmarks(skin(DEF, null, 0));
  const pass2 = Math.abs(lm.chord - 0.527) < 0.02 && Math.abs(lm.eyeFrac - 0.30) < 0.03;
  ok = ok && pass2; lines.push((pass2 ? 'PASS ' : 'FAIL ') + 'adult landmarks: ear-nose ' + lm.chord.toFixed(3) + ' m, eye at ' + (lm.eyeFrac * 100).toFixed(0) + '%, angle ' + lm.angle.toFixed(0) + ' deg (Blender 0.527 m, 30%, 176 deg)');
  return { ok, text: lines.join('\n') };
}
if (/[?&]test=1/.test(location.search)) {
  const r = selfTest();
  document.getElementById('testout').textContent = 'SELFTEST ' + (r.ok ? 'OK' : 'FAILED') + '\n' + r.text;
  document.title = 'SELFTEST ' + (r.ok ? 'OK' : 'FAILED');
}

// ====================== URL state ======================
const q = new URLSearchParams(location.search);
function readUrl() {
  if (q.has('preset')) { const pr = PRESETS.find(p => p[0] === q.get('preset')); if (pr) state.P = Object.assign({}, pr[3]); }
  PARAMS.forEach(p => { if (q.has(p[0])) { const v = parseFloat(q.get(p[0])); if (!isNaN(v)) state.P[p[0]] = Math.max(p[2], Math.min(p[3], v)); } });
  if (q.has('pose') && ['rest', 'idle', 'walk'].includes(q.get('pose'))) state.clip = q.get('pose');
  if (q.has('view') && ['side', 'three', 'front', 'head'].includes(q.get('view'))) state.view = q.get('view');
  ['mane', 'saddle', 'reins', 'wire', 'ghost', 'dots', 'bones'].forEach(k => { if (q.has(k)) state.show[k] = q.get(k) === '1'; });
  if (q.has('preset')) state.preset = q.get('preset');
}
let urlTimer = 0;
function writeUrl() {
  clearTimeout(urlTimer);
  urlTimer = setTimeout(() => {
    const p = new URLSearchParams();
    PARAMS.forEach(d => { if (Math.abs(state.P[d[0]] - DEF[d[0]]) > 1e-9) p.set(d[0], String(+state.P[d[0]].toFixed(4))); });
    if (state.clip !== 'rest') p.set('pose', state.clip);
    if (state.view !== 'side') p.set('view', state.view);
    const dflt = { mane: true, saddle: false, reins: false, wire: false, ghost: true, dots: false, bones: false };
    Object.keys(dflt).forEach(k => { if (state.show[k] !== dflt[k]) p.set(k, state.show[k] ? '1' : '0'); });
    try { history.replaceState(null, '', p.toString() ? '?' + p.toString() : location.pathname); } catch (e) { /* file:// in some browsers */ }
  }, 150);
}
readUrl();

// ====================== three.js scene ======================
const wrap = document.getElementById('canvas-wrap');
let renderer = null, scene, camera, meshes = {}, ghostMesh, dotGroup, gridHelper, boneSets = [];
const BONE_NODES = nodes.map((n, i) => i).filter(i => !/^(jtsSkinWire|jnts_|lid|lip|tongue)/.test(nodes[i].name) && nodes[i].parent >= 0);
function makeBones(color) {
  const g = new THREE.BufferGeometry(); g.setAttribute('position', new THREE.BufferAttribute(new Float32Array(BONE_NODES.length * 6), 3).setUsage(THREE.DynamicDrawUsage));
  const lines = new THREE.LineSegments(g, new THREE.LineBasicMaterial({ color, depthTest: false, transparent: true, opacity: 0.95 })); lines.renderOrder = 5; lines.frustumCulled = false;
  const pg = new THREE.BufferGeometry(); pg.setAttribute('position', new THREE.BufferAttribute(new Float32Array(BONE_NODES.length * 3), 3).setUsage(THREE.DynamicDrawUsage));
  const pts = new THREE.Points(pg, new THREE.PointsMaterial({ color, size: 5, sizeAttenuation: false, depthTest: false })); pts.renderOrder = 6; pts.frustumCulled = false;
  const grp = new THREE.Group(); grp.add(lines); grp.add(pts); scene.add(grp); return { grp, lines, pts };
}
function setBones(set, joints) {
  const la = set.lines.geometry.getAttribute('position').array, pa = set.pts.geometry.getAttribute('position').array;
  BONE_NODES.forEach((i, k) => {
    const a = joints[nodes[i].parent], b = joints[i];
    la.set(a, k * 6); la.set(b, k * 6 + 3); pa.set(b, k * 3);
  });
  set.lines.geometry.getAttribute('position').needsUpdate = true; set.pts.geometry.getAttribute('position').needsUpdate = true;
}
const orbit = { az: 0, el: 0.12, dist: 5.2, target: [0, -0.55, 0.95] };
const VIEWS = {
  side:  { az: 0,    el: 0.10, dist: 5.2, target: [0, -0.55, 0.95] },
  three: { az: -0.75, el: 0.22, dist: 5.0, target: [0, -0.55, 0.95] },
  front: { az: -1.5708, el: 0.10, dist: 5.2, target: [0, -0.55, 0.95] },
  head:  { az: -0.6, el: 0.10, dist: 1.5, target: [0, -1.35, 1.55] },
};
function setView(name, keepTarget) { const v = VIEWS[name]; orbit.az = v.az; orbit.el = v.el; orbit.dist = v.dist; orbit.target = v.target.slice(); state.view = name; markView(); writeUrl(); }
function placeCamera() {
  const t = orbit.target, ce = Math.cos(orbit.el);
  camera.position.set(t[0] + orbit.dist * ce * Math.cos(orbit.az), t[1] + orbit.dist * ce * Math.sin(orbit.az), t[2] + orbit.dist * Math.sin(orbit.el));
  camera.lookAt(t[0], t[1], t[2]);
}
function makeMesh(name, color) {
  const m = mesh[name];
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.BufferAttribute(new Float32Array(m.pos0), 3).setUsage(THREE.DynamicDrawUsage));
  g.setIndex(new THREE.BufferAttribute(m.idx, 1));
  g.computeVertexNormals();
  const mat = new THREE.MeshStandardMaterial({ color, roughness: 0.9, metalness: 0.0, side: THREE.DoubleSide });
  const o = new THREE.Mesh(g, mat); o.frustumCulled = false; scene.add(o); return o;
}
function initScene() {
  try { renderer = new THREE.WebGLRenderer({ antialias: true, preserveDrawingBuffer: true }); } catch (e) { renderer = null; }
  if (!renderer) { document.getElementById('vpnote').textContent = 'WebGL is not available here'; return; }
  renderer.setPixelRatio(Math.min(2, window.devicePixelRatio || 1));
  wrap.appendChild(renderer.domElement);
  scene = new THREE.Scene(); scene.background = new THREE.Color(0x0D1214);
  camera = new THREE.PerspectiveCamera(32, 1, 0.05, 100); camera.up.set(0, 0, 1);
  scene.add(new THREE.AmbientLight(0xffffff, 0.42));
  const d1 = new THREE.DirectionalLight(0xffffff, 0.62); d1.position.set(4, -3, 6); scene.add(d1);
  const d2 = new THREE.DirectionalLight(0x6FA8A0, 0.35); d2.position.set(-4, 3, 2); scene.add(d2);
  gridHelper = new THREE.GridHelper(10, 20, 0x2A3336, 0x1A2225); gridHelper.rotation.x = Math.PI / 2; scene.add(gridHelper);
  meshes.body = makeMesh('body', 0xD3CEC3); meshes.maneTail = makeMesh('maneTail', 0x5B5047); meshes.saddle = makeMesh('saddle', 0x7A4B2B); meshes.reins = makeMesh('reins', 0x3A2A1F);
  const gg = new THREE.BufferGeometry(); gg.setAttribute('position', new THREE.BufferAttribute(new Float32Array(mesh.body.pos0), 3).setUsage(THREE.DynamicDrawUsage)); gg.setIndex(new THREE.BufferAttribute(mesh.body.idx, 1));
  ghostMesh = new THREE.Mesh(gg, new THREE.MeshBasicMaterial({ color: 0x6FA8A0, wireframe: true, transparent: true, opacity: 0.18, depthWrite: false })); ghostMesh.frustumCulled = false; scene.add(ghostMesh);
  boneSets = [makeBones(0xB8E6DF), makeBones(0xE8A25C)];
  dotGroup = new THREE.Group(); scene.add(dotGroup);
  [[0xE05A4A, 'N'], [0x4A78E0, 'E'], [0xE0D04A, 'Y']].forEach(c => { const s = new THREE.Mesh(new THREE.SphereGeometry(0.018, 12, 8), new THREE.MeshBasicMaterial({ color: c[0], depthTest: false })); s.name = c[1]; s.renderOrder = 10; dotGroup.add(s); });
  // orbit controls: left drag orbit, right drag / shift-drag pan, wheel zoom
  const el = renderer.domElement; let drag = null;
  el.addEventListener('contextmenu', e => e.preventDefault());
  el.addEventListener('pointerdown', e => { drag = { x: e.clientX, y: e.clientY, pan: e.button === 2 || e.shiftKey }; el.setPointerCapture(e.pointerId); });
  el.addEventListener('pointerup', () => { drag = null; });
  el.addEventListener('pointermove', e => {
    if (!drag) return;
    const dx = e.clientX - drag.x, dy = e.clientY - drag.y; drag.x = e.clientX; drag.y = e.clientY;
    if (drag.pan) {
      const s = orbit.dist * 0.0016, a = orbit.az;
      orbit.target[0] += (Math.sin(a) * dx) * s; orbit.target[1] += (-Math.cos(a) * dx) * s; orbit.target[2] += dy * s;
    } else { orbit.az -= dx * 0.008; orbit.el = Math.max(-0.2, Math.min(1.45, orbit.el + dy * 0.006)); }
    state.view = 'custom'; markView();
  });
  el.addEventListener('wheel', e => { e.preventDefault(); orbit.dist = Math.max(0.5, Math.min(14, orbit.dist * Math.exp(e.deltaY * 0.001))); state.view = 'custom'; markView(); }, { passive: false });
  function resize() { const w = wrap.clientWidth, h = wrap.clientHeight; if (!w || !h) return; renderer.setSize(w, h, false); camera.aspect = w / h; camera.updateProjectionMatrix(); }
  window.addEventListener('resize', resize); resize();
}

// ====================== UI ======================
const $ = id => document.getElementById(id);
function markView() { document.querySelectorAll('#vpui [data-view]').forEach(b => b.classList.toggle('on', b.dataset.view === state.view)); }
const fmt = (p, v) => p[7] === 'm' ? (v * 100).toFixed(1) + ' cm' : p[7] === '°' ? v.toFixed(0) + '°' : v.toFixed(2) + '×';
const sliderEls = {};
function buildSliders() {
  const host = $('sliders'); let group = null, body = null;
  PARAMS.forEach(p => {
    if (p[6] !== group) {
      group = p[6]; const d = document.createElement('details'); d.open = ['Body', 'Head', 'Neck'].includes(group);
      d.innerHTML = '<summary>' + group + '</summary><div class="body"></div>'; host.appendChild(d); body = d.querySelector('.body');
    }
    const f = document.createElement('div'); f.className = 'field';
    f.innerHTML = '<label><span>' + p[1] + '</span><span class="val"></span></label><input type="range" min="' + p[2] + '" max="' + p[3] + '" step="' + p[4] + '">';
    const inp = f.querySelector('input'), val = f.querySelector('.val');
    inp.addEventListener('input', () => { state.P[p[0]] = parseFloat(inp.value); state.preset = ''; refreshUi(); dirty = true; writeUrl(); });
    inp.addEventListener('dblclick', () => { state.P[p[0]] = DEF[p[0]]; refreshUi(); dirty = true; writeUrl(); });
    body.appendChild(f); sliderEls[p[0]] = { inp, val, def: p };
  });
}
function refreshUi() {
  PARAMS.forEach(p => { const s = sliderEls[p[0]], v = state.P[p[0]]; s.inp.value = v; s.val.textContent = fmt(p, v); s.val.classList.toggle('changed', Math.abs(v - DEF[p[0]]) > 1e-9); });
  document.querySelectorAll('#presets .chip').forEach(c => c.classList.toggle('active', c.dataset.id === state.preset));
  document.querySelectorAll('#poses [data-clip]').forEach(b => b.classList.toggle('on', b.dataset.clip === state.clip));
  document.querySelectorAll('#toggles input').forEach(i => { i.checked = !!state.show[i.dataset.k]; });
}
function buildPresets() {
  const host = $('presets');
  PRESETS.forEach(p => {
    const b = document.createElement('button'); b.className = 'chip'; b.dataset.id = p[0]; b.innerHTML = p[1] + '<span class="sub">' + p[2] + '</span>';
    b.addEventListener('click', () => { state.P = Object.assign({}, p[3]); state.preset = p[0]; refreshUi(); dirty = true; writeUrl(); });
    host.appendChild(b);
  });
}
function buildToggles() {
  const host = $('toggles');
  [['mane', 'Mane and tail'], ['saddle', 'Saddle'], ['reins', 'Reins and bridle'], ['wire', 'Wireframe'], ['ghost', 'Ghost of the game adult'], ['dots', 'Ear base / eye / nose tip'], ['bones', 'Bones (adult teal, foal orange)']].forEach(t => {
    const l = document.createElement('label'); l.innerHTML = '<input type="checkbox" data-k="' + t[0] + '"> ' + t[1];
    l.querySelector('input').addEventListener('change', e => { state.show[t[0]] = e.target.checked; applyShow(); dirty = true; writeUrl(); });
    host.appendChild(l);
  });
}
function applyShow() {
  if (!renderer) return;
  meshes.maneTail.visible = state.show.mane; meshes.saddle.visible = state.show.saddle; meshes.reins.visible = state.show.reins;
  ['body', 'maneTail', 'saddle', 'reins'].forEach(n => { meshes[n].material.wireframe = state.show.wire; });
  ghostMesh.visible = state.show.ghost; dotGroup.visible = state.show.dots; boneSets.forEach(b => { b.grp.visible = state.show.bones; });
}
function setStats(res, lm) {
  const pct = (res.height / 2.28 * 100).toFixed(0);
  $('stats').innerHTML =
    '<div class="stat"><span>height (ground to top of head)</span><b>' + res.height.toFixed(2) + ' m</b></div>' +
    '<div class="stat"><span>of the game adult (2.28 m)</span><b>' + pct + '%</b></div>' +
    '<div class="stat"><span>ear base to nose tip</span><b>' + (lm.chord * 100).toFixed(0) + ' cm</b></div>' +
    '<div class="stat"><span>eye position, ear to nose</span><b>' + (lm.eyeFrac * 100).toFixed(0) + '%</b></div>' +
    '<div class="stat"><span>angle ear / eye / nose</span><b>' + lm.angle.toFixed(0) + '°</b></div>';
}

// ====================== frame loop ======================
let dirty = true, last = performance.now();
function update() {
  const key = keyFor();
  const res = skin(state.P, state.clip === 'rest' ? null : state.clip, key);
  if (renderer) {
    ['body', 'maneTail', 'saddle', 'reins'].forEach(n => {
      const g = meshes[n].geometry, a = g.getAttribute('position'); a.array.set(res.pos[n]); a.needsUpdate = true; g.computeVertexNormals();
    });
    const gh = adultAt(state.clip, key), ga = ghostMesh.geometry.getAttribute('position'); ga.array.set(gh.pos.body); ga.needsUpdate = true;
    if (state.show.bones) { setBones(boneSets[0], gh.joints); setBones(boneSets[1], res.joints); }
  }
  const lm = landmarks(res);
  if (renderer) { dotGroup.children.forEach(s => { const p = s.name === 'N' ? lm.N : s.name === 'E' ? lm.E : lm.Y; s.position.set(p[0] + 0.12, p[1], p[2]); }); }
  setStats(res, lm);
  current = res; curLm = lm;
}
let current = null, curLm = null;
function frame(now) {
  const dt = Math.min(0.1, (now - last) / 1000); last = now;
  if (state.clip !== 'rest') { state.time += dt * state.speed; dirty = true; }
  if (dirty) { update(); dirty = false; }
  if (renderer) {
    if (state.view === 'head' && curLm) {                                  // the head view follows the head, whatever its size or pose
      orbit.target = [(curLm.E[0] + curLm.N[0]) / 2, (curLm.E[1] + curLm.N[1]) / 2, (curLm.E[2] + curLm.N[2]) / 2 - 0.02];
      orbit.dist = Math.max(0.55, curLm.chord * 3.4);
    }
    placeCamera(); renderer.render(scene, camera);
  }
  requestAnimationFrame(frame);
}

// ====================== export ======================
function download(name, text, type) {
  const a = document.createElement('a'); a.download = name; a.href = URL.createObjectURL(new Blob([text], { type: type || 'text/plain' })); document.body.appendChild(a); a.click(); setTimeout(() => { URL.revokeObjectURL(a.href); a.remove(); }, 500);
}
function copy(text, btn, done) {
  const finish = () => { const o = btn.textContent; btn.textContent = done; setTimeout(() => { btn.textContent = o; }, 1400); };
  if (navigator.clipboard && navigator.clipboard.writeText) navigator.clipboard.writeText(text).then(finish, () => { window.prompt('Copy:', text); });
  else window.prompt('Copy:', text);
}
function exportObj() {
  if (!current) return;
  const lines = ['# foal-scale export (y up, metres)'], vis = { body: true, maneTail: state.show.mane, saddle: state.show.saddle, reins: state.show.reins };
  let off = 1;
  MESH_NAMES.forEach(n => {
    if (!vis[n]) return; const p = current.pos[n], m = mesh[n];
    lines.push('o ' + n);
    for (let v = 0; v < m.nv; v++) lines.push('v ' + p[v*3].toFixed(5) + ' ' + p[v*3+2].toFixed(5) + ' ' + (-p[v*3+1]).toFixed(5));
    for (let t = 0; t < m.idx.length; t += 3) lines.push('f ' + (m.idx[t] + off) + ' ' + (m.idx[t+1] + off) + ' ' + (m.idx[t+2] + off));
    off += m.nv;
  });
  download('foal.obj', lines.join('\n') + '\n');
}

// ====================== wire up ======================
buildPresets(); buildSliders(); buildToggles();
initScene(); applyShow(); setView(state.view); refreshUi(); markView();
document.querySelectorAll('#vpui [data-view]').forEach(b => b.addEventListener('click', () => setView(b.dataset.view)));
$('resetView').addEventListener('click', () => setView('side'));
document.querySelectorAll('#poses [data-clip]').forEach(b => b.addEventListener('click', () => { state.clip = b.dataset.clip; state.time = 0; refreshUi(); dirty = true; writeUrl(); }));
$('speed').addEventListener('input', e => { state.speed = parseFloat(e.target.value); $('speedv').textContent = state.speed.toFixed(1) + 'x'; });
$('resetAll').addEventListener('click', () => { state.P = Object.assign({}, DEF); state.preset = 'adult'; refreshUi(); dirty = true; writeUrl(); });
$('copyLink').addEventListener('click', e => { clearTimeout(urlTimer); const p = new URLSearchParams(); PARAMS.forEach(d => { if (Math.abs(state.P[d[0]] - DEF[d[0]]) > 1e-9) p.set(d[0], String(+state.P[d[0]].toFixed(4))); }); if (state.clip !== 'rest') p.set('pose', state.clip); if (state.view !== 'side' && state.view !== 'custom') p.set('view', state.view); copy(location.href.split('?')[0] + (p.toString() ? '?' + p.toString() : ''), e.target, 'Copied'); });
$('copyJson').addEventListener('click', e => { const o = {}; PARAMS.forEach(d => { o[d[0]] = +state.P[d[0]].toFixed(4); }); copy(JSON.stringify(o), e.target, 'Copied'); });
$('exportObj').addEventListener('click', exportObj);
$('exportPng').addEventListener('click', () => { if (!renderer) return; renderer.render(scene, camera); const a = document.createElement('a'); a.download = 'foal.png'; a.href = renderer.domElement.toDataURL('image/png'); a.click(); });
window.__foal = { state, skin, landmarks, selfTest, PRESETS, DEF };
requestAnimationFrame(frame);
})();

