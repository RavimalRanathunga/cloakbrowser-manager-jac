# CloakBrowser Manager — ported to Jac (neojac 0.3.3)

A dogfooding port of `../CloakBrowser-Manager` (Python/FastAPI + React) to Jac, made to find neojac's bugs and gaps.
**Read `LIMITATIONS.md` first** — it is the main deliverable.

## Layout
| Path | What |
|---|---|
| `model.jac` | Reply/response types that cross server↔page |
| `util.jac` | pure helpers hand-ported from Python (`safe_filename`, `mask_key`, versions, sidebar width) |
| `manager.jac` | the server: profiles/tags/files/settings as a **graph** (`Profile`, `Tag`, `Artifact`, `Settings` nodes; typed edges `HasTag`, `HasFile`) under the operator's `root`; ids are `jid()`s, no SQL |
| `token_auth/` | custom `auth` plugin = the original's optional `AUTH_TOKEN` |
| `web.jac`, `pages/`, `ui/`, `styles/` | the browser space (React via neojac's `react` ui plugin) |
| `archwire.jac`, `jac.toml` | spaces, wires, npm tree (`[npm.web]`, made by `neojac absorb`), plugin binding |
| `ported/` | what `neojac port` produced from a slimmed pure subset (byte-identical output to Python) |
| `parity/` | the same scenarios run against the ORIGINAL Python app (FastAPI TestClient) |
| `repros/` | one folder per limitation with command + saved output |
| `tools/guarded.sh`, `notes/` | memory watchdog used on this 3.7 GB machine, and its logs |

## How it was made (neojac's own tools)
`neojac absorb` (package.json → `[npm.web]`), `neojac port` (only a pure subset ports, see L-001/L-002), then a hand-designed
graph-based app: `root`-persisted nodes/edges, walkers not needed (single-hop `[p ->:HasTag:->]` queries), `:protect` endpoints
with a custom `auth` plugin, a browser space.

## Run the checks (one heavy command at a time; on a 4 GB machine pin to one CPU)
```sh
neojac check manager.jac                 # server + tests, lint
neojac check --space site                # the browser space
taskset -c 0 neojac test manager.jac util.jac     # 25 tests
(cd token_auth && taskset -c 0 neojac test auth.jac)   # 3 tests
ORIGINAL_REPO=../CloakBrowser-Manager python3 -I -m pytest parity -q   # the scenarios, against the original: 16 passed
```

## What is and is not proven
- **Server logic (tests):** 28 Jac tests pass (`manager.jac` 21, `util.jac` 4, `token_auth` 3). 16 scenario tests in `parity/` pass
  against the ORIGINAL Python app (on top of the original's own 240-test suite, run green first); the Jac tests encode the same
  expectations (statuses, defaults, 422 rejections, ordering incl. the reorder tie-break, patch/`null` semantics, tag replacement,
  `updated_at` not bumped by a tags-only update, reset/duplicate file effects, settings masking, artifact paths).
  *Parity is by hand-written mirrored scenarios, not a differential run of both servers.*
- **The built app was run** (`neojac build manager`, one CPU, memory watchdog; VS Code closed). Evidence is in `notes/`:
  `smoke.txt` (HTTP: 401 without/with wrong token, login right/wrong, Bearer and `auth_token` cookie accepted, create, `proxy: null`
  update clears the proxy, upload), `smoke2.txt` (data survives a restart), `browse-*.txt` (headless Chrome driven by `neojac browse`:
  plugin-generated sign-in form, wrong token → "Invalid token", right token → profile list, select, Launch/Stop, create via the form
  with `Shop "A" \ test`, Duplicate, Settings → masked key `cb_ab…mnop`, Delete, no console errors).
- **Not proven / not ported:** launch/stop are simulated (state only, no browser, no VNC/CDP); file upload/download UI, drag-reorder
  and noVNC are not in the UI; WebSocket proxies, proxy test, update check not ported (see the matrix in `LIMITATIONS.md`).
- Jac tests with no counterpart in the original scenarios: launch lifecycle, delete-while-running, duplicate-of-running → 409,
  artifact quotas, plugin and helper tests.
- **API differences by necessity:** RPC endpoints (`POST /__jac/call/api/manager/<fn>`), status carried in reply bodies (L-009/L-010),
  `""` instead of `null` for optional strings (L-026), files ≤ ~8 MiB (L-014).

## Run it
```sh
# build needs ~2.2 GB system peak: close the IDE; on a 4 GB machine:
taskset -c 0 tools/guarded.sh notes/build.log 0 "neojac build manager"
CLOAKBROWSER_MANAGER_DATA_DIR=/tmp/cbm/files JAC_MANAGER_DATA=/tmp/cbm/data JAC_MANAGER_LISTEN=127.0.0.1:8311 \
  AUTH_TOKEN=s3cret dist/manager-linux-x86_64/manager        # omit AUTH_TOKEN for the open local-dev mode
curl -s -X POST 127.0.0.1:8311/__jac/call/api/manager/list_profiles -d '{}'                       # 401
curl -s -H 'Authorization: Bearer s3cret' -X POST 127.0.0.1:8311/__jac/call/api/manager/list_profiles -d '{}'
neojac browse open 127.0.0.1:8311/ && neojac browse snapshot
```
(`CLOAKBROWSER_MANAGER_DATA_DIR` must be writable; the original's Linux default is `/data`.)
