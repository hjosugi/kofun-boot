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
| [L1 #1](https://github.com/hjosugi/kofun-boot/issues/1) | contract | route/table ADTs; validation sums; OpenAPI projection; typed client projection; drift gates between all four | — |
| [L2 #2](https://github.com/hjosugi/kofun-boot/issues/2) | serve | dispatch-table → `framework/http` registry; config surface (bind, limits, drain) as one printed record; TLS via capability | callback C ABI (kofun #574 lane) for arbitrary handlers |
| [L3 #3](https://github.com/hjosugi/kofun-boot/issues/3) | capabilities | clock/net/bytes/db wiring records; FCIS gate (code-only grep) over `core/`; fake-capability kit re-exported for app tests | — |
| [L4 #4](https://github.com/hjosugi/kofun-boot/issues/4) | replay | trace format v1 (versioned, digest-pinned like tzdb fixtures); record mode; replay mode; hostile-environment gate | — |
| [L5 #5](https://github.com/hjosugi/kofun-boot/issues/5) | speed | benchmark gate on `benchmarks/http` harness; recorded baselines; regression = failure; published same-box comparisons vs Elysia/Gin/Hono | — |
| [L6 #6](https://github.com/hjosugi/kofun-boot/issues/6) | concurrency | scoped spawn/join surface; cancellation as typed result; deterministic schedule replay | kofun #898 RFC, #736 |
| [L7 #7](https://github.com/hjosugi/kofun-boot/issues/7) | data | schema-as-contract (drizzle direction); typed queries; migrations as replayable traces; PostgREST interop | List/Text lowering maturity (kofun #919 lane) |
| [L8 #8](https://github.com/hjosugi/kofun-boot/issues/8) | cli & dx | `boot new/dev/test/bench/openapi/gen`; scaffolds that compile with the core/shell split; watch-reload | — |
| [L9 #9](https://github.com/hjosugi/kofun-boot/issues/9) | desktop | webview shell (KB-scale, gated size); wasm32 guest via host ABI v1; typed IPC = the router contract | kofun #906 activation lanes |
| [L10 #11](https://github.com/hjosugi/kofun-boot/issues/11) | site & docs | tutorial that never lies (every snippet is a gated fixture); comparison pages that show their measurement | — |
| [L11 #26](https://github.com/hjosugi/kofun-boot/issues/26) | effects & TEA | `Cmd`/`Sub` as inert data; the interpreter surface; `Result` and railway combinators; the TEA runtime; one core under every shell; effect-row migration | effect rows (kofun type-system target) for L11's final epic only |
| [L12 #27](https://github.com/hjosugi/kofun-boot/issues/27) | domain kit | constrained types and smart constructors; deriver/outcome discipline; the outcome lint; bounded-context layout; outbox; secret types | visibility slice maturity for constructor privacy |

L11 and L12 come from the research dossiers in
[`docs/research/`](research/) and the decisions in
[`docs/architecture/`](architecture/). They are the identity lanes: L11 is
*how an application asks for something to happen*, and L12 is *how it says
what it means*. Everything else in this table is a way of running them.

## Sequencing

```
now ──► L1 contract + L3 capabilities + L4 replay      (pure, unblocked, the identity of the framework)
     ──► L11 Cmd/Sub + TEA runtime                       (pure data and one interpreter; unblocked)
     ──► L2 serve v1 + L5 first baselines               (framework/http exists; numbers start accruing)
     ──► L12 domain kit + L8 cli                         (once `boot new` output compiles under the gate)
later ─► L6, L7, L9 as their language capabilities land
```

L11 sits beside L1 rather than after it because the two meet: an endpoint
value is what a request means, and a `Cmd` is what a handler asks for. Getting
them wrong in different shapes is how frameworks end up with two dependency
stories.

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
- [#31](https://github.com/hjosugi/kofun-boot/issues/31) effects: the `Cmd`/`Sub` canonical contract, pinned at its boundary, with a seed that emits a trace
- [#33](https://github.com/hjosugi/kofun-boot/issues/33) capabilities: the granted set as a printed, diffable manifest the gate reads from the binary
- [#29](https://github.com/hjosugi/kofun-boot/issues/29) desktop: IME and accessibility are gates — no number is recorded before they pass
- [#30](https://github.com/hjosugi/kofun-boot/issues/30) desktop: decompose the bar — two of the four webview costs are the language's win, not the renderer's

Blocked on a filed dependency, not on refinement:

- [#32](https://github.com/hjosugi/kofun-boot/issues/32) replay: the trace format is the `Cmd`/`Msg` sequence — blocked by [#31](https://github.com/hjosugi/kofun-boot/issues/31)

## Waiting on a decision

- [#28](https://github.com/hjosugi/kofun-boot/issues/28) **is the view a shared ADT, or platform-specific?** [R7 #22](https://github.com/hjosugi/kofun-boot/issues/22) says platform-specific; the render-backend dossier argues that this decides whether L9's "lighter than Tauri" is a claim about a webview app or a native one — and that the decision is cheap now and expensive after the first renderer exists. Only the decision owner may resolve it.
