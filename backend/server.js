// Unique Health clone - standalone backend (no external services).
// Node 22+ (built-in node:sqlite) + ws. Run: npm start  -> http://localhost:3000
import http from 'node:http';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { DatabaseSync } from 'node:sqlite';
import { WebSocketServer } from 'ws';
import QRCode from 'qrcode';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PORT = Number(process.env.PORT || 3000);
const SECRET = process.env.SECRET || 'dev-secret-change-me';
const DB_FILE = process.env.DB_FILE || path.join(__dirname, 'data.db');

export const db = new DatabaseSync(DB_FILE);
db.exec(`
PRAGMA journal_mode=WAL;
CREATE TABLE IF NOT EXISTS users(id INTEGER PRIMARY KEY, email TEXT UNIQUE, pw_hash TEXT, salt TEXT, nickname TEXT, created INTEGER);
CREATE TABLE IF NOT EXISTS settings(user_id INTEGER PRIMARY KEY, json TEXT);
CREATE TABLE IF NOT EXISTS members(id INTEGER PRIMARY KEY, owner_id INTEGER, name TEXT, gender INTEGER, birthday TEXT, height REAL, avatar TEXT, is_self INTEGER DEFAULT 0, athlete INTEGER DEFAULT 0);
CREATE TABLE IF NOT EXISTS devices(id INTEGER PRIMARY KEY, owner_id INTEGER, mac TEXT, name TEXT, custom_name TEXT, kind TEXT, unit TEXT DEFAULT 'kg', bound INTEGER);
CREATE TABLE IF NOT EXISTS device_shares(device_id INTEGER, user_id INTEGER, PRIMARY KEY(device_id,user_id));
CREATE TABLE IF NOT EXISTS body_data(id INTEGER PRIMARY KEY, owner_id INTEGER, member_id INTEGER, device_id INTEGER, weight REAL, impedance REAL, metrics TEXT, source TEXT, ts INTEGER);
CREATE TABLE IF NOT EXISTS body_share(id INTEGER PRIMARY KEY, owner_id INTEGER, viewer_id INTEGER, member_id INTEGER, UNIQUE(owner_id,viewer_id,member_id));
CREATE TABLE IF NOT EXISTS food_records(id INTEGER PRIMARY KEY, user_id INTEGER, member_id INTEGER, name TEXT, grams REAL, kcal REAL, protein REAL, fat REAL, carb REAL, meal TEXT, ts INTEGER);
CREATE TABLE IF NOT EXISTS food_bank(id INTEGER PRIMARY KEY, name TEXT, kcal REAL, protein REAL, fat REAL, carb REAL, icon TEXT);
CREATE TABLE IF NOT EXISTS goals(member_id INTEGER PRIMARY KEY, owner_id INTEGER, type TEXT, start_value REAL, target REAL, target_date INTEGER, created INTEGER);
CREATE TABLE IF NOT EXISTS messages(id INTEGER PRIMARY KEY, user_id INTEGER, kind TEXT, title TEXT, body TEXT, ts INTEGER, read INTEGER DEFAULT 0, dedupe TEXT, UNIQUE(user_id, dedupe));
CREATE TABLE IF NOT EXISTS brews(id INTEGER PRIMARY KEY, user_id INTEGER, name TEXT, dose REAL, water REAL, seconds REAL, rating INTEGER, notes TEXT, ts INTEGER);
CREATE TABLE IF NOT EXISTS barcodes(code TEXT PRIMARY KEY, food_name TEXT);
CREATE TABLE IF NOT EXISTS codes(email TEXT PRIMARY KEY, code TEXT, exp INTEGER);
`);

// ---------- helpers ----------
const now = () => Date.now();
const b64 = (b) => Buffer.from(b).toString('base64url');
function sign(payload) {
  const body = b64(JSON.stringify(payload));
  const sig = crypto.createHmac('sha256', SECRET).update(body).digest('base64url');
  return `${body}.${sig}`;
}
function verify(token) {
  if (!token) return null;
  const [body, sig] = token.split('.');
  if (!body || !sig) return null;
  const exp = crypto.createHmac('sha256', SECRET).update(body).digest('base64url');
  if (sig.length !== exp.length || !crypto.timingSafeEqual(Buffer.from(sig), Buffer.from(exp))) return null;
  try {
    const p = JSON.parse(Buffer.from(body, 'base64url').toString());
    return p.exp > now() ? p : null;
  } catch { return null; }
}
const hashPw = (pw, salt) => crypto.scryptSync(pw, salt, 32).toString('hex');
const tokens = (uid) => ({
  accessToken: sign({ uid, t: 'a', exp: now() + 2 * 3600e3 }),
  refreshToken: sign({ uid, t: 'r', exp: now() + 30 * 86400e3 }),
});
class ApiError extends Error { constructor(msg, code = 1, http = 200) { super(msg); this.code = code; this.http = http; } }
const ok = (data = null) => ({ code: 0, msg: 'ok', data });
const q = (sql, ...a) => db.prepare(sql).all(...a);
const q1 = (sql, ...a) => db.prepare(sql).get(...a);
const run = (sql, ...a) => db.prepare(sql).run(...a);
// client_id makes offline replays idempotent (a retried create returns the existing row)
for (const t of ['body_data', 'food_records']) {
  if (!q1(`SELECT 1 x FROM pragma_table_info('${t}') WHERE name='client_id'`)) db.exec(`ALTER TABLE ${t} ADD COLUMN client_id TEXT`);
}

function userView(u) { return { id: Number(u.id), email: u.email, nickname: u.nickname }; }
function memberView(m) {
  return { id: Number(m.id), name: m.name, gender: Number(m.gender), birthday: m.birthday, height: m.height, avatar: m.avatar, isSelf: !!m.is_self, athlete: !!m.athlete };
}
function deviceView(d, shared = false) {
  return { id: Number(d.id), mac: d.mac, name: d.name, customName: d.custom_name || d.name, kind: d.kind, unit: d.unit, shared };
}
function dataView(r) {
  return { id: Number(r.id), ownerId: Number(r.owner_id), memberId: r.member_id == null ? null : Number(r.member_id), deviceId: r.device_id == null ? null : Number(r.device_id), weight: r.weight, impedance: r.impedance, metrics: JSON.parse(r.metrics || '{}'), source: r.source, ts: Number(r.ts) };
}
function foodView(r) {
  return { id: Number(r.id), memberId: r.member_id == null ? null : Number(r.member_id), name: r.name, grams: r.grams, kcal: r.kcal, protein: r.protein, fat: r.fat, carb: r.carb, meal: r.meal, ts: Number(r.ts) };
}

// ---------- seed ----------
const FOODS = [
  ['Apple', 52, 0.3, 0.2, 14, '🍎'], ['Banana', 89, 1.1, 0.3, 23, '🍌'], ['Orange', 47, 0.9, 0.1, 12, '🍊'], ['Grapes', 69, 0.7, 0.2, 18, '🍇'],
  ['Strawberry', 32, 0.7, 0.3, 8, '🍓'], ['Watermelon', 30, 0.6, 0.2, 8, '🍉'], ['Tomato', 18, 0.9, 0.2, 3.9, '🍅'], ['Carrot', 41, 0.9, 0.2, 10, '🥕'],
  ['Broccoli', 34, 2.8, 0.4, 7, '🥦'], ['Potato', 77, 2, 0.1, 17, '🥔'], ['Corn', 86, 3.3, 1.4, 19, '🌽'], ['White Rice (cooked)', 130, 2.7, 0.3, 28, '🍚'],
  ['Bread', 265, 9, 3.2, 49, '🍞'], ['Pasta (cooked)', 158, 5.8, 0.9, 31, '🍝'], ['Egg', 155, 13, 11, 1.1, '🥚'], ['Chicken Breast', 165, 31, 3.6, 0, '🍗'],
  ['Beef', 250, 26, 15, 0, '🥩'], ['Salmon', 208, 20, 13, 0, '🐟'], ['Milk', 42, 3.4, 1, 5, '🥛'], ['Cheese', 402, 25, 33, 1.3, '🧀'],
  ['Yogurt', 59, 10, 0.4, 3.6, '🥣'], ['Almonds', 579, 21, 50, 22, '🥜'], ['Avocado', 160, 2, 15, 9, '🥑'], ['Oats', 389, 17, 7, 66, '🥣'],
  ['Pizza', 266, 11, 10, 33, '🍕'], ['Hamburger', 295, 17, 14, 24, '🍔'], ['Fries', 312, 3.4, 15, 41, '🍟'], ['Chocolate', 546, 5, 31, 61, '🍫'],
  ['Coffee (black)', 2, 0.3, 0, 0, '☕'], ['Olive Oil', 884, 0, 100, 0, '🫒'],
];
if (q1('SELECT COUNT(*) c FROM food_bank').c === 0) {
  const st = db.prepare('INSERT INTO food_bank(name,kcal,protein,fat,carb,icon) VALUES(?,?,?,?,?,?)');
  FOODS.forEach((f) => st.run(...f));
}
// demo barcodes (EAN-13 style) -> food bank names, used by the barcode-scan feature
const BARCODES = [['5000000000017', 'Apple'], ['5000000000024', 'Banana'], ['5000000000031', 'Egg'], ['5000000000048', 'Milk'], ['5000000000055', 'Yogurt'], ['5000000000062', 'Bread'], ['5000000000079', 'Oats'], ['5000000000086', 'Almonds'], ['5000000000093', 'Chocolate'], ['5000000000109', 'Pizza'], ['5000000000116', 'Cheese'], ['5000000000123', 'Chicken Breast']];
for (const [c, n] of BARCODES) db.prepare('INSERT OR IGNORE INTO barcodes(code, food_name) VALUES(?,?)').run(c, n);
function createUser(email, password, nickname) {
  const salt = crypto.randomBytes(16).toString('hex');
  const r = run('INSERT INTO users(email,pw_hash,salt,nickname,created) VALUES(?,?,?,?,?)', email, hashPw(password, salt), salt, nickname || email.split('@')[0], now());
  const uid = Number(r.lastInsertRowid);
  run('INSERT INTO members(owner_id,name,gender,birthday,height,avatar,is_self) VALUES(?,?,?,?,?,?,1)', uid, nickname || email.split('@')[0], 1, '1995-01-01', 170, '🙂');
  run('INSERT INTO settings(user_id,json) VALUES(?,?)', uid, JSON.stringify({ unit: 'kg', darkMode: false }));
  return uid;
}

// ---------- body composition ----------
// Published equations (see README "Body composition" for references and limits):
//  * Fat-free mass / total body water from impedance: Sun et al., Am J Clin Nutr 2003;77:331 (hand-to-foot BIA, DXA/4C reference)
//  * Skeletal muscle mass from impedance: Janssen et al., J Appl Physiol 2000;89:465 (MRI reference)
//  * Without usable impedance: body fat from BMI (Deurenberg et al., Br J Nutr 1991) and total body water (Watson et al., Am J Clin Nutr 1980)
//  * BMR: Mifflin-St Jeor 1990
// Bone mass, protein, visceral fat, subcutaneous fat, body age and the score are heuristic estimates (no validated BIA equation exists).
// Caveat: Sun/Janssen were validated on hand-to-foot BIA; foot-to-foot scale impedance is an approximation of it.
export const METHOD = { BIA: 1, BMI: 2 };
export function computeMetrics(weight, impedance, height, age, gender, athlete = false) {
  const w = weight, h = height || 170, a = age || 30, male = gender === 1, sex = male ? 1 : 0;
  const bmi = w / ((h / 100) ** 2);
  const useBia = impedance >= 150 && impedance <= 1500 && a >= 18;
  let ffm, tbw, smm;
  if (useBia) {
    const hz = (h * h) / impedance;
    ffm = male ? -10.68 + 0.65 * hz + 0.26 * w + 0.02 * impedance : -9.53 + 0.69 * hz + 0.17 * w + 0.02 * impedance;
    tbw = male ? 1.20 + 0.45 * hz + 0.18 * w : 3.75 + 0.45 * hz + 0.11 * w;
    smm = 0.401 * hz + 3.825 * sex - 0.071 * a + 5.102;
  } else {
    const bf0 = a >= 18 ? 1.20 * bmi + 0.23 * a - 10.8 * sex - 5.4 : 1.51 * bmi - 0.70 * a - 3.6 * sex + 1.4;
    ffm = w * (1 - clamp(bf0, 3, 60) / 100);
    tbw = male ? 2.447 - 0.09156 * a + 0.1074 * h + 0.3362 * w : -2.097 + 0.1069 * h + 0.2466 * w;
    smm = ffm * 0.52;
  }
  if (athlete) ffm += w * 0.03; // heuristic: athletes carry more lean mass than the equations assume
  ffm = clamp(ffm, w * 0.40, w * 0.97);
  tbw = clamp(tbw, ffm * 0.60, ffm * 0.80);
  smm = clamp(smm, ffm * 0.30, ffm * 0.65);
  const fatMass = w - ffm, bf = fatMass / w * 100;
  const bone = clamp(ffm * (male ? 0.045 : 0.040), 1.2, 4.5);
  const proteinKg = Math.max(ffm - tbw - bone, ffm * 0.10);
  const m = { method: useBia ? METHOD.BIA : METHOD.BMI, bmi: round(bmi, 1) };
  m.bodyFat = round(bf, 1);
  m.fatMass = round(fatMass, 1);
  m.leanMass = round(ffm, 1);
  m.muscleMass = round(smm, 1);
  m.muscleRate = round(smm / w * 100, 1);
  m.water = round(tbw / w * 100, 1);
  m.boneMass = round(bone, 1);
  m.protein = round(clamp(proteinKg / w * 100, 8, 25), 1);
  m.visceralFat = round(clamp(bmi * 0.55 + a * 0.08 - (male ? 8 : 9) + (bf - 20) * 0.15, 1, 30), 0);
  m.subcutaneousFat = round(clamp(bf * 0.85, 2, 55), 1);
  m.bmr = Math.round(10 * w + 6.25 * h - 5 * a + (male ? 5 : -161));
  m.bodyAge = clamp(Math.round(a + (bf - (male ? 18 : 28)) * 0.35 + (m.visceralFat - 7) * 0.3), 18, 80);
  m.idealWeight = round(22 * (h / 100) ** 2, 1);
  m.score = clamp(Math.round(100 - Math.abs(bmi - 22) * 2.2 - Math.max(0, bf - (male ? 20 : 30)) * 0.8 - Math.max(0, m.visceralFat - 9) * 1.5), 40, 100);
  return m;
}
const round = (v, d = 1) => Number(v.toFixed(d));
const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));
function ageOf(birthday) {
  if (!birthday) return 30;
  const b = new Date(birthday), n = new Date();
  let a = n.getFullYear() - b.getFullYear();
  if (n < new Date(n.getFullYear(), b.getMonth(), b.getDate())) a--;
  return a;
}

// ---------- in-app messages (the local stand-in for push notifications) ----------
function notify(uid, kind, title, body, dedupe) {
  try { run('INSERT INTO messages(user_id,kind,title,body,ts,dedupe) VALUES(?,?,?,?,?,?)', uid, kind, title, body, now(), dedupe || `${kind}:${now()}:${Math.random()}`); } catch { /* duplicate dedupe key */ }
}
function checkMilestones(uid, memberId) {
  const g = q1('SELECT * FROM goals WHERE member_id=?', memberId);
  const last = q1('SELECT * FROM body_data WHERE owner_id=? AND member_id=? ORDER BY ts DESC LIMIT 1', uid, memberId);
  if (g && last) {
    const cur = g.type === 'weight' ? last.weight : JSON.parse(last.metrics || '{}').bodyFat;
    if (cur != null && (g.target < g.start_value ? cur <= g.target : cur >= g.target)) {
      notify(uid, 'goal', 'Goal reached', `You reached your ${g.type === 'weight' ? 'weight' : 'body fat'} goal of ${g.target}${g.type === 'weight' ? ' kg' : '%'}. Great work!`, `goal:${memberId}:${g.created}`);
    }
  }
  const streak = weeklySummary(uid, memberId, new Date().setHours(0, 0, 0, 0)).streak;
  if ([7, 14, 30, 60, 100].includes(streak)) notify(uid, 'streak', `${streak}-day streak`, `You have weighed in ${streak} days in a row. Keep it going!`, `streak:${memberId}:${streak}:${new Date().toISOString().slice(0, 10)}`);
}
function weeklyDigest(uid) {
  const me = q1('SELECT * FROM members WHERE owner_id=? AND is_self=1', uid);
  if (!me) return;
  const d = new Date(); const week = `${d.getUTCFullYear()}-W${Math.floor((d - new Date(d.getUTCFullYear(), 0, 1)) / (7 * DAY_MS))}`;
  const sum = weeklySummary(uid, Number(me.id), new Date().setHours(0, 0, 0, 0));
  if (!sum.weighIns) return;
  const parts = [`${sum.weighIns} weigh-in${sum.weighIns === 1 ? '' : 's'}`];
  if (sum.avgWeight != null) parts.push(`average ${sum.avgWeight} kg`);
  if (sum.changeKg != null) parts.push(`change ${sum.changeKg > 0 ? '+' : ''}${sum.changeKg} kg`);
  notify(uid, 'weekly', 'Your weekly summary', parts.join(' · '), `weekly:${week}`);
}
const DAY_MS = 86400e3;

// ---------- routes ----------
const routes = {};
const route = (method, p, auth, fn) => { routes[`${method} ${p}`] = { auth, fn }; };
const need = (o, ...keys) => keys.forEach((k) => { if (o[k] === undefined || o[k] === null || o[k] === '') throw new ApiError(`${k} is required`); });
const myMember = (uid, id) => {
  const m = q1('SELECT * FROM members WHERE id=? AND owner_id=?', id, uid);
  if (!m) throw new ApiError('member not found', 404);
  return m;
};
const deviceAccess = (uid, id) => {
  const d = q1('SELECT * FROM devices WHERE id=?', id);
  if (!d) throw new ApiError('device not found', 404);
  if (d.owner_id !== uid && !q1('SELECT 1 x FROM device_shares WHERE device_id=? AND user_id=?', id, uid)) throw new ApiError('no permission', 403);
  return d;
};

// auth
route('POST', '/app/user/signUp', false, ({ body }) => {
  need(body, 'email', 'password');
  const email = String(body.email).trim().toLowerCase();
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) throw new ApiError('invalid email');
  if (String(body.password).length < 6) throw new ApiError('password too short (min 6)');
  if (q1('SELECT 1 x FROM users WHERE email=?', email)) throw new ApiError('email already registered');
  const uid = createUser(email, body.password, body.nickname);
  return ok({ ...tokens(uid), user: userView(q1('SELECT * FROM users WHERE id=?', uid)) });
});
route('POST', '/app/user/login', false, ({ body }) => {
  need(body, 'email', 'password');
  const u = q1('SELECT * FROM users WHERE email=?', String(body.email).trim().toLowerCase());
  if (!u || hashPw(body.password, u.salt) !== u.pw_hash) throw new ApiError('wrong email or password');
  return ok({ ...tokens(Number(u.id)), user: userView(u) });
});
route('POST', '/app/user/refreshToken', false, ({ body }) => {
  const p = verify(body.refreshToken);
  if (!p || p.t !== 'r') throw new ApiError('invalid refresh token', 401, 401);
  return ok(tokens(p.uid));
});
route('POST', '/app/user/logOut', true, () => ok());
route('POST', '/app/user/sendForgotPasswordEmail', false, ({ body }) => {
  need(body, 'email');
  const email = String(body.email).trim().toLowerCase();
  const code = String(Math.floor(100000 + Math.random() * 900000));
  run('INSERT OR REPLACE INTO codes(email,code,exp) VALUES(?,?,?)', email, code, now() + 10 * 60e3);
  // No email service: the code is returned so the app can show it (testing only).
  return ok({ devCode: q1('SELECT 1 x FROM users WHERE email=?', email) ? code : undefined });
});
route('POST', '/app/user/resetPassword', false, ({ body }) => {
  need(body, 'email', 'code', 'newPassword');
  const email = String(body.email).trim().toLowerCase();
  const c = q1('SELECT * FROM codes WHERE email=?', email);
  if (!c || c.code !== String(body.code) || c.exp < now()) throw new ApiError('invalid or expired code');
  if (String(body.newPassword).length < 6) throw new ApiError('password too short (min 6)');
  const salt = crypto.randomBytes(16).toString('hex');
  run('UPDATE users SET pw_hash=?, salt=? WHERE email=?', hashPw(body.newPassword, salt), salt, email);
  run('DELETE FROM codes WHERE email=?', email);
  return ok();
});
route('POST', '/app/user/updatePassword', true, ({ uid, body }) => {
  need(body, 'oldPassword', 'newPassword');
  const u = q1('SELECT * FROM users WHERE id=?', uid);
  if (hashPw(body.oldPassword, u.salt) !== u.pw_hash) throw new ApiError('old password is wrong');
  if (String(body.newPassword).length < 6) throw new ApiError('password too short (min 6)');
  const salt = crypto.randomBytes(16).toString('hex');
  run('UPDATE users SET pw_hash=?, salt=? WHERE id=?', hashPw(body.newPassword, salt), salt, uid);
  return ok();
});
route('GET', '/app/user', true, ({ uid }) => ok(userView(q1('SELECT * FROM users WHERE id=?', uid))));
route('POST', '/app/user/update', true, ({ uid, body }) => {
  if (body.nickname) run('UPDATE users SET nickname=? WHERE id=?', String(body.nickname), uid);
  return ok(userView(q1('SELECT * FROM users WHERE id=?', uid)));
});
route('POST', '/app/user/logOff', true, ({ uid, body }) => {
  need(body, 'password');
  const u = q1('SELECT * FROM users WHERE id=?', uid);
  if (hashPw(body.password, u.salt) !== u.pw_hash) throw new ApiError('wrong password');
  for (const t of ['members', 'devices', 'body_data', 'food_records', 'body_share']) run(`DELETE FROM ${t} WHERE ${t === 'food_records' ? 'user_id' : 'owner_id'}=?`, uid);
  run('DELETE FROM settings WHERE user_id=?', uid);
  run('DELETE FROM users WHERE id=?', uid);
  return ok();
});
route('GET', '/app/user/getSetting', true, ({ uid }) => ok(JSON.parse(q1('SELECT json FROM settings WHERE user_id=?', uid)?.json || '{}')));
route('POST', '/app/user/saveOrUpdateSetting', true, ({ uid, body }) => {
  const cur = JSON.parse(q1('SELECT json FROM settings WHERE user_id=?', uid)?.json || '{}');
  const next = { ...cur, ...body };
  run('INSERT OR REPLACE INTO settings(user_id,json) VALUES(?,?)', uid, JSON.stringify(next));
  return ok(next);
});

// members (family profiles)
route('GET', '/app/memberDevice/list', true, ({ uid }) => ok(q('SELECT * FROM members WHERE owner_id=? ORDER BY is_self DESC, id', uid).map(memberView)));
route('POST', '/app/memberDevice/add', true, ({ uid, body }) => {
  need(body, 'name', 'height', 'birthday');
  const r = run('INSERT INTO members(owner_id,name,gender,birthday,height,avatar,athlete) VALUES(?,?,?,?,?,?,?)', uid, body.name, body.gender ?? 1, body.birthday, Number(body.height), body.avatar || '🙂', body.athlete ? 1 : 0);
  return ok(memberView(q1('SELECT * FROM members WHERE id=?', Number(r.lastInsertRowid))));
});
route('POST', '/app/memberDevice/update', true, ({ uid, body }) => {
  need(body, 'id');
  const m = myMember(uid, body.id);
  run('UPDATE members SET name=?,gender=?,birthday=?,height=?,avatar=?,athlete=? WHERE id=?', body.name ?? m.name, body.gender ?? m.gender, body.birthday ?? m.birthday, body.height ?? m.height, body.avatar ?? m.avatar, (body.athlete ?? m.athlete) ? 1 : 0, m.id);
  return ok(memberView(q1('SELECT * FROM members WHERE id=?', m.id)));
});
route('POST', '/app/memberDevice/deleteByUid', true, ({ uid, body }) => {
  const m = myMember(uid, body.id);
  if (m.is_self) throw new ApiError('cannot delete your own profile');
  run('DELETE FROM body_data WHERE member_id=?', m.id);
  run('DELETE FROM members WHERE id=?', m.id);
  return ok();
});

// devices
route('GET', '/app/user/getUserDevice', true, ({ uid }) => {
  const own = q('SELECT * FROM devices WHERE owner_id=? ORDER BY id', uid).map((d) => deviceView(d));
  const sh = q('SELECT d.* FROM devices d JOIN device_shares s ON s.device_id=d.id WHERE s.user_id=?', uid).map((d) => deviceView(d, true));
  return ok([...own, ...sh]);
});
route('POST', '/app/user/addUserDevice', true, ({ uid, body }) => {
  need(body, 'mac', 'name');
  const ex = q1('SELECT * FROM devices WHERE mac=?', body.mac);
  if (ex && ex.owner_id !== uid) throw new ApiError('device already bound to another account');
  if (ex) return ok(deviceView(ex));
  const r = run('INSERT INTO devices(owner_id,mac,name,kind,bound) VALUES(?,?,?,?,?)', uid, body.mac, body.name, body.kind || 'body', now());
  return ok(deviceView(q1('SELECT * FROM devices WHERE id=?', Number(r.lastInsertRowid))));
});
route('POST', '/app/device/updateDevice', true, ({ uid, body }) => {
  need(body, 'id');
  const d = deviceAccess(uid, body.id);
  run('UPDATE devices SET custom_name=?, unit=? WHERE id=?', body.customName ?? d.custom_name, body.unit ?? d.unit, d.id);
  return ok(deviceView(q1('SELECT * FROM devices WHERE id=?', d.id)));
});
route('POST', '/app/user/removeUserDevice', true, ({ uid, body }) => {
  const d = q1('SELECT * FROM devices WHERE id=?', body.id);
  if (!d) throw new ApiError('device not found', 404);
  if (d.owner_id === uid) { run('DELETE FROM device_shares WHERE device_id=?', d.id); run('DELETE FROM devices WHERE id=?', d.id); }
  else run('DELETE FROM device_shares WHERE device_id=? AND user_id=?', d.id, uid);
  return ok();
});
route('POST', '/app/device/shareDevice', true, ({ uid, body }) => {
  need(body, 'id', 'email');
  const d = q1('SELECT * FROM devices WHERE id=? AND owner_id=?', body.id, uid);
  if (!d) throw new ApiError('only the owner can share a device');
  const t = q1('SELECT * FROM users WHERE email=?', String(body.email).trim().toLowerCase());
  if (!t) throw new ApiError('user not found');
  if (t.id === uid) throw new ApiError('cannot share with yourself');
  run('INSERT OR IGNORE INTO device_shares(device_id,user_id) VALUES(?,?)', d.id, t.id);
  return ok();
});
route('GET', '/app/device/shareUsers', true, ({ uid, query }) => {
  const d = q1('SELECT * FROM devices WHERE id=? AND owner_id=?', query.id, uid);
  if (!d) throw new ApiError('device not found');
  return ok(q('SELECT u.id,u.email,u.nickname FROM users u JOIN device_shares s ON s.user_id=u.id WHERE s.device_id=?', d.id).map(userView));
});
route('POST', '/app/device/unshareDevice', true, ({ uid, body }) => {
  const d = q1('SELECT * FROM devices WHERE id=? AND owner_id=?', body.id, uid);
  if (!d) throw new ApiError('device not found');
  run('DELETE FROM device_shares WHERE device_id=? AND user_id=?', d.id, body.userId);
  return ok();
});

// body data
route('POST', '/app/bodyData', true, ({ uid, body }) => {
  need(body, 'weight');
  const w = Number(body.weight);
  if (!(w > 0 && w < 400)) throw new ApiError('invalid weight');
  let memberId = body.memberId ?? null;
  let metrics = body.metrics || {};
  if (memberId) {
    const m = myMember(uid, memberId);
    if (!body.metrics) metrics = computeMetrics(w, Number(body.impedance || 0), m.height, ageOf(m.birthday), m.gender, !!m.athlete);
  }
  if (body.clientId) {
    const dup = q1('SELECT * FROM body_data WHERE owner_id=? AND client_id=?', uid, String(body.clientId));
    if (dup) return ok(dataView(dup));
  }
  const r = run('INSERT INTO body_data(owner_id,member_id,device_id,weight,impedance,metrics,source,ts,client_id) VALUES(?,?,?,?,?,?,?,?,?)', uid, memberId, body.deviceId ?? null, w, Number(body.impedance || 0), JSON.stringify(metrics), body.source || 'manual', body.ts || now(), body.clientId ? String(body.clientId) : null);
  if (memberId) checkMilestones(uid, memberId);
  return ok(dataView(q1('SELECT * FROM body_data WHERE id=?', Number(r.lastInsertRowid))));
});
route('POST', '/app/bodyData/compute', true, ({ uid, body }) => {
  need(body, 'weight');
  if (body.memberId) {
    const m = myMember(uid, body.memberId);
    return ok(computeMetrics(Number(body.weight), Number(body.impedance || 0), m.height, ageOf(m.birthday), m.gender, !!m.athlete));
  }
  // guest mode: caller supplies height/age/gender
  need(body, 'height', 'age', 'gender');
  return ok(computeMetrics(Number(body.weight), Number(body.impedance || 0), Number(body.height), Number(body.age), Number(body.gender)));
});
route('GET', '/app/bodyData/list', true, ({ uid, query }) => {
  const mid = query.memberId ? Number(query.memberId) : null;
  const rows = mid ? q('SELECT * FROM body_data WHERE owner_id=? AND member_id=? ORDER BY ts DESC LIMIT 500', uid, mid) : q('SELECT * FROM body_data WHERE owner_id=? ORDER BY ts DESC LIMIT 500', uid);
  return ok(rows.map(dataView));
});
route('GET', '/app/bodyData/unclaimed', true, ({ uid }) => ok(q('SELECT * FROM body_data WHERE owner_id=? AND member_id IS NULL ORDER BY ts DESC', uid).map(dataView)));
route('POST', '/app/bodyData/claim', true, ({ uid, body }) => {
  need(body, 'id', 'memberId');
  const r = q1('SELECT * FROM body_data WHERE id=? AND owner_id=?', body.id, uid);
  if (!r) throw new ApiError('record not found', 404);
  const m = myMember(uid, body.memberId);
  const metrics = computeMetrics(r.weight, r.impedance, m.height, ageOf(m.birthday), m.gender, !!m.athlete);
  run('UPDATE body_data SET member_id=?, metrics=? WHERE id=?', m.id, JSON.stringify(metrics), r.id);
  return ok(dataView(q1('SELECT * FROM body_data WHERE id=?', r.id)));
});
route('POST', '/app/bodyData/delete', true, ({ uid, body }) => {
  run('DELETE FROM body_data WHERE id=? AND owner_id=?', body.id, uid);
  return ok();
});
// data sharing between accounts
route('POST', '/app/bodyDataShare', true, ({ uid, body }) => {
  need(body, 'email', 'memberId');
  myMember(uid, body.memberId);
  const t = q1('SELECT * FROM users WHERE email=?', String(body.email).trim().toLowerCase());
  if (!t) throw new ApiError('user not found');
  if (t.id === uid) throw new ApiError('cannot share with yourself');
  run('INSERT OR IGNORE INTO body_share(owner_id,viewer_id,member_id) VALUES(?,?,?)', uid, t.id, body.memberId);
  return ok();
});
route('GET', '/app/bodyDataShare/list', true, ({ uid }) => ok(q('SELECT s.id,s.member_id,u.email,u.nickname,m.name member_name FROM body_share s JOIN users u ON u.id=s.viewer_id JOIN members m ON m.id=s.member_id WHERE s.owner_id=?', uid).map((r) => ({ id: Number(r.id), memberId: Number(r.member_id), memberName: r.member_name, email: r.email, nickname: r.nickname }))));
route('GET', '/app/bodyDataShare/otherList', true, ({ uid }) => ok(q('SELECT s.id,s.owner_id,s.member_id,u.email,u.nickname,m.name member_name FROM body_share s JOIN users u ON u.id=s.owner_id JOIN members m ON m.id=s.member_id WHERE s.viewer_id=?', uid).map((r) => ({ id: Number(r.id), ownerId: Number(r.owner_id), memberId: Number(r.member_id), memberName: r.member_name, ownerEmail: r.email, ownerNickname: r.nickname }))));
route('GET', '/app/bodyDataShare/bodyData/list', true, ({ uid, query }) => {
  const s = q1('SELECT * FROM body_share WHERE owner_id=? AND viewer_id=? AND member_id=?', query.ownerId, uid, query.memberId);
  if (!s) throw new ApiError('no permission', 403);
  return ok(q('SELECT * FROM body_data WHERE owner_id=? AND member_id=? ORDER BY ts DESC LIMIT 500', s.owner_id, s.member_id).map(dataView));
});
route('POST', '/app/bodyDataShare/delete', true, ({ uid, body }) => {
  run('DELETE FROM body_share WHERE id=? AND (owner_id=? OR viewer_id=?)', body.id, uid, uid);
  return ok();
});

// food
route('GET', '/food/scale/defaultFood', true, () => ok(q('SELECT * FROM food_bank ORDER BY id').map((f) => ({ id: Number(f.id), name: f.name, kcal: f.kcal, protein: f.protein, fat: f.fat, carb: f.carb, icon: f.icon }))));
route('POST', '/food/record/upload', true, ({ uid, body }) => {
  need(body, 'name', 'grams');
  const g = Number(body.grams);
  if (!(g > 0)) throw new ApiError('invalid grams');
  let per = body.per100;
  if (!per && body.foodId) {
    const f = q1('SELECT * FROM food_bank WHERE id=?', body.foodId);
    if (f) per = { kcal: f.kcal, protein: f.protein, fat: f.fat, carb: f.carb };
  }
  per = per || { kcal: 0, protein: 0, fat: 0, carb: 0 };
  const k = g / 100;
  if (body.clientId) {
    const dup = q1('SELECT * FROM food_records WHERE user_id=? AND client_id=?', uid, String(body.clientId));
    if (dup) return ok(foodView(dup));
  }
  const r = run('INSERT INTO food_records(user_id,member_id,name,grams,kcal,protein,fat,carb,meal,ts,client_id) VALUES(?,?,?,?,?,?,?,?,?,?,?)', uid, body.memberId ?? null, body.name, g, round(per.kcal * k), round(per.protein * k), round(per.fat * k), round(per.carb * k), body.meal || 'snack', body.ts || now(), body.clientId ? String(body.clientId) : null);
  return ok(foodView(q1('SELECT * FROM food_records WHERE id=?', Number(r.lastInsertRowid))));
});
route('GET', '/food/record/list', true, ({ uid, query }) => {
  const from = Number(query.from || 0), to = Number(query.to || now() + 86400e3);
  return ok(q('SELECT * FROM food_records WHERE user_id=? AND ts>=? AND ts<? ORDER BY ts DESC', uid, from, to).map(foodView));
});
route('POST', '/food/record/delete', true, ({ uid, body }) => { run('DELETE FROM food_records WHERE id=? AND user_id=?', body.id, uid); return ok(); });
route('GET', '/food/record/countTodayNutrition', true, ({ uid, query }) => {
  const from = Number(query.from || new Date().setHours(0, 0, 0, 0));
  const r = q1('SELECT COALESCE(SUM(kcal),0) kcal, COALESCE(SUM(protein),0) protein, COALESCE(SUM(fat),0) fat, COALESCE(SUM(carb),0) carb, COALESCE(SUM(grams),0) grams, COUNT(*) n FROM food_records WHERE user_id=? AND ts>=? AND ts<?', uid, from, from + 86400e3);
  return ok({ kcal: round(r.kcal), protein: round(r.protein), fat: round(r.fat), carb: round(r.carb), grams: round(r.grams), count: Number(r.n) });
});
route('GET', '/food/record/countLastSevenCalorie', true, ({ uid, query }) => {
  const today = Number(query.from || new Date().setHours(0, 0, 0, 0));
  const out = [];
  for (let i = 6; i >= 0; i--) {
    const f = today - i * 86400e3;
    const r = q1('SELECT COALESCE(SUM(kcal),0) kcal FROM food_records WHERE user_id=? AND ts>=? AND ts<?', uid, f, f + 86400e3);
    out.push({ day: f, kcal: round(r.kcal) });
  }
  return ok(out);
});

// goals
const GOAL_TYPES = { weight: [20, 300], bodyFat: [5, 55] };
route('GET', '/app/goal', true, ({ uid, query }) => {
  myMember(uid, query.memberId);
  const g = q1('SELECT * FROM goals WHERE member_id=?', query.memberId);
  return ok(g ? { memberId: Number(g.member_id), type: g.type, start: g.start_value, target: g.target, targetDate: g.target_date == null ? null : Number(g.target_date), created: Number(g.created) } : null);
});
route('POST', '/app/goal', true, ({ uid, body }) => {
  need(body, 'memberId', 'type', 'target');
  myMember(uid, body.memberId);
  const range = GOAL_TYPES[body.type];
  if (!range) throw new ApiError('goal type must be weight or bodyFat');
  const target = Number(body.target);
  if (!(target >= range[0] && target <= range[1])) throw new ApiError(`target must be between ${range[0]} and ${range[1]}`);
  if (body.targetDate && Number(body.targetDate) < now()) throw new ApiError('target date is in the past');
  const last = q1('SELECT * FROM body_data WHERE owner_id=? AND member_id=? ORDER BY ts DESC LIMIT 1', uid, body.memberId);
  let start = body.start != null ? Number(body.start) : null;
  if (start == null && last) start = body.type === 'weight' ? last.weight : JSON.parse(last.metrics || '{}').bodyFat ?? null;
  if (start == null) throw new ApiError('add a measurement first so the goal has a starting point');
  if (start === target) throw new ApiError('target equals your current value');
  run('INSERT OR REPLACE INTO goals(member_id,owner_id,type,start_value,target,target_date,created) VALUES(?,?,?,?,?,?,?)', body.memberId, uid, body.type, start, target, body.targetDate ? Number(body.targetDate) : null, now());
  return ok({ memberId: Number(body.memberId), type: body.type, start, target, targetDate: body.targetDate ? Number(body.targetDate) : null });
});
route('POST', '/app/goal/delete', true, ({ uid, body }) => { run('DELETE FROM goals WHERE member_id=? AND owner_id=?', body.memberId, uid); return ok(); });

// weekly summary: last 7 days (ending today) vs the 7 days before
const DAY = 86400e3;
export function weeklySummary(uid, memberId, today) {
  const from = today - 6 * DAY, prevFrom = from - 7 * DAY;
  const rows = q('SELECT weight, metrics, ts FROM body_data WHERE owner_id=? AND member_id=? AND ts>=? AND ts<? ORDER BY ts', uid, memberId, prevFrom, today + DAY).map((r) => ({ w: r.weight, bf: JSON.parse(r.metrics || '{}').bodyFat ?? null, ts: Number(r.ts) }));
  const cur = rows.filter((r) => r.ts >= from), prev = rows.filter((r) => r.ts < from);
  const avg = (a, f) => { const v = a.map(f).filter((x) => x != null); return v.length ? round(v.reduce((x, y) => x + y, 0) / v.length, 2) : null; };
  const days = [];
  for (let i = 0; i < 7; i++) days.push(cur.some((r) => r.ts >= from + i * DAY && r.ts < from + (i + 1) * DAY));
  // streak of consecutive days with a weigh-in (today may still be pending)
  const all = q('SELECT ts FROM body_data WHERE owner_id=? AND member_id=? AND ts<?', uid, memberId, today + DAY).map((r) => Math.floor((Number(r.ts) - (today % DAY)) / DAY));
  const set = new Set(all);
  const todayIdx = Math.floor((today - (today % DAY)) / DAY);
  let streak = 0, d = set.has(todayIdx) ? todayIdx : todayIdx - 1;
  while (set.has(d) && streak < 3650) { streak++; d--; }
  const food = q1('SELECT COALESCE(SUM(kcal),0) kcal, COUNT(DISTINCT CAST((ts - ?) / ? AS INTEGER)) days FROM food_records WHERE user_id=? AND ts>=? AND ts<?', today % DAY, DAY, uid, from, today + DAY);
  const first = cur[0], last = cur[cur.length - 1];
  return {
    from, weighIns: cur.length, daysWithWeighIn: days, streak,
    avgWeight: avg(cur, (r) => r.w), prevAvgWeight: avg(prev, (r) => r.w),
    changeKg: first && last && cur.length > 1 ? round(last.w - first.w, 2) : null,
    avgBodyFat: avg(cur, (r) => r.bf), prevAvgBodyFat: avg(prev, (r) => r.bf),
    minWeight: cur.length ? Math.min(...cur.map((r) => r.w)) : null, maxWeight: cur.length ? Math.max(...cur.map((r) => r.w)) : null,
    calories: { total: round(food.kcal, 0), loggedDays: Number(food.days), avgPerLoggedDay: Number(food.days) ? round(food.kcal / Number(food.days), 0) : null },
  };
}
route('GET', '/app/summary/weekly', true, ({ uid, query }) => {
  myMember(uid, query.memberId);
  const today = Number(query.today) || new Date().setHours(0, 0, 0, 0);
  return ok(weeklySummary(uid, Number(query.memberId), today));
});

// messages
route('GET', '/app/messages', true, ({ uid }) => {
  weeklyDigest(uid);
  const rows = q('SELECT * FROM messages WHERE user_id=? ORDER BY ts DESC LIMIT 100', uid).map((m) => ({ id: Number(m.id), kind: m.kind, title: m.title, body: m.body, ts: Number(m.ts), read: !!m.read }));
  return ok({ unread: rows.filter((m) => !m.read).length, messages: rows });
});
route('POST', '/app/messages/read', true, ({ uid, body }) => {
  if (body.id) run('UPDATE messages SET read=1 WHERE id=? AND user_id=?', body.id, uid);
  else run('UPDATE messages SET read=1 WHERE user_id=?', uid);
  return ok();
});
route('POST', '/app/messages/delete', true, ({ uid, body }) => { run('DELETE FROM messages WHERE id=? AND user_id=?', body.id, uid); return ok(); });

// firmware registry (the virtual scale downloads nothing from the internet: the image is served here)
const FW_LATEST = '1.1.0';
const FW_BYTES = (() => { const b = Buffer.alloc(64 * 1024); let h = crypto.createHash('sha256').update('virtual-scale-' + FW_LATEST).digest(); for (let i = 0; i < b.length; i += 32) { h.copy(b, i); h = crypto.createHash('sha256').update(h).digest(); } return b; })();
const FW_SHA = crypto.createHash('sha256').update(FW_BYTES).digest('hex');
const cmpVer = (a, b) => { const x = String(a).split('.').map(Number), y = String(b).split('.').map(Number); for (let i = 0; i < 3; i++) { const d = (x[i] || 0) - (y[i] || 0); if (d) return d; } return 0; };
route('GET', '/app/xinmiaoProductHardwareVersion/judgeVersion', true, ({ query }) => {
  const cur = query.version || '1.0.0';
  return ok({ model: query.model || 'virtual', current: cur, latest: FW_LATEST, upToDate: cmpVer(cur, FW_LATEST) >= 0, notes: ['Faster weight stabilisation', 'Improved impedance accuracy', 'New display brightness steps'], size: FW_BYTES.length, sha256: FW_SHA, url: `/firmware/virtual-${FW_LATEST}.bin` });
});

// barcode lookup for the food diary
route('GET', '/food/barcode', true, ({ query }) => {
  const code = String(query.code || '').trim();
  if (!/^\d{6,14}$/.test(code)) throw new ApiError('invalid barcode');
  const r = q1('SELECT f.* FROM barcodes b JOIN food_bank f ON f.name=b.food_name WHERE b.code=?', code);
  if (!r) throw new ApiError('This barcode is not in the local food database', 404);
  return ok({ id: Number(r.id), name: r.name, kcal: r.kcal, protein: r.protein, fat: r.fat, carb: r.carb, icon: r.icon });
});

// coffee brews
route('POST', '/app/brew', true, ({ uid, body }) => {
  need(body, 'dose', 'water');
  const dose = Number(body.dose), water = Number(body.water);
  if (!(dose > 0 && dose < 200) || !(water > 0 && water < 5000)) throw new ApiError('dose and water must be positive amounts in grams');
  const rating = body.rating == null ? null : Math.round(Number(body.rating));
  if (rating != null && !(rating >= 1 && rating <= 5)) throw new ApiError('rating must be 1 to 5');
  const r = run('INSERT INTO brews(user_id,name,dose,water,seconds,rating,notes,ts) VALUES(?,?,?,?,?,?,?,?)', uid, String(body.name || 'Coffee').slice(0, 60), dose, water, Number(body.seconds || 0), rating, String(body.notes || '').slice(0, 300), body.ts || now());
  return ok(brewView(q1('SELECT * FROM brews WHERE id=?', Number(r.lastInsertRowid))));
});
const brewView = (b) => ({ id: Number(b.id), name: b.name, dose: b.dose, water: b.water, seconds: b.seconds, ratio: round(b.water / b.dose, 1), rating: b.rating, notes: b.notes, ts: Number(b.ts) });
route('GET', '/app/brew/list', true, ({ uid }) => ok(q('SELECT * FROM brews WHERE user_id=? ORDER BY ts DESC LIMIT 200', uid).map(brewView)));
route('POST', '/app/brew/delete', true, ({ uid, body }) => { run('DELETE FROM brews WHERE id=? AND user_id=?', body.id, uid); return ok(); });

// QR login: a web page shows a QR code, the signed-in app scans and confirms it
const qrSessions = new Map();
const QR_TTL = 120e3;
const qrGet = (id) => { const x = qrSessions.get(String(id)); if (!x) throw new ApiError('QR code not found', 404); if (x.expires < now()) { qrSessions.delete(String(id)); throw new ApiError('QR code expired', 410); } return x; };
route('POST', '/app/user/qrCode/create', false, () => {
  for (const [k, v] of qrSessions) if (v.expires < now()) qrSessions.delete(k);
  const id = crypto.randomBytes(12).toString('hex');
  qrSessions.set(id, { status: 'waiting', expires: now() + QR_TTL, uid: null, tokens: null });
  return ok({ id, payload: `uhqr:${id}`, expiresIn: QR_TTL });
});
route('GET', '/app/user/qrCode/status', false, ({ query }) => {
  let x;
  try { x = qrGet(query.id); } catch (e) { return ok({ status: 'expired' }); }
  if (x.status === 'confirmed') { const t = x.tokens; x.status = 'done'; x.tokens = null; return ok({ status: 'confirmed', ...t, user: userView(q1('SELECT * FROM users WHERE id=?', x.uid)) }); }
  return ok({ status: x.status, nickname: x.uid ? q1('SELECT nickname FROM users WHERE id=?', x.uid)?.nickname : undefined });
});
route('POST', '/app/user/qrCode/scan', true, ({ uid, body }) => {
  const x = qrGet(String(body.id || '').replace(/^uhqr:/, ''));
  if (x.status !== 'waiting') throw new ApiError('QR code already used');
  x.status = 'scanned'; x.uid = uid;
  return ok({ status: 'scanned' });
});
route('POST', '/app/user/qrCode/confirm', true, ({ uid, body }) => {
  const x = qrGet(String(body.id || '').replace(/^uhqr:/, ''));
  if (x.status !== 'scanned' || x.uid !== uid) throw new ApiError('scan the QR code first');
  x.status = 'confirmed'; x.tokens = tokens(uid);
  return ok({ status: 'confirmed' });
});
route('POST', '/app/user/qrCode/cancel', true, ({ body }) => { qrSessions.delete(String(body.id || '').replace(/^uhqr:/, '')); return ok(); });

// misc
route('GET', '/common/whichServer', false, () => ok({ server: 'local', version: '1.0.0' }));
route('GET', '/health', false, () => ok({ up: true }));

// ---------- http server ----------
async function readBody(req) {
  const chunks = [];
  for await (const c of req) chunks.push(c);
  const s = Buffer.concat(chunks).toString();
  if (!s) return {};
  try { return JSON.parse(s); } catch { throw new ApiError('invalid JSON'); }
}
const MIME = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.css': 'text/css' };

export const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://x');
  const pathname = url.pathname.replace(/\/+$/, '') || '/';
  const send = (status, obj) => { res.writeHead(status, { 'content-type': 'application/json', 'access-control-allow-origin': '*', 'access-control-allow-headers': '*', 'access-control-allow-methods': '*' }); res.end(JSON.stringify(obj)); };
  if (req.method === 'OPTIONS') return send(204, {});
  if (pathname === '/' || pathname.startsWith('/simulator')) {
    const f = path.join(__dirname, 'public', 'simulator.html');
    res.writeHead(200, { 'content-type': MIME['.html'] });
    return res.end(fs.readFileSync(f));
  }
  if (pathname.startsWith('/firmware/')) {
    if (pathname === `/firmware/virtual-${FW_LATEST}.bin`) { res.writeHead(200, { 'content-type': 'application/octet-stream', 'content-length': FW_BYTES.length, 'access-control-allow-origin': '*' }); return res.end(FW_BYTES); }
    return send(404, { code: 404, msg: 'not found', data: null });
  }
  if (pathname === '/web') { res.writeHead(200, { 'content-type': MIME['.html'] }); return res.end(fs.readFileSync(path.join(__dirname, 'public', 'web.html'))); }
  if (pathname === '/app/qr') {
    const text = String(url.searchParams.get('text') || '').slice(0, 200);
    if (!text) return send(400, { code: 1, msg: 'text is required', data: null });
    const svg = await QRCode.toString(text, { type: 'svg', margin: 1, width: 240 });
    res.writeHead(200, { 'content-type': 'image/svg+xml', 'access-control-allow-origin': '*' });
    return res.end(svg);
  }
  const r = routes[`${req.method} ${pathname}`];
  if (!r) return send(404, { code: 404, msg: 'not found', data: null });
  try {
    let uid = null;
    if (r.auth) {
      const t = (req.headers['access-token'] || (req.headers.authorization || '').replace(/^Bearer /, ''));
      const p = verify(t);
      if (!p || p.t !== 'a') throw new ApiError('unauthorized', 401, 401);
      uid = p.uid;
      if (!q1('SELECT 1 x FROM users WHERE id=?', uid)) throw new ApiError('unauthorized', 401, 401);
    }
    const body = req.method === 'GET' ? {} : await readBody(req);
    const out = await r.fn({ uid, body, query: Object.fromEntries(url.searchParams) });
    send(200, out);
  } catch (e) {
    if (e instanceof ApiError) return send(e.http, { code: e.code, msg: e.message, data: null });
    console.error(e);
    send(500, { code: 500, msg: 'internal error', data: null });
  }
});

// ---------- virtual scale hub (WebSocket) ----------
// scale  -> hub: {type:'hello',mac,name,kind} | {type:'reading',kg,stable,impedance,unit} | {type:'off'}
// app    -> hub: {type:'list'} | {type:'connect',mac} | {type:'disconnect'} | {type:'cmd',...}
const wss = new WebSocketServer({ server, path: '/ws' });
const scales = new Map(); // mac -> {ws, info}
const sendJ = (ws, o) => { if (ws.readyState === 1) ws.send(JSON.stringify(o)); };
wss.on('connection', (ws) => {
  ws.role = null; ws.mac = null; ws.linked = null;
  ws.on('message', (raw) => {
    let m; try { m = JSON.parse(raw.toString()); } catch { return; }
    if (m.type === 'hello' && m.role !== 'app') {
      if (ws.mac) scales.delete(ws.mac);
      ws.role = 'scale'; ws.mac = m.mac || 'AA:BB:CC:00:00:01';
      scales.set(ws.mac, { ws, info: { mac: ws.mac, name: m.name || 'CF568_G', kind: m.kind || 'body', rssi: -48, caps: Array.isArray(m.caps) ? m.caps : [] } });
      sendJ(ws, { type: 'ready', mac: ws.mac });
    } else if (m.type === 'hello') { ws.role = 'app'; sendJ(ws, { type: 'ready' }); }
    else if (ws.role === 'app') {
      if (m.type === 'list') sendJ(ws, { type: 'devices', devices: [...scales.values()].map((s) => s.info) });
      else if (m.type === 'connect') {
        const s = scales.get(m.mac);
        if (!s) return sendJ(ws, { type: 'error', msg: 'device not found' });
        ws.linked = s.ws; s.ws.linkedApp = ws;
        sendJ(ws, { type: 'connected', device: s.info });
        sendJ(s.ws, { type: 'appConnected' });
      } else if (m.type === 'disconnect') {
        if (ws.linked) { sendJ(ws.linked, { type: 'appDisconnected' }); ws.linked.linkedApp = null; }
        ws.linked = null; sendJ(ws, { type: 'disconnected' });
      } else if (m.type === 'cmd' && ws.linked) sendJ(ws.linked, m);
    } else if (ws.role === 'scale' && m.type !== 'hello') {
      if (ws.linkedApp) sendJ(ws.linkedApp, m);
    }
  });
  ws.on('close', () => {
    if (ws.role === 'scale') { scales.delete(ws.mac); if (ws.linkedApp) { sendJ(ws.linkedApp, { type: 'disconnected', reason: 'scale offline' }); ws.linkedApp.linked = null; } }
    if (ws.role === 'app' && ws.linked && ws.linked.linkedApp === ws) { sendJ(ws.linked, { type: 'appDisconnected' }); ws.linked.linkedApp = null; }
  });
});

// demo seed
if (!q1("SELECT 1 x FROM users WHERE email='demo@unique.test'")) {
  const uid = createUser('demo@unique.test', 'demo1234', 'Demo');
  const m = q1('SELECT * FROM members WHERE owner_id=? AND is_self=1', uid);
  const kid = Number(run('INSERT INTO members(owner_id,name,gender,birthday,height,avatar) VALUES(?,?,?,?,?,?)', uid, 'Sara', 0, '1998-06-12', 163, '👩').lastInsertRowid);
  for (const [mem, base, imp] of [[m, 78, 520], [{ id: kid, height: 163, birthday: '1998-06-12', gender: 0 }, 61, 600]]) {
    for (let i = 29; i >= 0; i--) {
      const w = round(base + Math.sin(i / 4) * 0.8 + i * 0.05 + (Math.random() - 0.5) * 0.4, 1);
      const met = computeMetrics(w, imp, mem.height, ageOf(mem.birthday), mem.gender);
      run('INSERT INTO body_data(owner_id,member_id,weight,impedance,metrics,source,ts) VALUES(?,?,?,?,?,?,?)', uid, mem.id, w, imp, JSON.stringify(met), 'seed', now() - i * 86400e3);
    }
  }
  createUser('friend@unique.test', 'friend1234', 'Friend');
}

// migration: records saved before the validated equations have no `method` flag -> recompute
for (const r of q('SELECT b.id, b.weight, b.impedance, b.metrics, m.height, m.birthday, m.gender, m.athlete FROM body_data b JOIN members m ON m.id=b.member_id')) {
  const cur = JSON.parse(r.metrics || '{}');
  if (cur.method !== undefined || r.source === 'baby' || Object.keys(cur).length < 3) continue;
  run('UPDATE body_data SET metrics=? WHERE id=?', JSON.stringify(computeMetrics(r.weight, r.impedance, r.height, ageOf(r.birthday), r.gender, !!r.athlete)), r.id);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  server.listen(PORT, '0.0.0.0', () => {
    console.log(`Unique clone backend  : http://localhost:${PORT}`);
    console.log(`Virtual scale (browser): http://localhost:${PORT}/simulator`);
    console.log('Demo login: demo@unique.test / demo1234   (friend@unique.test / friend1234)');
  });
}
