# Architecture: the effect model

Decided 2026-08-02 from [`docs/research/EFFECT_SYSTEMS.md`](../research/EFFECT_SYSTEMS.md).
This document is the reasoning; the canonical shapes belong in `contracts/`
and the executable evidence in `seed/`.

## The decision in one paragraph

kofun-boot has **no monad abstraction and no effect system of its own.** The
core asks for work by *returning inert data* — a value of an open sum `Cmd` —
and the shell interprets that data using capabilities it was handed as
arguments. Sequencing inside the core uses `Result` and a small set of
combinators, monomorphised per type until the language says otherwise. When
Kofun's effect rows land, the capability record becomes a checked row and the
framework's grep-based FCIS gate is retired in favour of a type rule; **the
`Cmd` sum does not change when that happens**, which is why the two are
specified separately.

## Why not a monad

Because it is not expressible, and because it is not the part that makes Elm
understandable.

Not expressible: Kofun's
[implemented-status matrix](https://github.com/hjosugi/kofun/blob/main/docs/MVP_IMPLEMENTED.md)
records the general parser and type checker as open, enum matching as a
bounded slice carrying one `Int` payload, and records lowering `Int`/`Bool`
fields. `Monad m => m a` needs higher-kinded types and type classes; neither
exists. A framework that specified one would be specifying against a compiler
that cannot check it — the exact failure the language repository's claim
manifest exists to prevent.

Not the point: Elm has no effect system and is the clearest thing in the
field. Its clarity comes from `Cmd msg` being *data you can print*, not from
monadic sequencing. What a beginner needs to understand is "my function
returned a description of an HTTP request, and the runtime made it happen" —
and that sentence is true with or without a monad.

## The four layers

```
┌─ layer 4 ── effect rows ──────────────────── (blocked on the language) ──┐
│  the capability record becomes a checked effect row; the FCIS gate       │
│  becomes a type rule. Cmd is unchanged.                                  │
├─ layer 3 ── Cmd / Sub as data ──────────────────────── (the interface) ──┤
│  the core returns descriptions; the shell interprets them                │
├─ layer 2 ── Result and railway combinators ─────── (sequencing in core) ─┤
│  typed failure in the signature; no exceptions, no sentinel values       │
├─ layer 1 ── capability records ───────────────────── (the shell's hand) ─┤
│  clock, entropy, log, net, db — values, passed as arguments              │
└──────────────────────────────────────────────────────────────────────────┘
```

Layers 1 and 2 exist in the repository today in spirit: `contracts/boot.kofun`
declares `Capabilities`, and `seed/router/router.kofun` proves a handler that
receives its one capability as an argument and is pure. Layer 3 is the new
work this design adds. Layer 4 is somebody else's lane, in another repository.

## Layer 1 — capability records

Unchanged from `docs/DESIGN.md`, restated here because layer 3 depends on it:
a dependency is a value; the composition root is the single place a capability
record is built; the core cannot name one.

Three additions this design commits to:

1. **Capabilities are printable.** The shell prints the effective capability
   record at startup — which clock, which network policy, which scopes. WASI
   components carry a WIT world and Tauri carries a JSON ACL for exactly this
   reason; ours is derived from the type rather than maintained beside it, but
   it must still be *readable by an operator who is not reading the code*.
2. **Capabilities are scoped, not just present.** A filesystem capability is
   not "the filesystem"; it names its roots. This is Tauri's scopes idea and it
   is the difference between a capability system and a feature flag.
3. **Fakes are the same record.** The test kit is not a parallel
   implementation; it is the same record type with different fields. This is
   the property that makes deterministic replay cheap, and it must be
   re-exported as a first-class package rather than rediscovered per
   application.

## Layer 2 — `Result` and the railway

Typed failure in the signature, no exceptions, no sentinels. The domain
vocabulary is the one `docs/research/FDDD` work uses: a *deriver* is a pure
function returning a **closed sum** of domain outcomes, and `Result` is for
failures that are not domain outcomes.

That distinction is the one beginners get wrong, so the framework states it
once, sharply, borrowing the formulation from the F# lab this design draws on:

> "Can this be approved under these conditions?" is a domain outcome — a
> constructor of a closed sum. "The database connection failed" is a system
> failure — an `Err`. A rejected upgrade is not an error; it is an answer.

`RouteResult` in `contracts/boot.kofun` already follows this: `NotFound`,
`MethodNotAllowed(allowed)` and `PayloadTooLarge(limit, observed)` are
*answers*, each carrying what was observed, and none of them is an `Err`.

The combinator set stays deliberately tiny — `map`, `and_then`, `map_err`,
`or_else`, and a propagation operator — because the value of railway-oriented
programming is that failure is in the signature, not that there are forty
combinators.

Bounded by the compiler today: generics over `Result[T, E]` are not generally
available, so the first landing is **monomorphised per concrete pair**,
generated from the contract rather than hand-written. That is a real
limitation and the issue for it says so rather than pretending otherwise.

## Layer 3 — `Cmd` and `Sub` as data

The interface between the halves. The core never performs an effect; it
returns one.

```kofun
# What the core asks for. Open: an application adds its own constructors.
type Cmd =
    | None
    | Batch(commands: List[Cmd])
    | HttpRequest(request: OutboundRequest, on_result: MsgId)
    | ReadClock(on_result: MsgId)
    | Persist(entity: EntityId, bytes: Bytes, on_result: MsgId)
    | Custom(tag: CmdTag, payload: Bytes, on_result: MsgId)

# What the core asks to be told about, unprompted.
type Sub =
    | NoSub
    | Every(interval_ms: Int, on_tick: MsgId)
    | OnSignal(signal: SignalId, on_signal: MsgId)
    | Custom(tag: SubTag, payload: Bytes, on_event: MsgId)
```

Four properties, each chosen against a documented failure elsewhere:

**Every `Cmd` names its continuation.** `on_result: MsgId` is not optional.
This is the fix for Elm's [ports-do-not-pair-requests-with-responses
problem](https://cscalfani.medium.com/the-biggest-problem-with-elm-4faecaa58b77):
correlation is in the constructor, so no application has to invent a
correlation id.

**`Custom` makes the sum open.** Elm's `Cmd` is closed to the framework, which
is why [effect managers stalled](https://groups.google.com/g/elm-discuss/c/_cfOu88oCx4/m/madaA1rBAQAJ)
and why every unusual effect became a port. Here, an application's interpreter
is an ordinary Kofun function, so an application-defined effect is not a
special case of anything.

**Interpretation is total, and failure is a `Msg`.** An interpreter must
produce a `Msg` for every `Cmd` it accepts, including the failure and timeout
cases. Elm's [task/port termination
hole](https://gist.github.com/alpacaaa/13335246234042395813d97af029b10f) —
foreign code that simply never calls back — is closed by making the *deadline*
part of the interpreter's contract, not the caller's discipline.

**Cancellation is a `Cmd`, and scope-bound.** A spawned effect belongs to a
scope; leaving the scope cancels it. This is where the structured-concurrency
lane (L6) meets this design, and it is blocked on the language RFC — so the
`Cmd` set ships without unscoped spawn rather than shipping a leak we would
have to break.

### Why this is the replay format

This is the property that pays for the whole design.

A recorded run **is** the sequence of `Cmd`s the core emitted and the `Msg`s
the shell fed back. It is data, it is already serialisable, and it needs no
instrumentation — because the core could not have done anything else. Replay
is: run the same `init`, feed the recorded `Msg` sequence, assert the emitted
`Cmd` sequence is identical.

Compare with the alternative designs: a monadic core has to be *instrumented*
to be recorded, and what gets recorded is an interpreter's trace rather than
the program's own output. Here the trace is the program's output. The existing
gate discipline — run twice, `cmp`; run under `TZ=Pacific/Kiritimati`, a
hostile locale and `env -i`, `cmp` again — applies to it unchanged.

## Layer 4 — effect rows, when they land

Kofun's type-system document names effects and row polymorphism as targets.
When they arrive:

- the capability record becomes a checked effect row, and passing capabilities
  explicitly becomes optional sugar rather than the mechanism;
- the FCIS gate — which today greps core modules with comments stripped for
  capability names — is deleted and replaced by the type rule, which is
  strictly better because a grep cannot see indirection;
- **`Cmd` does not change.** An application written against layer 3 keeps
  compiling. This is the entire reason the two are specified as separate
  layers, and it is the promise the versioning policy has to hold.

## What this buys, stated as claims a gate can check

| claim | how it is checked |
|---|---|
| a core module cannot perform an effect | FCIS gate: comments stripped, capability names greped, as `tests/boot/check.sh` already does for the seed |
| every run is byte-replayable | record `Cmd`/`Msg`, replay, `cmp`; then re-run under hostile `TZ`, locale and `env -i` |
| the same core runs under any shell | one core, interpreted by the server shell and the desktop shell, both gated on the same trace |
| an effect cannot outlive its scope | blocked on kofun #898; the gate lands with the surface |
| the granted capability set is auditable | the shell prints the effective record; the gate reads the printed record, not the source |

## What this refuses

- **A `Monad` abstraction**, now or after effect rows land. Nothing in the
  design needs one.
- **A closed `Cmd` set.** Openness is the fix for Elm's four documented
  problems, not a convenience.
- **Ambient anything.** Including "just for tests" and "just for logging". A
  logger that can be reached without being handed over is an ambient authority
  wearing a friendly name.
- **Async/await syntax over an implicit runtime.** The runtime would be
  ambient, and the whole design is that it is a value.
