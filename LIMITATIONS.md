# neojac limitations found while porting CloakBrowser-Manager to Jac

Compiler under test: **neojac 0.3.3 (linux-x86_64, 98a4abf03de2)**, installed with the official
`install.sh` on 2026-11-21. Sources of knowledge: neojac's own docs / skills / `help` / diagnostics and the
observed behaviour of the compiler. No compiler source was read; any cause is marked **(guess)**.

Port target: `../CloakBrowser-Manager` (FastAPI backend ~5k lines + React/Vite frontend ~4.5k lines).
Test machine: WSL2, **3.7 GB RAM / 1 GB swap, 16 logical CPUs**, Linux x86_64.

Severity: **blocker** (cannot do what the app needs) / **major** (needs a large workaround) /
**minor** (annoyance, wrong/missing docs). Every entry has a repro under `repros/` (command + saved output)
unless marked *docs-only*. Entries are appended as they are hit.

---

## A. `neojac port` / `neojac absorb`

### L-001 `port` refuses every real file of the backend, whole (blocker for "port first")
- `neojac port --check ../CloakBrowser-Manager/backend` → **23 sources refused** (the 13 non-empty modules + the 10 test
  files), *nothing written* (raw output: `repros/r07-port-raw/backend.txt`). A file ports whole or not at all, so one `try` discards 1900 lines. Even 39–117 line files
  (`env_file.py`, `settings_store.py`, `runtime.py`) are refused.
- Refusal tally over the backend (E4001/E4005):

  | count | construct refused |
  |---|---|
  | 160 | class-level annotated attribute (every Pydantic model / dataclass field) |
  | 50 + 21 | `async def` (functions, methods) |
  | 42 | module-level name bound by code and used by functions (`logger = ...`, `X = os.environ.get(..)`, `re.compile(..)`) — E4005 |
  | 31 | `try` / `except` / `finally` |
  | 17 | relative import (`from . import x`) |
  | 16 | `with` |
  | 8 | bytes literal |
  | 7 | `*args` / `**kwargs` / keyword-only parameters |
  | 6 + 6 | import inside a function; function inside a function |
  | 6 | `*` unpack in a literal |
  | 5 + 3 | decorators / class decorators (`@app.get`, `@dataclass`, `@contextmanager`) |
  | 4 + 2 | `**` argument / `**` dict item |
  | 3 | `global x` |
  | 2 + 1 | `lambda`; non-`self` first parameter (`@classmethod`); multi-target assignment |
  | 1 | non-constant default (`def f(path: Path = _ENV_PATH)`) — E4005 |
- Consequence: the backend was hand-written as idiomatic Jac; `port` produced nothing from the real sources.
  Raw output: `repros/r07-port-raw/backend.txt` (the tally above was counted from it).

### L-002 `port` succeeds on a slimmed pure subset — but its output fails the project's default `check`
- `ported/src/pure.py` (4 pure helpers lifted from `main.py`, rewritten to port's core) → `neojac port` wrote
  `ported/pure.jac`; `neojac run` output is **byte-identical** to `python3` (`ported/result.txt`). Good. Every
  parameter/return/local is typed `any` (documented).
- Re-run in a **fresh project whose `jac.toml` has no `[check.lint]`** (`ported/fresh-default-lint.txt`): `port` exits 0 and writes
  `pure.jac`, then `neojac check pure.jac` → **5 errors** (W3051 docstring, 4× W3055 "body belongs in an impl"). `neojac docs port`
  says port's output "is checked before it is written"; whatever it checks, it is not the project's default lint, so the
  first `neojac check` after every port fails. `fmt --fix` makes it pass by **deleting the docstring and every comment**
  and moving bodies to `impl/pure.impl.jac` (`ported/impl/`, and git history of `ported/pure.jac`) — source comments are lost.
- Minor: port emitted `parts.append(`int(part))` — a backtick-escaped `int` — for `int(part)`.

### L-003 `port` cannot read the React/TS frontend (blocker for "port the UI")
- `.tsx` is not a port source: `neojac port --check Hello.tsx` → `E4004 ... is no source port translates:
  one is known by its extension, one of .c .cc .cjs .cpp .cxx .h .hpp .js .mjs .py .rs .ts` (`repros/r02-tsx/result.txt`).
  All 15 components of the app are `.tsx`.
- Plain `.ts` of the app (`lib/api.ts`, `hooks/useProfiles.ts`): `neojac port --check frontend/src` reports
  `tsc TS2304 Cannot find name 'fetch'/'File'`, `TS2835 relative import needs explicit file extension
  (moduleResolution node16/nodenext)`, `TS7006 implicit any`, `TS2307 cannot find 'vitest'`: port type-checks
  with its own tsc settings (no DOM lib, nodenext), not the project's `tsconfig.json`. **(guess)** a fixed config.
  Raw output: `repros/r07-port-raw/frontend-src.txt` (6 sources refused).

### L-004 `neojac absorb` is shallow (minor, mostly missing guidance)
- `neojac absorb dir --tree web` (exit 0) turns `package.json`/lock into `[npm.web]` + `jac.lock` and moves them
  to `eco/web`. It keeps the Node scripts (`vite`, `tsc -b && vite build`, `vitest`) and dev-deps (tailwind, vitest,
  jsdom, testing-library, typescript) verbatim and says nothing about which of those a Jac browser space can
  never use. It brings none of `vite.config.ts`, `tailwind.config.ts`, `postcss.config.js`, `index.html`, `tsconfig.json`.
- **Absorbed versions do not build** — see L-005.

### L-005 `@jac/vite` is incompatible with the Vite 8 / plugin-react 6 that `absorb` brought in (major)
- Absorbed `vite ^8.3.8` + `@vitejs/plugin-react ^6.3.0` → `neojac build manager`:
  `[plugin jac] TypeError: this.getWatchFiles is not a function at ... @jac/vite/index.js:126:40`
  (rolldown-based Vite 8). Repro: `repros/r04-vite8/{jac.toml.vite8,result.txt}`. Pinning `vite ^7.1.0` +
  `plugin-react ^5.0.0` (the versions in `neojac docs apps/index`) builds.
- No docs page states a supported Vite range (`neojac docs search vite` finds none), so this is only found by building.

---

## B. Docs / skills

### L-006 `writing-jac` skill says "`class` is not built yet" — it is
- `neojac skills writing-jac` rule 5: "`class` is not built yet: write `obj`." `neojac skills porting-from-python`
  says to write `class P { ... }`. Tested: `class P { has x: int = 0; def double -> int {...} }` builds and runs (`4`);
  `neojac check` only reports lint W3055. Repro `repros/r01-class/`.

### L-007 `neojac docs <module>` is a page lookup, not a module entry, for some modules (minor)
- `neojac docs uuid` prints the generic "Standard-library modules" page (the module is only a table row there);
  `neojac docs search uuid` is needed to learn it is "Nearly complete". `neojac docs re`/`json` have own pages.

### L-008 install.sh re-downloads the full release even when that version is installed (minor)
- `neojac --version` was already 0.3.3; the installer fetched "the latest version" (0.3.3) and downloaded the whole
  ~370 MB tarball again (>7 minutes here) before printing "installed". **(guess)** no installed-vs-latest check.

---

## C. Server/transport model (`apps/server`, `crossings`) — these shape the whole port

### L-009 `@restspec`: GET/POST only, no parameters — the original REST contract cannot be reproduced (major)
- Verified (`repros/r03-restspec/result.txt`): a `@restspec` function with a parameter →
  `E0109 comptime assertion failed: a function served at a path of its own takes no parameters`;
  `HTTPMethod.PUT` / `HTTPMethod.DELETE` → `E0108 cannot evaluate at compile time: neojac evaluates only enum members
  and methods as attributes` (misleading: the real reason is that `HTTPMethod` has only GET and POST).
- So no `/api/profiles/{id}`, no `PUT`/`DELETE`, no query strings, no response headers/cookies (`Set-Cookie` on login,
  `Content-Disposition` on download), no custom status codes (every success is 200 + JSON envelope). The Jac app's HTTP
  contract is `POST /__jac/call/<space>/<module>/<fn>` with `{"args":{...}}`. The original statuses (201/404/409/422/507)
  are carried inside a `status` field of each reply object instead. Parity is shown at the behaviour level (`parity/`).

### L-010 An endpoint cannot return an HTTP error; exceptions are opaque 500s (major) — *docs-only*
- `neojac docs apps/server`: a raising endpoint answers 500 `"<name> failed"`, detail only on the server's log; there
  is no way to answer 404/409 with a message. Every endpoint of the port therefore returns a reply object with `status`.

### L-011 BUG: `str | None` rejects `None`/JSON `null` as an argument (and see L-026 for results and the store); `int | None` accepts it (major)
- Docs: "`null` is `None` for a parameter whose type admits `None`". Observed (`repros/r05-probes/result.txt`, `result2.txt`):
  `def f(a: str | None = None)` called with `{"a": null}` → `400 rejected "expected a str, got None"`;
  `def f(a: str | None)` same; **but** `def f(n: int | None = None)` with `{"n": null}` → ok. Same for an `obj` field
  `proxy: str | None` → `".p.proxy: expected a str, got None"`. **(guess)** the str decoder runs before the `None` branch.
- The same goal (clear the proxy) is impossible through typed parameters: with `int | None = None`, absent and `null` are
  indistinguishable. The original `ProfileUpdate` relies on exactly this (`exclude_unset`). **Workaround:** update/create
  take the fields as a JSON *string* and `json.loads` it on the server.

### L-012 No free-form JSON value can cross (`any`, unions) (major)
- `def f(patch: dict[str, any])` → `E1308 'patch: dict[str, any]' is not sendable across a concurrency boundary`
  (`repros/r05-probes`, first check). Documented ("an `any`... a union of several types besides `None` is refused"), but
  it means partial-update payloads, heterogeneous JSON, and `Literal`-like unions all need a JSON string or an enum.

### L-013 Enums cross by member *name*; wrong member is a 400 (minor)
- Lowercase members (`enum Gpu { auto, nvidia }`) compile, so original values (`"auto"`) can match. A bad value →
  `400 "expected a member's name, got 'bogus'"` (original: pydantic 422 with a list). Fine; noted for parity.

### L-014 Binary payloads: hex JSON, 16 MiB body cap, no chunked bodies → files ≤ ~8 MiB (major)
- `bytes` crosses as a hex string (2× size) inside a JSON body capped at 16 MiB; `Transfer-Encoding: chunked` → 411.
  Verified (`repros/r05-probes/result3.txt`): 3 MB upload ok; 9 MB (18 MB JSON) → `413 the request's body is too large`;
  chunked → `411 a body is read by its Content-Length, not in chunks`. The original streams up to 256 MiB per file
  (`ARTIFACT_MAX_BYTES`), so Jac can hold ≈8 MiB per file. No `multipart`/raw-body upload, no `Content-Disposition` download.

### L-015 No documented way to serve a WebSocket (blocker for VNC/CDP proxying) — *docs-only*
- Searched, no documented way found: `neojac docs search websocket` → only a `WebSocket` *client* global in `hermes`
  (also `search "server-sent"`: nothing). The original's `/vnc` and `/cdp`
  WebSockets (and `/cdp/json/*` rewriting reverse proxy, clipboard relay) cannot be served; a custom `transport` plugin
  would mean writing an HTTP/WebSocket server by hand. Not attempted.

### L-016 Auth model: single shared token vs `accounts` plugin
- The original's optional single `AUTH_TOKEN` (Bearer header or `auth_token` cookie, `hmac.compare_digest`) has no
  counterpart in the standard `accounts` plugin (username/password + per-caller roots). `Auth.caller(headers)` in a custom
  plugin does implement it: see L-023 (works, unit-tested) and L-022 (token lives in `localStorage`, not an HttpOnly cookie).

---

## D. Python interop (the app's core is `cloakbrowser`, a PyPI package)

### L-017 `neojac install --pypi "cloakbrowser[geoip]"` records the requirement as `"[geoip]"` (minor, cosmetic)
- `repros/r06-cloakbrowser/jac.toml` ends with `cloakbrowser = "[geoip]"` — the extras bracket sits where the version spec
  belongs. I predicted later installs would choke on it; they **do not**: `neojac install` and `neojac install --frozen` both
  succeed (`repros/r06-cloakbrowser/reinstall.txt`, 26 distributions incl. `geoip2`, `cloakbrowser 0.7.3`). So the extra was
  honoured and the file is merely odd/misleading (a human or another tool reading `"[geoip]"` as a version would be wrong).
- Positive: `import cloakbrowser; print(cloakbrowser.__version__)` works from Jac → `0.7.3` (`import.txt`).

### L-025 Native `shutil.copytree(ignore=...)` is typed `set[str]`; CPython documents any iterable (minor)
- The original passes `ignore=lambda _d, names: [n for n in names if n in SKIP]` (a list). In Jac:
  `error[E1053]: copytree()'s parameter 'ignore' expects Callable[[str, list[str]], set[str]], found Callable[[str, list[str]], list[str]]`
  (seen while porting `_copy_browser_state`). Fixed by returning a set. `neojac docs library` says native modules have
  "the interface and behavior of CPython's"; this is a (small, deliberate-looking) tightening.

---

## E. Memory (this machine: 3.7 GB RAM) — the build toolchain does not fit next to an IDE

The user's WSL2 VM is capped at ~4 GB; VS Code's remote server alone holds ~2.2 GB. Measured with `/usr/bin/time -v`
and `/proc/meminfo`:

| operation | peak RSS (largest process) | notes |
|---|---|---|
| original app's Python tests (240 pytest tests) | **80 MB** | baseline: same behaviour spec |
| `neojac check <app>` (small) | 745 MB | |
| `neojac test util.jac` (1 small module) | 679 MB | |
| `neojac run` of a 3-line program importing `cloakbrowser` (CPython embedded) | 910 MB | |
| `neojac build` of a **trivial native app** (~25 lines) | **1.62–1.66 GB** | `repros/r05-probes` |
| `neojac install` (npm tree, 129 packages) | not measured, ~34 s | |
| a trivial native app server at rest | 211 MB RSS | |

### L-018 neojac's native build/test needs 1–1.7 GB in one process and does not fit next to an IDE on a 4 GB VM (major on small machines)
- Fact (solid): a **trivial 25-line app** `neojac build` has a single-process peak RSS of 1.62–1.66 GB (`/usr/bin/time -v`,
  `repros/r05-probes`, no CPU pinning, ~1 GB of other use on the machine).
- The WSL VM **crashed three times** (VM restarted, `uptime` 0 min, `/tmp` wiped): (1) running the r05 probe server
  (`neojac run api`, which builds) plus curl probes and 18 MB JSON bodies; (2) an unguarded `neojac build manager` with VS Code
  holding ~2.2 GB; (3) the same build under my first watchdog (0.5 s poll, `/tmp`-based, floor 350 MB). Cause = my guess (OOM),
  not proven: the VM dies, nothing is logged.
- Controlled runs afterwards (`tools/guarded.sh`: `taskset -c <cpus>`, polls `/proc/meminfo` every 0.2 s, kills the process group
  below the floor; logs in `notes/`). These runs differ in cache state and baseline, so they do **not** isolate a cause:

  | command | CPUs | floor | other use before | system peak | outcome |
  |---|---|---|---|---|---|
  | `neojac build api` (25-line app, clean `.jac/`) | 0-1 | 500 MB | ~2.2 GB | 3306 MB | killed by watchdog |
  | `neojac test manager.jac` (700 lines + 21 tests) | 0-3 | 500 MB | ~2.1 GB | 3279 MB | killed by watchdog |
  | `neojac test manager.jac` | 0 | 250 MB | ~2.0 GB | 3072 / 2656 / 2638 / 2728 / 2321 MB (5 runs, cache warming) | passed |
  | `neojac test auth.jac` (plugin, pulls `stdjac.server`) | 0 | 250 MB | ~2.0 GB | 3221 MB | passed |
  | `neojac check <app>` / `neojac test util.jac` | — | — | — | 745 MB / 679 MB single-process RSS | passed |
  | `neojac run` of 3-line program importing `cloakbrowser` | — | — | — | 910 MB single-process RSS | passed |
  | original Python: 240 pytest tests | — | — | — | 80 MB | passed |

- Documented controls: none. `neojac help build` has no jobs/memory option; `neojac docs search "parallel"` / `"memory"` find
  nothing about build parallelism or build memory. **(guess)** it fans out to all 16 online CPUs; the only thing that worked
  here was pinning with `taskset` plus a lower floor.
- **Update after the user closed VS Code (baseline 0.77 GB used instead of ~2.2 GB):** the full app (`neojac build manager`, native
  server + vite bundle of the site) built pinned to one CPU with the watchdog at 300 MB and a **system peak of 2.2 GB** (1.2 GB when the
  cache was warm) — `notes/build-final.log`; `neojac browse` (headless Chrome) added ~0.2 GB. So the toolchain *does* fit in 4 GB, but
  not next to a ~2 GB IDE server; on this VM the build is only usable with the IDE closed. The crashes above were VS Code + build.

---

## F. Port-specific findings recorded while building the app (appended as hit)

### L-019 Under the default lint, `neojac check` rejects ordinary code and `fmt --fix` rewrites/deletes it
- New project with no `[check.lint]`: a one-method class fails `check` with W3055 (body "belongs in an impl") — every
  W-code is an error. `neojac fmt --fix` removes docstrings and comments by design. This project sets
  `[check.lint] select = ["style"]` to keep docs; `fmt --fix` then still rewrote ~190 lines (combine `glob`s etc.).
  Intentional per the docs (`starting-a-project`), but it is the first wall every port hits.

### L-020 Diagnostics print paths inside the installed runtime
- `E0109` for `@restspec` printed `/home/ravimal/.neojac/0.3.3/rt/stdjac/server.jac:346:5 ... comptime assert len(params(f))`.
  Harmless, but it points a user at compiler-runtime source the rules forbid reading; a user diagnostic could name the
  decorator's own line instead.

### L-021 Test blocks share one graph (minor, expected)
- `root` persists across `test` blocks of a module run, so a test that counts profiles sees the previous test's nodes
  (5 of my first 21 tests failed for this reason). Isolation is manual (`fresh_data()` in `manager.test.jac` removes every node).

### L-022 Endpoints cannot read the request (headers, caller, client address) — *docs-only*
- Searched, no documented way found (`docs search "request header"`, `"whoami"`, `"current caller"`; read `apps/server`,
  `stdjac`, `stdjac.server`): an endpoint has no handle on the caller's headers or address; only `root` is the caller's.
  (`Request` with `headers` exists only as the `transport` plugin's type.)
  The original's `/api/auth/status` (`authenticated: bool`, computed from the request) therefore returns only `auth_required`;
  a page learns whether it is signed in from `GET /__jac/auth/me` / `signed_in()`.
- The session token is kept in the browser's `localStorage` (`jac_token`) per `neojac docs apps/pages`, not in the original's
  `HttpOnly; SameSite=Strict` cookie, which the server cannot set (no response headers, L-009). A custom `Auth` plugin
  can *read* an `auth_token` cookie (`token_auth` does, unit-tested) but nothing can *set* it.

### L-023 `Auth` plugin: worked as documented (positive) — with one undocumented-in-skill cost
- `token_auth` (custom `auth` plugin, ~60 lines) reproduces `AUTH_TOKEN` (Bearer + cookie, constant-time compare, open mode
  when unset) and passes 3 unit tests. Cost: its package is its own project root, so the default lint applied and
  `fmt --fix` deleted its module docstring and moved all bodies into `impl/` (L-019), and the `writing-a-plugin` skill
  points at a worked example only inside neojac's repository (`tests/plugins/ticket_auth`), which the rules forbid reading,
  so the plugin was written from `neojac docs stdjac.server` tables alone (it type-checked first time).

### L-024 Pydantic-style data models have no port mapping and no decoder equivalent
- Pydantic models (`class X(BaseModel)` with annotated fields and validators, 160 of the refusals) have no mapping at all;
  the Jac replacement (`obj` + manual `validate_fields`) had to be designed by hand, and `extra="forbid"`, `Literal[...]`,
  `field_validator`, `model_dump(exclude_unset=True)` have no counterpart in neojac's decoder (L-011/L-012/L-013).

## What of the original is NOT ported (and why)

| Original feature | Status | Reason |
|---|---|---|
| Profile CRUD, reorder, reset, duplicate (+browser state), tags | **ported**, 21 Jac tests + 16 original-behaviour tests | |
| Settings (masked key, channel), status, health, runtime config | **ported** | |
| Files / artifacts (upload, list, download, delete, quotas, safe filenames) | **ported**, ≤ ~8 MiB per file | L-014 |
| Optional `AUTH_TOKEN` auth | **ported** as a custom `auth` plugin | token in `localStorage`, not cookie (L-022) |
| Launch / stop / status | **simulated** (state only, no browser) | no KasmVNC/Xvnc and 3.7 GB RAM here; real launch would need `cloakbrowser` + a VNC server; `cloakbrowser` itself imports from Jac (L-017) |
| VNC WebSocket, CDP WebSocket and `/cdp/json/*` reverse proxy, clipboard relay, screenshot | **not ported** | L-015 |
| `test-proxy`, update-check, open-external, shutdown | **not ported** | need outbound HTTP + request origin (L-022); low value |
| Browser-download capture (`downloads.py`), file-chooser bookmarks (`artifacts.sync_picker_view`) | **not ported** | belong to the live browser container |
| React UI (15 components, drag-and-drop, noVNC viewer) | **partial**: login gate, profile list, create/edit form, settings, files list/delete, launch/stop in Jac JSX; *type-checked, never rendered*; no drag-reorder, no file upload/download UI, no noVNC | L-003, memory (L-018) |

### L-026 BUG (major): a `str | None` field cannot hold `None` — not in a result a page decodes, and not in the graph store
- Same defect as L-011, found twice more once the app was built and run:
  1. **Store.** A `node` with `has opt_str: str | None = None;` is written fine; after the server restarts every read fails:
     `DataError: .../graph.db holds a svc.Item node, ..., which no longer fits its type (.opt_str: expected a str, got None)` and the
     endpoint answers 500. An `int | None = None` field on the same node loads fine. Minimal repro: `repros/r09-store-optional/`
     (`result.txt`, saved server log). This one is data-destroying in effect: a profile with no proxy makes the whole app unreadable
     after the first restart (seen in the real app, `notes/smoke2.txt`, before the workaround).
  2. **Client decode.** A page awaiting a function whose result has `timezone: str | None = None` (value `None`) raises
     `.profiles[0].timezone: expected a str, got None` in the browser console (`notes/browse-signin.txt`); the server had encoded `null` happily.
- **Workaround used:** every optional string is a plain `str` where `""` means "none" (graph fields, reply objects). The Jac API
  therefore returns `""` where the original returned `null` (`proxy`, `timezone`, `locale`, `color_scheme`, `notes`, `cdp_url`,
  tag `color`, artifact `content_type`, `license_key_masked`), a visible contract difference (an empty `proxy` string cannot be told from none).
- Docs say `null` is `None` for a parameter "whose type admits None"; nothing documents that `str | None` is the exception.
  **(guess)** the decoder tries the `str` branch of the union before the `None` branch for strings only.

### L-027 BUG (major): `import json` in a browser-space module passes `neojac check --space site` but fails the bundle
- `neojac check --space site`: clean. `neojac build manager`: `[vite]: Rollup failed to resolve import "@jac/runtime/lib/json" from
  ".../eco/web/.jac/build/manager/site/src/ui/profile_form.jsx"` (`repros/r08-json-browser/build-output.txt`). The docs say a *node* space
  refuses these modules with E1540 (`apps/hosts`); a *browser* space gets no such diagnostic and no doc says which native modules it has.
- Workaround: a hand-written JSON string builder in the form (escapes `\`, `"`, newline, CR, tab); verified in the browser with a name
  containing quotes and a backslash (`notes/browse-create.txt`).
- The build prints a ~30-line Node stack trace for this; the useful line is the first.

### L-028 `neojac browse` accepts CSS selectors and `@eN` refs only (minor, docs)
- `neojac browse click 'text=Launch'` → `SyntaxError: ... 'text=Launch' is not a valid selector` (Playwright-style selectors are a
  common guess; `neojac docs browse` lists the supported forms). Noted only because the skill suggests "a CSS selector".
