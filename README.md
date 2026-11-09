# Unique Health clone (local test build)

Flutter app + Node backend + virtual scale. Nothing external is used (no Supabase, Firebase or Lefu servers).

```
clone/
  backend/   Node 22+ API + SQLite + WebSocket hub + virtual scale web page
  app/       Flutter app (Android + Windows)
```

## Run it

1. Backend (also serves the virtual scale):
   ```
   cd backend
   npm install
   npm start
   ```
   - API: http://localhost:3000
   - Virtual scale: http://localhost:3000/simulator
   - Demo accounts: `demo@unique.test / demo1234` (30 days of data, 2 profiles), `friend@unique.test / friend1234`
2. App:
   ```
   cd app
   flutter pub get
   flutter run -d windows        # uses http://localhost:3000
   flutter run                   # Android emulator uses http://10.0.2.2:3000
   ```
   On a real phone, set the server to `http://<your-PC-LAN-IP>:3000` (login screen or Mine > Settings) and allow port 3000 in the Windows firewall.
3. Pair: open the virtual scale page, then in the app go to Devices > Add device > Add. Tap Measure, then press **Step on** in the simulator.

## Virtual scale
One scale at a time. Switch it between a body-fat scale (weight + impedance) and a kitchen scale (grams) on the page. Behaviors: normal, impedance error (no foot contact), never stabilises. Kitchen scale has Tare.

## Features
Accounts (sign up, sign in, token refresh, forgot password with an on-screen code, change password, delete account) · family profiles · device binding, rename, unit, sharing between accounts, firmware check stub · live measurement, guest mode, baby mode, manual entry, impedance-error handling · 14 body metrics with level ratings and advice · trends, history, compare two records, assign guest readings · sharing a profile's data with another account · food scale diary with nutrition totals and a 7-day chart · kg/lb, dark mode.

## Tests
```
cd backend && npm test                     # 12 API + hub tests
cd app && flutter analyze && flutter test  # unit test; e2e test runs if a backend is on :3100
```
E2E: `PORT=3100 DB_FILE=/tmp/e2e.db node backend/server.js` then `flutter test test/e2e_test.dart`.

## Known limits
- **Real Lefu scales will not connect.** The app talks to the virtual scale over WebSocket. Lefu's Bluetooth protocol is proprietary and not implemented. `lib/core/scale_transport.dart` defines a `ScaleTransport` interface so a real BLE transport can be added (standard Weight Scale 0x181D / Body Composition 0x181B, or a decoded vendor protocol).
- Body metrics are estimates from generic formulas, not Lefu's algorithm and not medical advice.
- Not built: Fitbit sync (needs your own Fitbit developer app), Google Fit (being retired by Google), direct Samsung Health access, real push notifications, SMS or email delivery (reset codes are shown on screen), and the proprietary Lefu scale protocol.
- Backend is for testing: HTTP only, a dev token secret (set `SECRET`), no rate limiting.
- Verified: backend tests, Flutter analyze (0 errors), unit, offline and live e2e tests, the Windows debug build, and the main screens in a browser preview. Not run on an Android device: real Bluetooth, camera scanning, reminders and Health Connect are untested on hardware.

## Also included
- Body composition uses published equations (Sun 2003, Janssen 2000, Deurenberg 1991, Watson 1980, Mifflin-St Jeor) and ratings with the original's level names and colours. Bone, protein, visceral fat, body age and score remain heuristic estimates.
- Goals, weekly summary and streaks; offline mode with a sync outbox (idempotent replays); real Bluetooth for standard Weight Scale / Body Composition scales (phone builds only, untested on hardware).
- Virtual scale extras: coffee scale, Wi-Fi setup, fingerprint users, display settings, firmware update. Check them with `node backend/scale-protocol-check.mjs` while `/simulator` is open.
- Message center, QR login (`/web` page), device QR binding, food barcode lookup, weigh-in reminders, Health Connect export, CSV export, 7 UI languages (English, Spanish, French, German, Arabic, Hindi, Chinese).
- Android needs `flutter doctor --android-licenses` accepted once before an APK can be built.
