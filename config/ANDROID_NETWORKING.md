# Crownspire Android / mobile networking notes (BETA)

## Why Android showed "Disconnected"

1. Release builds skipped Nakama entirely (`OS.is_debug_build()` early-return).
2. Host was hardcoded to `127.0.0.1` (the phone itself, not your PC).
3. Internet permission needed to be explicit in the Android export preset.

## Fix

- `NakamaConnection` always connects (debug + release).
- Host resolution:
  - Desktop: `config/nakama_client.cfg` → `[server] host` (default `127.0.0.1`)
  - Android/iOS: `[server] mobile_host` (your PC LAN IP)
  - Optional override: `user://nakama_config.cfg` or env `CROWNSPIR_NAKAMA_HOST`
- Auto-reconnect on disconnect and when the app resumes.
- Status labels: Connecting… / Connected / Reconnecting… / Offline

## Before testing on a phone

1. PC and phone on the same Wi‑Fi.
2. Update `mobile_host` in `config/nakama_client.cfg` to your current LAN IP (`ipconfig`).
3. Ensure Nakama is running (`server/docker compose up -d`) and ports `7350` are reachable.
4. Windows Firewall: allow inbound TCP 7350 for Docker/Nakama if prompted.
5. Re-export the Android APK after changing `mobile_host`.

## Quick per-device override (no rebuild)

Create `user://nakama_config.cfg` on the device (via debug) with:

```
[server]
mobile_host="192.168.x.x"
host="192.168.x.x"
port=7350
scheme="http"
server_key="defaultkey"
```

Do **not** put `host="127.0.0.1"` in the device override — on Android that used to wipe `mobile_host`.

## Log lines to expect on Android

```
[Nakama] Config loaded host=127.0.0.1 mobile_host=192.168.x.x selected_host=192.168.x.x platform=Android mobile=true ...
[Nakama] Final endpoint before create_client: http://192.168.x.x:7350 (platform=Android mobile=true)
[Nakama] Connecting to http://192.168.x.x:7350 ...
```
