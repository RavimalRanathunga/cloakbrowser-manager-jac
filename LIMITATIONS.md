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
- `neojac port --check ../CloakBrowser-Manager/backend` → every one of the 13 non-empty modules refused,
  *nothing written*. A file ports whole or not at all, so one `try` discards 1900 lines. Even 39–117 line files
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
  Repro: `repros/` n/a (command above; output summarised in this table).

### L-002 `port` does succeed on a slimmed pure subset — but its output is not clean under the project's default lint
- `ported/src/pure.py` (4 pure helpers lifted from `main.py`, rewritten to port's core) → `neojac port` wrote
  `ported/pure.jac`; `neojac run` output is **byte-identical** to `python3` (`ported/result.txt`). Good.
- But: every parameter/return/local is `any`; and with the default lint (`"clean"`) `neojac check pure.jac`
  fails with W3051 (docstring) and 4× W3055 (inline bodies) — port's docs say it "is checked before it is written",
  yet its own output fails the project's default check. `neojac fmt --fix` makes it pass by **deleting the docstring
  and every comment** and moving bodies to `impl/pure.impl.jac` (`ported/pure.jac` before/after in git history).
  Comments/docstrings of the source are therefore lost irrecoverably by the recommended workflow.
- Minor: port emitted `parts.append(`int(part))` — a backtick-escaped `int` — for `int(part)`.

### L-003 `port` cannot read the React/TS frontend (blocker for "port the UI")
- `.tsx` is not a port source: `neojac port --check Hello.tsx` → `E4004 ... is no source port translates:
  one is known by its extension, one of .c .cc .cjs .cpp .cxx .h .hpp .js .mjs .py .rs .ts` (`repros/r02-tsx/result.txt`).
  All 15 components of the app are `.tsx`.
- Plain `.ts` of the app (`lib/api.ts`, `hooks/useProfiles.ts`): `neojac port --check frontend/src` reports
  `tsc TS2304 Cannot find name 'fetch'/'File'`, `TS2835 relative import needs explicit file extension
  (moduleResolution node16/nodenext)`, `TS7006 implicit any`, `TS2307 cannot find 'vitest'`: port type-checks
  with its own tsc settings (no DOM lib, nodenext), not the project's `tsconfig.json`. **(guess)** a fixed config.

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

### L-011 BUG: `str | None` parameter rejects JSON `null`; `int | None` accepts it (major)
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

### L-015 No WebSocket server, no raw sockets in a served space (blocker for VNC/CDP proxying) — *docs-only*
- `neojac docs search websocket` → only a `WebSocket` *client* global in `hermes`. The original's `/vnc` and `/cdp`
  WebSockets (and `/cdp/json/*` rewriting reverse proxy, clipboard relay) cannot be served; a custom `transport` plugin
  would mean writing an HTTP/WebSocket server by hand. Not attempted.

### L-016 Auth model: single shared token vs `accounts` plugin
- The original's optional single `AUTH_TOKEN` (Bearer header or `auth_token` cookie, `hmac.compare_digest`) has no
  counterpart in the standard `accounts` plugin (username/password + per-caller roots). `Auth.caller(headers)` in a custom
  plugin could implement it (`neojac docs stdjac.server`). Status: see section F once attempted.

---

## D. Python interop (the app's core is `cloakbrowser`, a PyPI package)

### L-017 BUG: `neojac install --pypi "cloakbrowser[geoip]"` writes an invalid requirement (minor)
- `repros/r06-cloakbrowser/jac.toml` ends with `cloakbrowser = "[geoip]"` — package name and version dropped into the
  extras string (the installed venv does contain `geoip2`, so the extra was honoured once). A later `neojac install`
  would read `"[geoip]"` as a version spec. **(guess)** the extras bracket is parsed as the version.
- Positive: `import cloakbrowser; print(cloakbrowser.__version__)` works from Jac → `0.7.3` (`import.txt`).

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

### L-018 `neojac build <app>` of a trivial app needs ~1.6 GB in one process; the full app's build killed the VM (major on small machines)
- Building the real app (`manager.jac` ~700 lines) **crashed the WSL VM three times** (the VM restarted: `uptime` 0 min,
  /tmp wiped) — twice plain, once with a memory watchdog that polls every 0.5 s. A second attempt pinned to 2 CPUs with a
  0.2 s watchdog was killed by the watchdog at `MemAvailable < 500 MB` (system peak 3306 MB, `notes/r05-build-2cpu.log`),
  even for the *trivial* 25-line app built from a clean `.jac/`. `taskset -c 0-1` did **not** keep the build under budget,
  so per-process peak (not CPU fan-out) dominates. **(guess)** whole-program link/CPython embedding, not module count.
- The equivalent Python backend and its test-suite run in 80 MB. The Rust/C++ toolchain neojac ships (Clang + LLD +
  runtime) is the cost; there is no documented option to reduce build memory (`neojac help build` has none;
  `neojac docs search memory|parallel` finds nothing about build memory/jobs).
- Impact: iterate with `neojac check` / `neojac test` (<0.8 GB) and build only when nothing else is running.

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
