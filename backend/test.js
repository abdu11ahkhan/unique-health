// End-to-end smoke test. Uses a temp DB. Run: npm test
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import assert from 'node:assert/strict';

process.env.DB_FILE = path.join(os.tmpdir(), `uc-test-${Date.now()}.db`);
process.env.PORT = '0';
const { server, computeMetrics } = await import('./server.js');
await new Promise((r) => server.listen(0, r));
const base = `http://127.0.0.1:${server.address().port}`;

async function api(method, p, body, token) {
  const r = await fetch(base + p, { method, headers: { 'content-type': 'application/json', ...(token ? { 'Access-Token': token } : {}) }, body: method === 'GET' ? undefined : JSON.stringify(body || {}) });
  return r.json();
}
let n = 0;
const t = (name, fn) => fn().then(() => console.log('ok  ', ++n, name)).catch((e) => { console.error('FAIL', name, e.message); process.exitCode = 1; });

let tok, tok2, memberId, devId, recId;
await t('signup rejects bad input', async () => {
  assert.equal((await api('POST', '/app/user/signUp', { email: 'x', password: '123456' })).code, 1);
  assert.equal((await api('POST', '/app/user/signUp', { email: 'a@b.co', password: '1' })).code, 1);
});
await t('signup + login + duplicate', async () => {
  const s = await api('POST', '/app/user/signUp', { email: 'a@b.co', password: 'secret1', nickname: 'Al' });
  assert.equal(s.code, 0); tok = s.data.accessToken;
  assert.equal((await api('POST', '/app/user/signUp', { email: 'a@b.co', password: 'secret1' })).code, 1);
  assert.equal((await api('POST', '/app/user/login', { email: 'a@b.co', password: 'nope' })).code, 1);
  const l = await api('POST', '/app/user/login', { email: 'a@b.co', password: 'secret1' });
  assert.equal(l.code, 0);
});
await t('auth required + refresh', async () => {
  assert.equal((await api('GET', '/app/user')).code, 401);
  const l = await api('POST', '/app/user/login', { email: 'a@b.co', password: 'secret1' });
  const r = await api('POST', '/app/user/refreshToken', { refreshToken: l.data.refreshToken });
  assert.equal(r.code, 0);
  assert.equal((await api('POST', '/app/user/refreshToken', { refreshToken: l.data.accessToken })).code, 401);
});
await t('forgot/reset password', async () => {
  const f = await api('POST', '/app/user/sendForgotPasswordEmail', { email: 'a@b.co' });
  assert.match(f.data.devCode, /^\d{6}$/);
  assert.equal((await api('POST', '/app/user/resetPassword', { email: 'a@b.co', code: '000000', newPassword: 'newpass1' })).code, 1);
  assert.equal((await api('POST', '/app/user/resetPassword', { email: 'a@b.co', code: f.data.devCode, newPassword: 'newpass1' })).code, 0);
  const l = await api('POST', '/app/user/login', { email: 'a@b.co', password: 'newpass1' });
  assert.equal(l.code, 0); tok = l.data.accessToken;
});
await t('members', async () => {
  const l = await api('GET', '/app/memberDevice/list', null, tok);
  assert.equal(l.data.length, 1); memberId = l.data[0].id;
  const a = await api('POST', '/app/memberDevice/add', { name: 'Kid', height: 120, birthday: '2018-01-01', gender: 0 }, tok);
  assert.equal(a.code, 0);
  assert.equal((await api('POST', '/app/memberDevice/deleteByUid', { id: memberId }, tok)).code, 1); // self
  assert.equal((await api('POST', '/app/memberDevice/deleteByUid', { id: a.data.id }, tok)).code, 0);
});
await t('device bind/update/share', async () => {
  const d = await api('POST', '/app/user/addUserDevice', { mac: 'AA:BB', name: 'CF568_G', kind: 'body' }, tok);
  assert.equal(d.code, 0); devId = d.data.id;
  assert.equal((await api('POST', '/app/device/updateDevice', { id: devId, customName: 'Bathroom', unit: 'lb' }, tok)).data.customName, 'Bathroom');
  const s2 = await api('POST', '/app/user/signUp', { email: 'c@d.co', password: 'secret2' }); tok2 = s2.data.accessToken;
  assert.equal((await api('POST', '/app/user/addUserDevice', { mac: 'AA:BB', name: 'x' }, tok2)).code, 1);
  assert.equal((await api('POST', '/app/device/shareDevice', { id: devId, email: 'c@d.co' }, tok)).code, 0);
  assert.equal((await api('GET', '/app/user/getUserDevice', null, tok2)).data[0].shared, true);
  assert.equal((await api('POST', '/app/device/shareDevice', { id: devId, email: 'zz@zz.co' }, tok)).code, 1);
});
await t('body data + metrics', async () => {
  const r = await api('POST', '/app/bodyData', { weight: 75.2, impedance: 510, memberId, deviceId: devId, source: 'scale' }, tok);
  assert.equal(r.code, 0); recId = r.data.id;
  const m = r.data.metrics;
  for (const k of ['bmi', 'bodyFat', 'muscleMass', 'water', 'boneMass', 'bmr', 'visceralFat', 'score']) assert.ok(typeof m[k] === 'number' && Number.isFinite(m[k]), k);
  assert.ok(m.bodyFat > 4 && m.bodyFat < 60);
  assert.equal((await api('POST', '/app/bodyData', { weight: -1 }, tok)).code, 1);
  assert.equal((await api('GET', `/app/bodyData/list?memberId=${memberId}`, null, tok)).data.length, 1);
});
await t('body composition equations', async () => {
  // male 30y 170cm 72.5kg 520 ohm: Sun 2003 -> FFM 54.7kg (fat ~24.5%), TBW 39.3L (~54%); Janssen 2000 -> SMM ~29.1kg
  const m = computeMetrics(72.5, 520, 170, 30, 1);
  assert.equal(m.method, 1);
  assert.ok(Math.abs(m.bodyFat - 24.5) < 0.6, 'bodyFat ' + m.bodyFat);
  assert.ok(Math.abs(m.water - 54.2) < 0.8, 'water ' + m.water);
  assert.ok(Math.abs(m.muscleMass - 29.1) < 0.5, 'smm ' + m.muscleMass);
  assert.ok(Math.abs(m.bmr - 1642.5) < 1, 'bmr ' + m.bmr); // Mifflin: 725+1062.5-150+5
  // higher impedance (same body) -> less fat-free mass -> more fat
  assert.ok(computeMetrics(72.5, 700, 170, 30, 1).bodyFat > m.bodyFat);
  // no impedance falls back to Deurenberg: 1.2*25.09+0.23*30-10.8-5.4 = 20.8
  const n = computeMetrics(72.5, 0, 170, 30, 1);
  assert.equal(n.method, 2);
  assert.ok(Math.abs(n.bodyFat - 20.8) < 0.2, 'deurenberg ' + n.bodyFat);
  // implausible impedance is ignored
  assert.equal(computeMetrics(72.5, 20, 170, 30, 1).method, 2);
  // female reference
  const f = computeMetrics(61, 600, 163, 28, 0);
  assert.ok(f.bodyFat > 24 && f.bodyFat < 33, 'female ' + f.bodyFat);
  for (const k of Object.keys(m)) assert.ok(Number.isFinite(m[k]), k);
});
await t('guest record claim', async () => {
  const g = await api('POST', '/app/bodyData', { weight: 80, impedance: 480, source: 'guest' }, tok);
  assert.equal(g.data.memberId, null);
  assert.equal((await api('GET', '/app/bodyData/unclaimed', null, tok)).data.length, 1);
  const c = await api('POST', '/app/bodyData/claim', { id: g.data.id, memberId }, tok);
  assert.equal(c.data.memberId, memberId); assert.ok(c.data.metrics.bodyFat);
});
await t('goals', async () => {
  assert.equal((await api('POST', '/app/goal', { memberId, type: 'weight', target: 5 }, tok)).code, 1);
  assert.equal((await api('POST', '/app/goal', { memberId, type: 'height', target: 70 }, tok)).code, 1);
  const g = await api('POST', '/app/goal', { memberId, type: 'weight', target: 70 }, tok);
  assert.equal(g.code, 0); assert.ok(g.data.start > 70);
  const r = await api('GET', `/app/goal?memberId=${memberId}`, null, tok);
  assert.equal(r.data.target, 70);
  assert.equal((await api('POST', '/app/goal/delete', { memberId }, tok)).code, 0);
  assert.equal((await api('GET', `/app/goal?memberId=${memberId}`, null, tok)).data, null);
  assert.equal((await api('GET', '/app/goal?memberId=99999', null, tok)).code, 404);
});
await t('weekly summary', async () => {
  const today = new Date().setHours(0, 0, 0, 0);
  const DAY = 86400e3;
  const mem = (await api('POST', '/app/memberDevice/add', { name: 'Sum', height: 175, birthday: '1990-01-01', gender: 1 }, tok)).data.id;
  for (const [d, w] of [[0, 80], [1, 80.5], [2, 81], [9, 83]]) await api('POST', '/app/bodyData', { weight: w, impedance: 500, memberId: mem, ts: today + 3600e3 - d * DAY }, tok);
  const s = (await api('GET', `/app/summary/weekly?memberId=${mem}&today=${today}`, null, tok)).data;
  assert.equal(s.weighIns, 3); assert.equal(s.streak, 3);
  assert.equal(s.daysWithWeighIn.filter(Boolean).length, 3);
  assert.equal(s.changeKg, -1); // 81 -> 80, oldest to newest
  assert.equal(s.avgWeight, 80.5); assert.equal(s.prevAvgWeight, 83);
  assert.ok(s.avgBodyFat > 5);
  const e = (await api('GET', `/app/summary/weekly?memberId=${memberId}&today=${today - 400 * DAY}`, null, tok)).data;
  assert.equal(e.weighIns, 0); assert.equal(e.streak, 0); assert.equal(e.avgWeight, null);
});
await t('data sharing', async () => {
  assert.equal((await api('POST', '/app/bodyDataShare', { email: 'c@d.co', memberId }, tok)).code, 0);
  const o = await api('GET', '/app/bodyDataShare/otherList', null, tok2);
  assert.equal(o.data.length, 1);
  const d = await api('GET', `/app/bodyDataShare/bodyData/list?ownerId=${o.data[0].ownerId}&memberId=${memberId}`, null, tok2);
  assert.ok(d.data.length >= 2);
  assert.equal((await api('GET', `/app/bodyDataShare/bodyData/list?ownerId=${o.data[0].ownerId}&memberId=999`, null, tok2)).code, 403);
});
await t('food', async () => {
  const f = await api('GET', '/food/scale/defaultFood', null, tok);
  assert.ok(f.data.length >= 20);
  const apple = f.data.find((x) => x.name === 'Apple');
  const u = await api('POST', '/food/record/upload', { name: 'Apple', grams: 200, foodId: apple.id, meal: 'lunch' }, tok);
  assert.equal(u.data.kcal, 104);
  const day = await api('GET', '/food/record/countTodayNutrition', null, tok);
  assert.equal(day.data.kcal, 104);
  assert.equal((await api('GET', '/food/record/countLastSevenCalorie', null, tok)).data.length, 7);
  assert.equal((await api('POST', '/food/record/upload', { name: 'x', grams: 0 }, tok)).code, 1);
});
await t('offline replay is idempotent', async () => {
  const body = { weight: 70.1, impedance: 500, memberId, source: 'scale', clientId: 'abc-123', ts: Date.now() - 5000 };
  const a = await api('POST', '/app/bodyData', body, tok);
  const b = await api('POST', '/app/bodyData', body, tok);
  assert.equal(a.data.id, b.data.id);
  const f = { name: 'Egg', grams: 100, per100: { kcal: 155, protein: 13, fat: 11, carb: 1 }, clientId: 'food-1' };
  const f1 = await api('POST', '/food/record/upload', f, tok);
  const f2 = await api('POST', '/food/record/upload', f, tok);
  assert.equal(f1.data.id, f2.data.id);
});
await t('virtual scale hub', async () => {
  const wsBase = base.replace('http', 'ws') + '/ws';
  const next = (ws) => new Promise((res) => ws.addEventListener('message', (e) => res(JSON.parse(e.data)), { once: true }));
  const scale = new WebSocket(wsBase); await new Promise((r) => (scale.onopen = r));
  scale.send(JSON.stringify({ type: 'hello', role: 'scale', mac: 'AA:00', name: 'CF568_G', kind: 'body' })); await next(scale);
  const app = new WebSocket(wsBase); await new Promise((r) => (app.onopen = r));
  app.send(JSON.stringify({ type: 'hello', role: 'app' })); await next(app);
  app.send(JSON.stringify({ type: 'list' }));
  const dl = await next(app); assert.equal(dl.devices[0].mac, 'AA:00');
  app.send(JSON.stringify({ type: 'connect', mac: 'AA:00' }));
  assert.equal((await next(app)).type, 'connected');
  const got = next(app);
  scale.send(JSON.stringify({ type: 'reading', value: 70, unit: 'kg', stable: true, stage: 'done', impedance: 500 }));
  assert.equal((await got).impedance, 500);
  scale.close(); app.close();
});
await t('messages: goal, streak, weekly digest', async () => {
  const m0 = (await api('GET', '/app/messages', null, tok)).data;
  assert.ok(Array.isArray(m0.messages));
  const mem = (await api('POST', '/app/memberDevice/add', { name: 'Goalie', height: 170, birthday: '1990-01-01', gender: 1 }, tok)).data.id;
  await api('POST', '/app/bodyData', { weight: 80, impedance: 500, memberId: mem }, tok);
  assert.equal((await api('POST', '/app/goal', { memberId: mem, type: 'weight', target: 75 }, tok)).code, 0);
  await api('POST', '/app/bodyData', { weight: 74.5, impedance: 500, memberId: mem, ts: Date.now() + 1000 }, tok);
  const m1 = (await api('GET', '/app/messages', null, tok)).data;
  const goal = m1.messages.find((x) => x.kind === 'goal');
  assert.ok(goal, 'goal message'); assert.ok(m1.unread >= 1);
  // same goal does not notify twice
  await api('POST', '/app/bodyData', { weight: 74.0, impedance: 500, memberId: mem, ts: Date.now() + 2000 }, tok);
  const m2 = (await api('GET', '/app/messages', null, tok)).data;
  assert.equal(m2.messages.filter((x) => x.kind === 'goal').length, 1);
  assert.equal((await api('POST', '/app/messages/read', { id: goal.id }, tok)).code, 0);
  assert.equal((await api('POST', '/app/messages/read', {}, tok)).code, 0);
  assert.equal((await api('GET', '/app/messages', null, tok)).data.unread, 0);
  assert.equal((await api('POST', '/app/messages/delete', { id: goal.id }, tok)).code, 0);
});
await t('firmware registry', async () => {
  const old = (await api('GET', '/app/xinmiaoProductHardwareVersion/judgeVersion?version=1.0.3', null, tok)).data;
  assert.equal(old.upToDate, false); assert.equal(old.latest, '1.1.0');
  const cur = (await api('GET', '/app/xinmiaoProductHardwareVersion/judgeVersion?version=1.1.0', null, tok)).data;
  assert.equal(cur.upToDate, true);
  const bin = Buffer.from(await (await fetch(base + old.url)).arrayBuffer());
  assert.equal(bin.length, old.size);
  const { createHash } = await import('node:crypto');
  assert.equal(createHash('sha256').update(bin).digest('hex'), old.sha256);
  assert.equal((await fetch(base + '/firmware/evil.bin')).status, 404);
});
await t('barcode lookup', async () => {
  const f = await api('GET', '/food/barcode?code=5000000000017', null, tok);
  assert.equal(f.data.name, 'Apple');
  assert.equal((await api('GET', '/food/barcode?code=1234567890123', null, tok)).code, 404);
  assert.equal((await api('GET', '/food/barcode?code=abc', null, tok)).code, 1);
});
await t('coffee brews', async () => {
  assert.equal((await api('POST', '/app/brew', { dose: 0, water: 300 }, tok)).code, 1);
  assert.equal((await api('POST', '/app/brew', { dose: 18, water: 300, rating: 9 }, tok)).code, 1);
  const b = await api('POST', '/app/brew', { name: 'V60', dose: 18, water: 288, seconds: 175, rating: 4, notes: 'bright' }, tok);
  assert.equal(b.code, 0); assert.equal(b.data.ratio, 16);
  const l = (await api('GET', '/app/brew/list', null, tok)).data;
  assert.equal(l[0].name, 'V60');
  assert.equal((await api('POST', '/app/brew/delete', { id: b.data.id }, tok)).code, 0);
  assert.equal((await api('GET', '/app/brew/list', null, tok)).data.length, 0);
});
await t('QR login flow', async () => {
  const c = (await api('POST', '/app/user/qrCode/create', {})).data;
  assert.match(c.payload, /^uhqr:[0-9a-f]{24}$/);
  assert.equal((await api('GET', `/app/user/qrCode/status?id=${c.id}`)).data.status, 'waiting');
  const svg = await (await fetch(base + '/app/qr?text=' + encodeURIComponent(c.payload))).text();
  assert.ok(svg.includes('<svg'));
  // confirming before scanning is refused; a different user cannot confirm someone else's scan
  assert.equal((await api('POST', '/app/user/qrCode/confirm', { id: c.payload }, tok)).code, 1);
  assert.equal((await api('POST', '/app/user/qrCode/scan', { id: c.payload }, tok)).code, 0);
  assert.equal((await api('GET', `/app/user/qrCode/status?id=${c.id}`)).data.status, 'scanned');
  assert.equal((await api('POST', '/app/user/qrCode/scan', { id: c.payload }, tok)).code, 1); // already used
  assert.equal((await api('POST', '/app/user/qrCode/confirm', { id: c.payload }, tok2)).code, 1);
  assert.equal((await api('POST', '/app/user/qrCode/confirm', { id: c.payload }, tok)).code, 0);
  const done = (await api('GET', `/app/user/qrCode/status?id=${c.id}`)).data;
  assert.equal(done.status, 'confirmed'); assert.ok(done.accessToken);
  assert.equal((await api('GET', '/app/user', null, done.accessToken)).code, 0);
  assert.equal((await api('GET', `/app/user/qrCode/status?id=${c.id}`)).data.status, 'done'); // tokens are handed out once
  assert.equal((await api('GET', '/app/user/qrCode/status?id=nope')).data.status, 'expired');
});
await t('delete + logoff', async () => {
  assert.equal((await api('POST', '/app/bodyData/delete', { id: recId }, tok)).code, 0);
  assert.equal((await api('POST', '/app/user/logOff', { password: 'bad' }, tok)).code, 1);
  assert.equal((await api('POST', '/app/user/logOff', { password: 'newpass1' }, tok)).code, 0);
  assert.equal((await api('GET', '/app/user', null, tok)).code, 401);
});
server.close();
try { fs.rmSync(process.env.DB_FILE, { force: true }); } catch {}
console.log(process.exitCode ? 'SOME TESTS FAILED' : `all ${n} tests passed`);
setTimeout(() => process.exit(process.exitCode || 0), 100);
