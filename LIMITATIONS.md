# neojac limitations found while porting CloakBrowser-Manager to Jac

Compiler under test: **neojac 0.3.3 (linux-x86_64, 98a4abf03de2)**, installed with the
official `install.sh` on 2026-11-21. Source of truth for everything below: neojac's own
docs/skills/`help`/diagnostics, plus the observed behaviour of the compiler. No compiler
source was read; any cause is explicitly marked **(guess)**.

Port target: `../CloakBrowser-Manager` (FastAPI backend ~5k lines + React/Vite frontend ~4.5k lines).

Severity: **blocker** (cannot do what the app needs) / **major** (needs a large workaround) /
**minor** (annoyance, wrong/missing docs, cosmetic).

Entries are appended the moment they are hit, in order.

---

## L-001 `neojac port` refuses every file of the backend, whole (blocker for "port first")

- **Symptom:** `neojac port --check ../CloakBrowser-Manager/backend` → 14 of 14 sources "refused,
  nothing written". A file ports whole or not at all, so one unsupported construct anywhere in a
  file (e.g. a single `try`) discards the whole file. Zero lines of the backend were produced by `port`.
- **Repro:** `neojac port --check ../CloakBrowser-Manager/backend/*.py`
- **Refusal tally (E4001/E4005) across the backend**, by construct:

  | count | construct refused |
  |---|---|
  | 160 | class-level annotated attribute (`name: str = ...` inside a class — i.e. every Pydantic model / dataclass field) |
  | 50  | `async def` |
  | 42  | module-level name bound by code, used by functions (`logger = ...`, `X = os.environ.get(..)`, `re.compile(..)`, `frozenset(...)`) — E4005 |
  | 31  | `try` / `except` / `finally` |
  | 21  | `async def` method in a class |
  | 17  | relative import (`from . import x`, `from .m import y`) |
  | 16  | `with` |
  | 8   | bytes literal |
  | 7   | `*args` / `**kwargs` / keyword-only (`*,`) parameters |
  | 6   | import inside a function |
  | 6   | function defined inside a function |
  | 6   | `*` unpack item in a literal |
  | 5+3 | decorators / class decorators (`@app.get`, `@dataclass`, `@contextmanager`, `@field_validator`) |
  | 4+2 | `**` argument / `**` item of dict |
  | 2   | `lambda` |
  | 2   | method whose first parameter is not `self` (`@classmethod`) |
  | 3   | `global x` |
  | 1   | non-constant default (`def f(path: Path = _ENV_PATH)`) — E4005 |
  | 1   | assignment to several targets (`a = b = 0`) |

- **Consequence:** the whole backend had to be hand-written in idiomatic Jac; `port` contributed
  nothing mechanically. Note even tiny files (`env_file.py`, 39 lines; `settings_store.py`, 48 lines;
  `runtime.py`, 117 lines) are refused.
- **Docs:** `neojac docs toolchain/port` says "This first version translates a core of each language";
  honest, but it is not discoverable up front that `try`, `with`, `async def`, classes with annotated
  fields and module-level `X = call()` are all outside that core — i.e. almost all real Python.
- **Sub-finding:** E4005 on `X = os.environ.get(...)` at module level is the most common refusal after
  classes; the suggested fix ("Bind to a literal above the module's code, or pass it to the functions")
  has no direct Jac form either — see L-0xx (module-level initialisation) below once hit.

## L-002 `neojac port` of the TypeScript frontend: spurious tsc errors, project config ignored

- **Symptom:** `neojac port --check ../CloakBrowser-Manager/frontend/src` →
  `error[tsc TS2304]: Cannot find name 'fetch'` / `'File'` (browser globals), `TS2307: Cannot find
  module 'vitest'` (no node_modules), `TS2835: Relative import paths need explicit file extensions
  ... moduleResolution node16/nodenext` (the project's own `tsconfig.json` uses bundler resolution),
  and many `TS7006 implicit any`.
- **Meaning:** port type-checks with its own settings (lib without DOM, nodenext resolution),
  not the project's `tsconfig.json`, so ordinary browser TS/React code is "refused" before any
  translation question arises. **(guess)** it runs `tsc` with a fixed config.
- **Also:** JSX/TSX files (`.tsx`) are not in the supported-extension list in `neojac docs toolchain/port`
  (`.js .mjs .cjs .ts` only) — the whole React UI (all `.tsx`) is out of scope for `port`.

## L-003 docs/skills contradict each other about `class`

- `neojac skills writing-jac` rule 5: "`class` is not built yet: write `obj`."
- `neojac skills porting-from-python` step 2: "`class` to `class` with `has` fields (or `obj` for a dataclass)"
  and the mistakes table: "`class P { ... }`, or `obj P { ... }` for a dataclass".
- (verification result appended below once tested)

## L-004 `install.sh` re-downloads the full release even when the same version is installed

- `neojac --version` already printed 0.3.3 and the installer fetched "the latest version"
  (0.3.3), then downloaded the whole ~370 MB tarball again (took >7 minutes on this link) before
  reporting "neojac 0.3.3 installed". **(guess)** no installed-vs-latest comparison before download.
  Minor; but strict rule #1 ("install the latest release first") makes every dogfooder pay it.

## L-005 `@restspec` cannot express the original REST contract (major)

- Per `neojac docs apps/server`: `@restspec(method, path, ...)` supports only `GET` and `POST`, the
  function **takes no parameters**, so there are no path parameters (`/api/profiles/{id}`), no
  `PUT`/`DELETE`, no query string, no request headers/cookies, no custom status codes (always the
  `{"ok": ..., "data": ...}` envelope or a bare `str`), no non-JSON bodies.
- Every original endpoint therefore moves to `POST /__jac/call/<space>/<module>/<name>` with
  `{"args": {...}}`; the original HTTP API (`GET /api/profiles`, `PUT /api/profiles/{id}`,
  `DELETE ...`, `201`/`404`/`409` statuses, `Set-Cookie` on login, `Content-Disposition` downloads)
  cannot be reproduced byte-for-byte. The Jac app has a *different* HTTP contract; parity is proven
  at the behaviour level (see `parity/`).

## L-006 `neojac absorb` only moves package.json; the rest of the JS project stays behind

- `neojac absorb absorb-input --tree web` succeeded (exit 0): `package.json` → `[npm.web]` in
  `jac.toml`, lock → `jac.lock`, and (per `help absorb`) files moved to `eco/web`.
- It carries the **scripts** (`dev = "vite"`, `build = "tsc -b && vite build"`, `test = "vitest run"`)
  and dev dependencies for TypeScript/Vitest/Tailwind verbatim. Nothing tells the user those
  scripts/dev-deps do not apply to a Jac browser space (neojac's own `@jac/vite` plugin owns the build).
  It also does not bring `vite.config.ts`, `tailwind.config.ts`, `postcss.config.js`, `index.html`,
  `tsconfig.json` — those must be re-created by hand under `eco/web/` (docs: `neojac docs apps/index`).
- It does not add `react-router-dom`, which the docs' "smallest project" lists as required for a pages app.
