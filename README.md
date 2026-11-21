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
- **Proven (server logic):** 28 Jac tests pass (`manager.jac` 21, `util.jac` 4, `token_auth` 3). 16 scenario tests in `parity/` pass
  against the ORIGINAL Python app (on top of the original's own 240-test suite, run green first); the Jac tests encode the same
  expectations (statuses, defaults, 422 rejections, ordering incl. the reorder tie-break, patch/`null` semantics, tag replacement,
  `updated_at` not bumped by a tags-only update, reset/duplicate file effects, settings masking, artifact paths).
  *The parity is by hand-written mirrored scenarios, not a differential run of both servers against each other.*
- **Jac tests with no counterpart in the original scenarios:** launch/stop lifecycle and delete-while-running (launch is simulated),
  duplicate-of-a-running-source → 409, artifact count/size quotas, the plugin's 3 tests, `util` tests.
- **Proven (toolchain path), earlier vertical slice:** a 3-file api+site app (same archwire shape, `[npm.web]` pinned to vite 7)
  built, served `POST /__jac/call/api/profiles/...`, kept its graph across a restart and rendered the list in `neojac browse`.
  That slice was replaced by the real app *before the first commit*, so its files and outputs are **not preserved in this repo**:
  treat it as an observation from the session, not a reproducible artifact.
- **Not proven:** the *built* real app was never run (native build exceeds this VM's memory, L-018): `/__jac/call/...` of the
  final server, `sign_in()` with `token_auth`, and the rendered page are unverified; the browser space is only type-checked.
  Launch/stop are simulated (state only).
- HTTP contract differs from the original by necessity (L-009/L-010): RPC endpoints, status carried in reply bodies.
- To run the server: `CLOAKBROWSER_MANAGER_DATA_DIR=/some/writable/dir` must be set (the original's Linux default `/data` is kept).

## To finish the proof (needs memory — please close VS Code, then say "go")
```sh
taskset -c 0 tools/guarded.sh notes/build.log 0 "neojac build manager"       # watchdog kills at <250 MB free
CLOAKBROWSER_MANAGER_DATA_DIR=/tmp/cbm AUTH_TOKEN=s3cret JAC_MANAGER_LISTEN=127.0.0.1:8311 dist/manager-linux-x86_64/manager &
curl -s -X POST :8311/__jac/call/api/manager/list_profiles -d '{}'      # expect 401 (no token)
curl -s -X POST :8311/__jac/auth/login -d '{"token":"s3cret"}'           # then Bearer calls: create, list, update {"proxy": null}
neojac browse open 127.0.0.1:8311/ ; neojac browse snapshot              # the page
```
