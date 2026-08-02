# Changelog

Every release records what changed and — required by
[`tests/release/check.sh`](tests/release/check.sh) — which pillar bars were
still unmeasured when it shipped. The unmeasured list must match
[`README.md`](README.md)'s pillar table exactly; the gate compares them and
fails on either kind of drift. See [`docs/RELEASING.md`](docs/RELEASING.md).

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), with
the `Unmeasured at this release` section added as a local requirement.

## [Unreleased]

Nothing yet.

## [0.2.0] - 2026-08-02

Bounded contexts now own their complete vertical. This is a breaking path
change below 1.0.0: code and tests formerly under `seed/` moved into modules,
and the router's canonical contract moved with its owner.

### Changed

- **Module ownership** — `router` and `mock` now each own `contract/`, `core/`,
  `shell/`, and `tests/` under `modules/<name>/`. The generic build and test
  adapters discover that layout instead of carrying a registry of module
  names.
- **Canonical contract location** — the router surface moved from
  `contracts/boot.kofun` to `modules/router/contract/router.kofun`.
  `contracts/` now contains projected/public artifacts rather than another
  module's source of truth.
- **Research pack** — the modular-monolith/DDD dossier now records the
  implemented evidence, ADR 5 and ADR 6 are included, and the deterministic
  archive digest is
  `bd489900e1e526a6193a2af39a6173a24547a5c070d6cb62692bd03762583e8e`.

### Added

- **Contract-only dependency gate** — a data-driven architecture gate requires
  every module to own its four layers and lets one module name only another's
  public contract. Canonical, dotted, and relative path spellings are checked.
- **Gate tested both ways** — the architecture fixture adds a third `orders`
  module without editing the existing two, then injects
  `../../router/core/router` and requires a diagnostic with the offending
  source, line, and allowed contract target.
- **Closed business outcome contract** — `modules/mock/contract/mock.kofun`
  models domain refusal as `MockOutcome`. The boot gate compares all seven
  constructors with the executable seed and requires every case to carry what
  was observed.
- **ADR 6** — records why a bounded context owns contract, core, shell, and
  tests, and why the assembly adapters are temporary compiler seams rather
  than a second ownership model.

### Gates

- 22/22 module-owned core tests pass through the filesystem-discovered test
  adapter.
- A third module passes without changes to existing modules; an internal
  cross-module reference fails with source, line, and allowed target.
- The boot gate pins the rich/executable outcome sum, all router projections,
  trace replay, and hostile-environment determinism.
- The deterministic research ZIP, real-socket integration suite, generated
  scaffold, and release coherence gate all pass.

### Unmeasured at this release

- Speed — L5; the benchmark harness exists and refuses to produce a number it
  does not trust, but no baseline has been recorded.
- Desktop lighter than Tauri — L9; blocked on the language's wasm32 activation
  lanes, and gated behind IME and accessibility conformance before any number
  is recorded ([#29](https://github.com/hjosugi/kofun-boot/issues/29)).

### Known boundaries

- The executable Kofun slice has no module imports yet. Build and test adapters
  concatenate module-owned files in a deterministic order; generated units do
  not enter the worktree.
- Contract-only imports are gated as source references today. The first native
  import implementation must retain the same break test.
- Outbox/Inbox, module-local database schemas, and event sourcing remain
  adopt/adapt/defer decisions, not claims of executable data-lane support.

## [0.1.0] - 2026-08-02

First tagged release. A working contract-first slice, a research corpus with
its sources pinned, and the gates that hold both.

### Added

- **Router** — a route table compiled at build time, dispatched with a
  comparison count independent of the request, so the same input can never
  take two paths. Failures are a closed sum carrying what was observed:
  `MethodNotAllowed` names the methods that would have worked,
  `PayloadTooLarge` names the limit. Dispatch order is size → route → method,
  so an oversized request cannot probe the route space by watching the
  refusal change.
- **Mock resource** — a full REST resource from a seed, mutating nothing.
  `apply : Store -> Operation -> StoreStep` returns the resource and what
  happened, and is the only way to obtain the next store, so a session is a
  fold. Ids come from a counter carried in the value: deterministic with no
  clock and no entropy.
- **Replay** — a recorded session replays step-for-step under `env -i`,
  refusing on the first divergence and naming the step. The trace needed no
  format design; it is the fold the core already performs
  ([ADR 5](docs/adr/0005-a-trace-is-the-fold-the-core-already-performs.md)).
- **Projections** — the OpenAPI document and the typed TypeScript client are
  both generated from the twelve lines the router itself printed, which the
  gate pins as the compiled table. An artifact cannot describe a route the
  dispatcher does not serve.
- **Scaffold** — `scripts/new.sh` emits a project that already has the
  core/shell boundary, and CI generates one, runs its gate, then breaks its
  core and requires that gate to refuse.
- **Research corpus** — source-linked, dated dossiers on web frameworks,
  desktop frameworks, render backends, effect systems, Spring Boot/FastAPI/Gin,
  and modular-monolith DDD, plus the architecture decisions they produced:
  inert `Cmd` effects, one update loop under three shells, and functional
  domain modelling.
- **Deterministic research pack** — a byte-reproducible ZIP with a SHA-256
  sidecar and an internal manifest, built twice including once under `env -i`
  with a hostile timezone and locale, and compared.
- **Release scaffolding** — `VERSION`, this file, `docs/RELEASING.md`, and
  `tests/release/check.sh`.

### Gates

- 22 unit tests across the router and mock cores, running in about a second
  with no server.
- The boot gate: boundary, canonical contract pinned at its compiler boundary,
  every dispatch decision read by name, projections, determinism on both
  backends under hostile `TZ`, locale, and `env -i`.
- A real server on a real socket: bind, path capture, JSON decode, 404,
  malformed input, keep-alive, SIGTERM drain.
- Every gate verified in both directions — added together with the
  demonstration that it fails.

### Unmeasured at this release

These bars carry no number, and this release makes no claim about them. Each
is blocked on the lane named beside it.

- Speed — L5; the benchmark harness exists and refuses to produce a number it
  does not trust, but no baseline has been recorded.
- Desktop lighter than Tauri — L9; blocked on the language's wasm32 activation
  lanes, and gated behind IME and accessibility conformance before any number
  is recorded ([#29](https://github.com/hjosugi/kofun-boot/issues/29)).

### Known boundaries

- Structured concurrency is blocked on the language RFC and ships nothing.
- The `Cmd`/`Sub` effect surface is a decision
  ([`docs/architecture/EFFECTS.md`](docs/architecture/EFFECTS.md)) and a filed
  contract ([#31](https://github.com/hjosugi/kofun-boot/issues/31)), not yet
  executable code.
- Whether the view is a shared ADT or platform-specific is an open decision
  ([#28](https://github.com/hjosugi/kofun-boot/issues/28)) and determines the
  shape of the desktop lane.
- `0.x` makes no API stability promise. Minors may break the contract surface;
  this file will say so when they do.

[Unreleased]: https://github.com/hjosugi/kofun-boot/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/hjosugi/kofun-boot/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/hjosugi/kofun-boot/releases/tag/v0.1.0
