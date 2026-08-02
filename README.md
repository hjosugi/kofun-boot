# kofun-boot

Batteries-included application framework for the
[Kofun](https://github.com/hjosugi/kofun) language.

The ambition is Spring Boot's: the de-facto way to build a production
application. The discipline is Kofun's: every claim is backed by a gate, every
dependency is a capability handed in by the caller, and a feature that cannot
be exercised deterministically does not ship.

## The one-sentence design

**An application is a pure function from its capabilities to its behaviour;
kofun-boot is the shell that wires, serves, replays, and measures it.**

Everything below follows from that sentence.

## Try it

```sh
git clone --recurse-submodules https://github.com/hjosugi/kofun-boot
cd kofun-boot
sh scripts/dev.sh          # 22 unit tests, a build, and a golden check — about a second
```

| command | what |
|---|---|
| `sh scripts/dev.sh` | the inner loop: unit suite, build, golden check |
| `sh scripts/dev.sh --test` | the unit suite alone, the fastest useful loop |
| `sh scripts/dev.sh --watch` | re-run on every save |
| `sh scripts/dev.sh --serve` | a real server on a real socket |
| `sh scripts/dev.sh --openapi` | the document the route table projects |
| `sh scripts/dev.sh --research` | deterministic framework-research ZIP + SHA-256 |
| `sh scripts/dev.sh --check` | exactly what CI runs, in CI's order |

The last row is the point: a green terminal and a green pipeline are the same
commands, so they cannot come to mean different things.

## What exists today, honestly

Kofun's Stage 2 core is deliberately small. kofun-boot follows the pattern the
language repository uses everywhere: a **canonical contract** ahead of the
compiler and pinned by a gate, beside a **bounded executable seed** that proves
the decisions on both backends, byte-for-byte.

### The router — contract-first dispatch

`seed/router/` compiles a route table at build time and dispatches with a
comparison count independent of the request, so the same input can never take
two paths. Failures are a closed sum that carries what was observed:

```
GET  /hello   → Matched(handler 1)
GET  /sum     → MethodNotAllowed(allowed = POST)     ← names what would have worked
GET  /nope    → NotFound(path)
… body 4097   → PayloadTooLarge(limit = 4096)        ← names the limit
```

The dispatch order is the contract and the gate reads it: **size before route,
route before method**, so an oversized request cannot probe the route space by
watching the refusal change.

### The mock resource — json-server's five minutes, replayable

`seed/mock/` gives a full REST resource from a seed: list, show, create,
update, delete. It edits nothing. `apply : Store -> Operation -> StoreStep`
returns the resource *and* what happened, and there is no other way to obtain
the next store, so a session is a fold.

Three properties follow that a file-mutating mock cannot offer: the same seed
and the same requests **replay byte-identically**; a test can assert the
resource *between* two requests; and `POST` allocates from a counter carried
in the value, so ids are deterministic with **no clock and no entropy**.

### The projections — one declaration, many artifacts

`scripts/openapi.sh` generates the OpenAPI document from **the twelve lines the
router itself printed**, which the gate pins as the compiled table. A document
made from those bytes cannot describe a route the dispatcher does not serve.
Editing it by hand fails; a projection that silently drops a route fails on the
count.

## Testing, which is most of the reason to pick a framework

**Unit tests need no server.** kotest pairs `core_test.kofun` with its
companion `core.kofun`, so tests call the core directly. Twenty-two of them run
in about a second. Assertions accumulate rather than abort, so a broken change
reports everything that is wrong at once instead of the first thing.

```
Tests  22 passed (22 total, 2 suites)
```

**Integration tests use a real socket.** `tests/integration/serve.sh` builds the
example server from the pinned checkout, waits for `READY <port>` rather than
sleeping, and asserts path capture, JSON decode, 404, 400-not-a-crash,
keep-alive across two requests, and SIGTERM drain — killing the process on
every exit path. Port 0 means parallel runs cannot collide.

**Every gate is verified in both directions.** A gate is added together with
the demonstration that it fails: making the body limit exclusive fails exactly
one named test; a handler that constructs its own clock fails with its line
number quoted; hand-editing the OpenAPI document fails with the diff.

## Pillars, each with a bar it must clear

| pillar | inherited from | the measurable bar |
|---|---|---|
| Contract-first APIs | servant, FastAPI, Elysia | routes, validation, OpenAPI, and the typed client derive from **one** declaration; drift is a build failure — **holds for the document today** |
| Capabilities, not containers | Spring DI, inverted | no container and no reflection; the core **may not construct** a capability, enforced by a gate that prints the offending line |
| Functional core, imperative shell | FCIS, functional DDD | enforced by construction — **holds today** |
| Deterministic replay | Kofun's gate culture | identical bytes on both backends, twice, under a hostile `TZ`, locale, and `env -i` — **holds today** |
| Speed | Elysia, Gin, Hono | requests/sec published with its method — *unmeasured; no number appears here before the gate that measured it* |
| Structured concurrency | Go's ergonomics, without the leaks | scoped spawn/join, deterministic schedules — blocked on the language RFC, and says so |
| Desktop lighter than Tauri | Tauri, inverted | binary size and cold start as gated numbers — *unmeasured* |
| A CLI worth living in | Rails, Spring Initializr | `boot new / dev / test / bench / openapi / gen` |

## Repository layout

| path | what |
|---|---|
| `contracts/` | canonical surfaces ahead of the compiler, pinned by gates; the generated OpenAPI document |
| `seed/router/` | the dispatcher: core, shell, unit suite, golden |
| `seed/mock/` | the REST resource: core, unit suite |
| `scripts/` | `dev.sh`, `build-seed.sh`, `openapi.sh` |
| `tests/boot/check.sh` | the gate: boundary, contract, dispatch decisions, projection, determinism |
| `tests/integration/serve.sh` | a real server on a real socket |
| `docs/adr/` | the numbered decision log — why, and what it cost |
| `docs/DESIGN.md`, `docs/ROADMAP.md` | the architecture; the lanes and what each is blocked on |
| `docs/BACKLOG.md` | the epic decomposition, issue shape, and labels |
| `docs/research/` | the source-linked, dated surveys behind the decisions |
| `docs/architecture/` | the resulting effect, update-loop, and domain-model decisions |
| `vendor/kofun` | the pinned language checkout |

## The three decisions worth arguing with

The research dossiers in [`docs/research/`](docs/research/) produced three
positions that shape everything else. Each links to the evidence.

**Effects are inert data, not a monad.**
[`docs/architecture/EFFECTS.md`](docs/architecture/EFFECTS.md) — the core
returns a `Cmd` describing what should happen; the shell interprets it holding
the capabilities. This needs a closed sum and a function, which is all Kofun
has today, and it is *why Elm is understandable* — the monad was never the
clear part. A recorded run then **is** the `Cmd`/`Msg` sequence, so replay
needs no instrumentation.

**One update loop, three shells.**
[`docs/architecture/TEA.md`](docs/architecture/TEA.md) — `init`, `update`,
`view`, `subscriptions`, all pure, interpreted by a server shell, a desktop
shell, or a server-driven shell. That the same core runs under all of them is
a gate, not a slogan.

**The view is an ADT, which is the only reason "replace the webview" is
schedulable.**
[`docs/research/RENDER_BACKENDS.md`](docs/research/RENDER_BACKENDS.md) — Tauri
cannot swap its renderer cheaply because its contract *is* the DOM, so a
replacement must reimplement the web platform; that is why the leading attempt
is still pre-alpha. If the view is a vocabulary we chose, a renderer is an
interpreter, and native becomes a second backend rather than a rewrite. The
same dossier records the finding that governs the desktop lane: **IME and
accessibility are gates, not features**. No performance number is recorded
until both pass under a gate.

## What we refuse

- **No reflection, ever.** Everything derived is derived at build time.
- **No middleware onion.** Cross-cutting behaviour is a function composed in
  the shell, visible in one place.
- **No unstated defaults.** Defaults exist, are few, and are printed.
- **No number without the gate that measured it.**
- **No feature without a gate**, and no gate merged without the demonstration
  that it fails.

## License

Apache-2.0 OR MIT, matching the language.
