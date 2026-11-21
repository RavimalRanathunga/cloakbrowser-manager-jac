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
- **Proven:** 28 Jac tests pass. Their expectations (statuses, defaults, validation, ordering incl. the reorder tie-break,
  patch semantics, tag replacement, reset/duplicate file effects, settings masking, artifact paths/quotas) are the same scenarios
  that pass against the original (`parity/`, 16 passed, on top of the original's own 240-test baseline).
- **Not proven:** the built app has not been run (the native build exceeds this VM's memory budget, L-018), so the HTTP surface
  (`/__jac/call/...`), `sign_in()` and the rendered page are unverified here. Launch/stop are simulated.
- HTTP contract differs from the original by necessity (L-009/L-010): RPC endpoints, status carried in reply bodies.
