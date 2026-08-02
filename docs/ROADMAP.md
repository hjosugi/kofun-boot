# Roadmap: lanes → epics → bounded children

The unit of work is a bounded child: one reviewable change, one gate, one
honest boundary statement — the granularity the Kofun repository runs at.
Lanes decompose into epics, epics into children; at production scale this
tracker is expected to pass four digits of issues, and the structure below is
what keeps that navigable rather than aspirational.

Every lane names what it is blocked on. A lane blocked on a language
capability tracks the Kofun issue and does not ship a workaround we would
have to break.

| # | lane | first epics | blocked on |
|---|---|---|---|
| [L0 #10](https://github.com/hjosugi/kofun-boot/issues/10) | governance & evidence | issue metadata discipline; release claims + evidence pack (kofun's `release/claims.json` pattern); benchmark result provenance | — |
| [L1 #1](https://github.com/hjosugi/kofun-boot/issues/1) | contract | route/table ADTs; validation sums; OpenAPI projection; **multi-language client generation (swagger-codegen's reach)**; drift gates between all four | — |
| [L2 #2](https://github.com/hjosugi/kofun-boot/issues/2) | serve | dispatch-table → `framework/http` registry; config surface (bind, limits, drain) as one printed record; TLS via capability | callback C ABI (kofun #574 lane) for arbitrary handlers |
| [L3 #3](https://github.com/hjosugi/kofun-boot/issues/3) | capabilities | clock/net/bytes/db wiring records; FCIS gate (code-only grep) over `core/`; fake-capability kit re-exported for app tests | — |
| [L4 #4](https://github.com/hjosugi/kofun-boot/issues/4) | replay | trace format v1 (versioned, digest-pinned like tzdb fixtures); record mode; replay mode; hostile-environment gate | — |
| [L5 #5](https://github.com/hjosugi/kofun-boot/issues/5) | speed | benchmark gate on `benchmarks/http` harness; recorded baselines; regression = failure; published same-box comparisons vs Elysia/Gin/Hono | — |
| [L6 #6](https://github.com/hjosugi/kofun-boot/issues/6) | concurrency | scoped spawn/join surface; cancellation as typed result; deterministic schedule replay | kofun #898 RFC, #736 |
| [L7 #7](https://github.com/hjosugi/kofun-boot/issues/7) | data | schema-as-contract (drizzle direction); **API derived from schema (Hasura's move)**; typed queries; migrations as replayable traces; PostgREST interop | List/Text lowering maturity (kofun #919 lane) |
| [L8 #8](https://github.com/hjosugi/kofun-boot/issues/8) | cli & dx | `boot new/dev/test/bench/openapi/gen`; **`boot mock` — json-server's convenience, replayable**; scaffolds that compile with the core/shell split; watch-reload | — |
| [L9 #9](https://github.com/hjosugi/kofun-boot/issues/9) | desktop | webview shell (KB-scale, gated size); wasm32 guest via host ABI v1; typed IPC = the router contract; **UI quality as a discipline, not a default (taste-skill)** | kofun #906 activation lanes |
| [L10 #11](https://github.com/hjosugi/kofun-boot/issues/11) | site & docs | tutorial that never lies (every snippet is a gated fixture); comparison pages that show their measurement | — |

## Sequencing

```
now ──► L1 contract + L3 capabilities + L4 replay      (pure, unblocked, the identity of the framework)
     ──► L2 serve v1 + L5 first baselines               (framework/http exists; numbers start accruing)
     ──► L8 cli                                          (once `boot new` output compiles under the gate)
later ─► L6, L7, L9 as their language capabilities land
```

## The bars, restated as numbers to be filled in

| bar | measured by | current value |
|---|---|---|
| dispatch overhead vs hand-written matcher | L5 gate | *(unmeasured — no number may appear here before the gate exists)* |
| req/s vs Elysia, same box, same handler | L5 published run | *(unmeasured)* |
| desktop binary size vs Tauri hello | L9 gate | *(unmeasured; kofun native ELF fixtures are KB-scale, which is the reason to believe the bar is reachable)* |
| replay determinism | L4 gate | seed already holds it: two runs, both backends, `env -i` — byte-identical |

## Filed and ready now

- [#12](https://github.com/hjosugi/kofun-boot/issues/12) serve: build and smoke the vendored `framework/http` server on CI
- [#13](https://github.com/hjosugi/kofun-boot/issues/13) contract: path captures in the seed, read by the gate
- [#14](https://github.com/hjosugi/kofun-boot/issues/14) capabilities: the FCIS gate — core modules cannot name a capability

## What we are learning from, and exactly what we take

Reading a reference implementation is only useful if the reading is specific.
Each row says what we take and — where it matters more — what we deliberately
do not.

| source | taken | left |
|---|---|---|
| [json-server](https://github.com/typicode/json-server) | zero-config REST from a seed; the whole developer feeling | in-place file mutation. Ours returns a new store, so a session is a fold and replays ([ADR 3](adr/0003-mutations-return-a-new-state.md)) |
| [modular-monolith-with-ddd](https://github.com/kgrzybek/modular-monolith-with-ddd) | the numbered ADR log; module = its own Application/Domain/Infrastructure/Tests; business rules as values; arch rules enforced mechanically | one test method per rule. Its own `LayersTests.cs` names Infrastructure and asserts Application, so Domain→Infrastructure was never checked — [ADR 2](adr/0002-enforce-boundaries-by-gate-not-by-named-test.md) explains why we print the offending line instead |
| [servant](https://github.com/haskell-servant/servant) / [FastAPI](https://github.com/fastapi/fastapi) / [Elysia](https://elysiajs.com/) | one declaration → routes, validation, docs, typed client; dispatch compiled rather than interpreted | type-level gymnastics for their own sake; ours stays monomorphic until measurement argues otherwise |
| [swagger-codegen](https://github.com/swagger-api/swagger-codegen) | generating clients for languages we do not own | generation as a separate tool with its own model. Ours is a projection of the same table the dispatcher runs, so drift is a build failure |
| [Hasura](https://github.com/hasura/graphql-engine) | the API derived from the schema rather than hand-written beside it | a running engine that owns your database. Ours generates, it does not sit in the path |
| [Spring Boot](https://github.com/spring-projects/spring-boot) | the ambition: the default way to build an application | the IoC container — a language without ambient authority does not have the problem it solves |
| [tonatona](https://github.com/tonatona-project/tonatona) | plugins as an environment record | the type-class machinery; plain records, plain arguments |
| [axum](https://github.com/tokio-rs/axum) / [Gin](https://github.com/gin-gonic/gin) / [Hono](https://github.com/honojs/hono) | composition over middleware onions; small fast cores | implicit extractor magic; every capability is visible in the signature |
| [Tauri](https://github.com/tauri-apps/tauri) | the system webview is already installed | the multi-megabyte binary; ours is a gated KB number |
| [taste-skill](https://github.com/Leonxlnx/taste-skill) | UI quality as an explicit discipline for generated interfaces | — |
| [Rails](https://github.com/rails/rails) | generators, conventions, the first-hour experience | convention that cannot be checked; every scaffold we emit is a tested fixture |
