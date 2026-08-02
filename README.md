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

## Pillars, each with a bar it must clear

| pillar | inherited from | the measurable bar |
|---|---|---|
| Contract-first APIs | servant, FastAPI, Elysia Eden | routes, validation, OpenAPI, and the typed client all derive from **one** declaration; drift between them is a build failure, not a review comment |
| Capabilities, not containers | Spring DI, tonatona — inverted | no IoC container and no reflection: a dependency is a value passed to a function, and an application that names an ambient authority **does not compile** |
| Functional core, imperative shell | FCIS, functional DDD | enforced by construction, not convention: domain modules cannot name a capability, and a gate greps the code (comments stripped) to prove it |
| Deterministic replay | Kofun's own gate culture | every integration test is a byte-replayable trace: fake clock, injected bytes, scripted network — identical output under a hostile `TZ`, locale, and `env -i` |
| Speed | Elysia, Gin, Hono | static route dispatch decided at build time — zero reflection, zero runtime route parsing; a benchmark gate records requests/sec and fails on regression |
| Structured concurrency | Go's ergonomics, without `go func` leaks | scoped spawn/join where a child cannot outlive its scope, and test schedules replay deterministically |
| Desktop lighter than Tauri | Tauri, inverted | a hello-world desktop app measured in **kilobytes of our binary** riding the system webview; cold start and binary size are gated numbers |
| A CLI worth living in | Rails, Spring Initializr | `boot new / dev / test / bench / openapi / gen` — scaffolds, watch-reload, and generated clients from the same contract |

The bars are commitments, not claims. Where a bar is not yet met, the roadmap
issue for it says so; nothing in this repository asserts a number it has not
measured.

## What is executable today, honestly

Kofun's Stage 2 core is deliberately small. kofun-boot follows the pattern the
Kofun repository itself uses everywhere: a **canonical contract** that is ahead
of the compiler and pinned by a gate, beside a **bounded executable seed** that
proves the decisions on both the reference executor and the C11 backend,
byte-for-byte.

- `contracts/boot.kofun` — the canonical application surface: typed routes,
  capability wiring, closed error sums. Ahead of the compiler **on purpose**;
  the gate requires it to keep failing at the documented boundary.
- `seed/router/` — the executable seed: a static-dispatch router in the Stage 2
  slice. Typed request → closed `RouteResult`, dispatch by a fixed comparison
  rank (the same input can never take two paths), handlers as pure functions,
  every failure a constructor that names what was observed. Runs identically on
  the reference executor and the C11 backend, twice, under `env -i`.
- `vendor/kofun` — the language, pinned as a submodule. The seed is checked and
  executed by the pinned toolchain, so "it works" always means "at this
  revision".

The serving story does not start from zero: Kofun ships a first-party epoll
HTTP/1.1 runtime (`framework/http`) with an integration-tested event loop and a
benchmark harness. kofun-boot's serve lane builds on it rather than beside it.

## Repository layout

| path | what |
|---|---|
| `contracts/` | canonical surfaces, ahead of the compiler, pinned by gates |
| `seed/` | bounded executable producers proving contract decisions today |
| `tests/boot/check.sh` | the gate: contract stops at its boundary, seed agrees on both backends, bytes do not move under a hostile environment |
| `docs/DESIGN.md` | the architecture and every decision's reason |
| `docs/ROADMAP.md` | lanes → epics → issues; how this grows to production |
| `docs/BACKLOG.md` | the epic decomposition, the issue shape, and the labels |
| `docs/research/` | the surveys the decisions came out of, each source-linked and stamped |
| `docs/architecture/` | the decisions themselves: effects, the update loop, domain modelling |
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
accessibility are gates, not features** — a 2025 survey found 94.4% of Rust
GUI libraries not production-ready, with text input the most common failure.

## Building

```sh
git submodule update --init vendor/kofun
sh tests/boot/check.sh
```

## License

Apache-2.0 OR MIT, matching the language.
