# Crownspire Nakama Runtime (LOCAL DEVELOPMENT)

Phase 3+4 server runtime for identity, alliances, roster/ranks/applications/invites, Alliance Chat authority, and chat reports.

## Start

```bash
cd server
npm install
npm run build
docker compose up -d --build
node scripts/phase4_rpc_test.mjs
```

## Dual-state

| Authority | Systems |
|-----------|---------|
| `AllianceBackend` + Nakama Groups | membership, roster, ranks, applications, invites, Alliance Chat |
| Local `AllianceState` | research, help, treasury (unmigrated) |

When authenticated, AllianceScreen membership UI uses AllianceBackend only.

## Layout

```
server/
  src/index.ts          TypeScript runtime source
  build/index.js        Compiled module loaded by Nakama
  local.yml             LOCAL-ONLY Nakama config
  docker-compose.yml    Local stack (reuses Postgres volume)
  Dockerfile            Builds runtime into nakama:3.40.0
  package.json
  tsconfig.json
```

## Start (LOCAL)

```bash
cd server
npm install
npm run build
docker compose up -d --build
```

Preserves Postgres via external volume `crownspire-nakama_crownspire_nakama_data`.

- API: `http://127.0.0.1:7350`
- Console: `http://127.0.0.1:7351`
- Server key: `defaultkey` (**local only — never for production**)

## RPCs

| RPC | Purpose |
|-----|---------|
| `crownspire_get_profile` | Load/create Crownspire profile; sync alliance from group membership |
| `crownspire_set_display_name` | Validated display name (rate-limited) |
| `crownspire_get_public_profile` | Minimal public identity |
| `crownspire_create_alliance` | Private Nakama Group + R5 creator |
| `crownspire_join_alliance` | Join request (pending until approve) |
| `crownspire_list_alliance_join_requests` | Admin list |
| `crownspire_approve_alliance_join` | Approve → R2 member |
| `crownspire_kick_alliance_member` | Kick + clear profile alliance fields |
| `crownspire_leave_alliance` | Leave + clear profile |
| `crownspire_chat_report` | Evidence-only moderation report |

## Dual-state risk (temporary)

| System | Authority |
|--------|-----------|
| `AllianceBackend` + Nakama Groups | Multiplayer membership, Alliance Chat, tags |
| Local `AllianceState` / AllianceScreen | Local single-player alliance UX only |

Do **not** merge these until a dedicated migration phase. Chat authorization must never use local `AllianceState`.

## Rank mapping foundation

| Nakama group state | Crownspire rank |
|--------------------|-----------------|
| Superadmin (0) | R5 |
| Admin (1) | R4 |
| Member (2) | R2 (default) |

Fine ranks R1–R5 also stored in `crownspire_alliance_ranks` for future permission matrix migration.

## Rate limits (server)

- Display name change: 60s
- Chat report: 10s
- Alliance create: 30s

Chat message flood: client 1.5s cooldown exists; Nakama channel ACLs enforce membership. Production should add a runtime `before` hook for chat writes if abuse appears in beta.

## Integration test

```bash
cd server
node scripts/phase3_rpc_test.mjs
```

Godot two-user chat smoke: set `CROWNSPIR_PHASE3_SMOKE=1` (see `ChatManager.run_phase3_alliance_smoke_test`).
