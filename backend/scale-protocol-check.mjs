// Drives the virtual scale (open http://localhost:3000/simulator in a browser first, with the backend running) through
// info, display settings, Wi-Fi, fingerprint users and the firmware update. Run: node scale-protocol-check.mjs
import crypto from 'node:crypto';
const BASE = 'http://localhost:3000';
const ws = new WebSocket('ws://localhost:3000/ws');
const events = [];
let resolveNext;
const wait = (pred, ms = 9000) => new Promise((res, rej) => {
  const t = setTimeout(() => rej(new Error('timeout waiting for event')), ms);
  const check = (e) => { if (pred(e)) { clearTimeout(t); res(e); return true; } return false; };
  for (const e of events) if (check(e)) return;
  resolveNext = check;
});
const open = new Promise((r) => (ws.onopen = r));
ws.onmessage = (e) => {
  const m = JSON.parse(e.data);
  if (m.type === 'event') { const ev = { event: m.event, data: m.data }; events.push(ev); if (resolveNext && resolveNext(ev)) resolveNext = null; }
  else if (m.type === 'devices') globalThis.devs = m.devices; else if (m.type === 'connected') globalThis.conn = m.device;
};
const cmd = (c, d = {}) => ws.send(JSON.stringify({ type: 'cmd', cmd: c, ...d }));
const clear = () => (events.length = 0);
const out = [];
const ok = (name, cond, extra = '') => { out.push(`${cond ? 'PASS' : 'FAIL'}  ${name} ${extra}`); };

await open;
ws.send(JSON.stringify({ type: 'hello', role: 'app' }));
await new Promise((r) => setTimeout(r, 200));
ws.send(JSON.stringify({ type: 'list' })); await new Promise((r) => setTimeout(r, 400));
const dev = (globalThis.devs || []).find((d) => d.kind === 'body');
ok('scale found with caps', !!dev && dev.caps.includes('wifi') && dev.caps.includes('fingerprint'), JSON.stringify(dev));
ws.send(JSON.stringify({ type: 'connect', mac: dev.mac })); await new Promise((r) => setTimeout(r, 400));

clear(); cmd('info'); let e = await wait((x) => x.event === 'info');
ok('info', e.data.fw === '1.0.3', JSON.stringify(e.data));

cmd('light', { color: '#f43f31' }); cmd('brightness', { value: 30 }); cmd('language', { value: 'de' }); await new Promise((r) => setTimeout(r, 200));
clear(); cmd('info'); e = await wait((x) => x.event === 'info');
ok('display settings applied', e.data.light === '#f43f31' && e.data.brightness === 30 && e.data.language === 'de', JSON.stringify(e.data));

clear(); cmd('wifiScan'); e = await wait((x) => x.event === 'wifiList');
ok('wifi scan', e.data.networks.some((n) => n.ssid === 'HomeWiFi'), e.data.networks.map((n) => n.ssid).join(','));
for (const [ssid, pw, expected] of [['HomeWiFi', 'wrong', 'wrong_password'], ['Office5G', 'office5g', 'unsupported_5ghz'], ['Nope', '', 'not_found'], ['CafeGuest', '', 'connected'], ['HomeWiFi', 'homepass123', 'connected']]) {
  clear(); cmd('wifiConnect', { ssid, password: pw });
  e = await wait((x) => x.event === 'wifiStatus' && x.data.state !== 'connecting', 6000);
  const got = e.data.state === 'connected' ? 'connected' : e.data.reason;
  ok(`wifi ${ssid}/${pw || '-'} -> ${expected}`, got === expected, got);
}
clear(); cmd('info'); e = await wait((x) => x.event === 'info'); ok('wifi remembered', e.data.wifi === 'HomeWiFi');

clear(); cmd('fingerList'); e = await wait((x) => x.event === 'fingerUsers'); ok('finger list', e.data.users.length === 1);
clear(); cmd('fingerEnroll', { name: 'Sara' });
e = await wait((x) => x.event === 'fingerUsers', 8000);
ok('finger enroll (3 progress steps)', events.filter((x) => x.event === 'fingerProgress').length === 3 && e.data.users.length === 2 && e.data.added === 2);
for (const n of ['A', 'B', 'C']) { clear(); cmd('fingerEnroll', { name: n }); await wait((x) => x.event === 'fingerUsers' || x.event === 'fingerError', 8000); }
clear(); cmd('fingerEnroll', { name: 'overflow' }); e = await wait((x) => x.event === 'fingerError'); ok('finger slot limit (5)', e.data.reason === 'full');
clear(); cmd('fingerDelete', { id: 2 }); e = await wait((x) => x.event === 'fingerUsers'); ok('finger delete', !e.data.users.some((u) => u.id === 2));

// firmware: ask the backend, download, verify, stream to the scale
const login = await (await fetch(BASE + '/app/user/login', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ email: 'demo@unique.test', password: 'demo1234' }) })).json();
const tok = login.data.accessToken;
const meta = (await (await fetch(BASE + '/app/xinmiaoProductHardwareVersion/judgeVersion?version=1.0.3', { headers: { 'Access-Token': tok } })).json()).data;
ok('firmware update offered', meta.upToDate === false);
const bin = Buffer.from(await (await fetch(BASE + meta.url)).arrayBuffer());
ok('firmware checksum', crypto.createHash('sha256').update(bin).digest('hex') === meta.sha256);
clear(); cmd('fwStart', { version: meta.latest, size: bin.length });
for (let o = 0; o < bin.length; o += 4096) { cmd('fwChunk', { seq: o / 4096, data: bin.subarray(o, o + 4096).toString('base64') }); await new Promise((r) => setTimeout(r, 15)); }
cmd('fwEnd', { sha256: meta.sha256 });
e = await wait((x) => x.event === 'fwDone', 10000);
ok('firmware installed', e.data.ok === true && e.data.version === '1.1.0', JSON.stringify(e.data));
ok('firmware progress reported', events.filter((x) => x.event === 'fwProgress').length > 5);
// corrupted image is refused
clear(); cmd('fwStart', { version: '9.9.9', size: 100 }); cmd('fwChunk', { seq: 0, data: Buffer.alloc(100, 1).toString('base64') }); cmd('fwEnd', { sha256: 'deadbeef' });
e = await wait((x) => x.event === 'fwDone', 8000); ok('corrupt firmware rejected', e.data.ok === false && e.data.reason === 'checksum');
clear(); cmd('info'); e = await wait((x) => x.event === 'info'); ok('version stays 1.1.0 after bad image', e.data.fw === '1.1.0');

console.log(out.join('\n'));
console.log(out.some((l) => l.startsWith('FAIL')) ? 'SOME FAILED' : 'ALL PASSED');
process.exit(0);
