# Dossier: effect systems

Written 2026-08-02. Every external claim links its source.

The question: **how do languages that take effects seriously actually handle
them, and which of those designs survives in a language with no higher-kinded
types, no type classes, and a deliberately small executable core?**

That last clause is the binding constraint. Kofun's
[type system document](https://github.com/hjosugi/kofun/blob/main/docs/TYPE_SYSTEM.md)
names ADTs, traits, effects and row polymorphism as *targets*; the
[implemented-status matrix](https://github.com/hjosugi/kofun/blob/main/docs/MVP_IMPLEMENTED.md)
records that the general parser and type checker are open, that enum matching
is a bounded slice with one `Int` payload, and that records lower `Int`/`Bool`
fields. A design that needs `Monad m => m a` is not a design for this
language. A design that needs a closed sum and an interpreter is.

## 1. The families

### Monad transformers and `ReaderT IO`

Haskell's oldest answer, and still the pragmatic one. The Haskell community's
own summary is unusually blunt: [most popular monad transformers other than
`ReaderT` are "rife with subtle
issues"](https://github.com/haskell-effectful/effectful), which is exactly why
the `ReaderT` design pattern became the recommendation — carry an environment
record in a reader, do effects in `IO`, and stop trying to stack transformers.

That is worth staring at, because **`ReaderT Env IO` is the capability record**.
The most battle-tested effect design in the most effect-serious mainstream
language converged on: *pass a record of your dependencies as an argument*.

### Extensible effects: effectful, fused-effects, Bluefin

[`effectful`](https://github.com/haskell-effectful/effectful) describes itself
as a replacement for the bare `ReaderT` pattern — "essentially its enriched
version" — with better semantics, performance and reuse.
[Bluefin](https://hackage.haskell.org/package/bluefin/docs/Bluefin.html) makes
the contrast explicit and instructive: **in Bluefin, effects are value-level
capabilities; in effectful they are type-level only.** Bluefin's author
describes his own library as a well-typed implementation of *the Handle
pattern*.

Value-level capabilities. Handles passed as arguments. Kofun's clock is an
affine handle passed as an argument. These are the same design, arrived at
independently, and one of them is already in the language.

### Algebraic effects and handlers: Koka, Eff, OCaml 5, Unison

The academically strongest answer. [Koka is a strongly typed functional
language with a polymorphic type-and-effect system and
handlers](https://github.com/koka-lang/koka); OCaml 5 is [the first industrial
language shipping algebraic effects, storing continuations in the heap so
user-level schedulers like Eio can be written in
library](https://interjectedfuture.com/algebraic-handler-lookup-in-koka-eff-ocaml-and-unison/);
Unison calls them abilities; Effekt uses a capability-based type system where
effect types express what a computation needs from its context.

Two facts matter for us. First, **the handler lookup is dynamic — nearest
enclosing handler at run time — and the type system's job is to guarantee the
search succeeds**. Second, the performance story is not free: [most
handler-based programs remain much slower than hand-written code, though
optimising compilers can close the
gap](https://dl.acm.org/doi/10.1145/3485479).

For kofun-boot this is the *destination*, not the *starting point*. When
Kofun's effect rows land, a capability record becomes a checked effect row and
the framework's FCIS grep gate can be retired in favour of a type rule. Until
then, building on machinery the compiler does not have would be exactly the
kind of unfounded claim this repository refuses.

### Effects as a data structure: Elm

Elm has no effect system at all, and is the most *understandable* member of
this list. `Cmd msg` is **inert data**. `update` returns a description of what
should happen; the runtime interprets it; results come back as `Msg`. Purity is
preserved not by tracking effects in types but by *never performing them in the
first place*.

This is the design that survives Kofun's current type system intact, because
it needs precisely one thing: a closed sum type and a function that interprets
it.

Elm's community also documented the failure modes honestly, and they are
instructive because they are avoidable:

- [Ports do not scale for request/response pairing](https://cscalfani.medium.com/the-biggest-problem-with-elm-4faecaa58b77) —
  a message out and a matched message back is not expressible, so callers hand-roll correlation.
- [Making a port a `Task` breaks the `Task` guarantee](https://gist.github.com/alpacaaa/13335246234042395813d97af029b10f):
  a `Task` must terminate with an error or a result, and foreign code may
  simply never call back.
- [Effect managers stalled](https://groups.google.com/g/elm-discuss/c/_cfOu88oCx4/m/madaA1rBAQAJ),
  leaving no supported way to build effects on effects.
- Cancellation lifecycle is [hard to express explicitly](https://groups.google.com/g/elm-discuss/c/BR-f9qXbt3k/m/c-7bHvMgiigJ).

Every one of those is a consequence of `Cmd` being *closed to the framework*
and foreign calls escaping the model. A framework whose `Cmd` set is **open to
the application** and whose interpreter is **a Kofun function the application
can supply** does not inherit them.

### Effects as a runtime service: Effect-TS, ZIO

The industrial end. [Effect-TS](https://www.effect.website/) bundles typed
errors, structured concurrency and dependency injection via Service/Layer, and
is used in production; its own guidance is to [start from a managed runtime
and build up](https://noqta.tn/en/blog/effect-ts-functional-typescript-production-ai-2026),
and the reported ramp for a developer is 3–6 weeks. That ramp is the number to
remember. It is the price of an effect system that is a *library* rather than
a language feature, and it is why `docs/DESIGN.md` refuses type gymnastics.

The parts worth taking are not the encoding, they are the *operational*
features Effect-TS and ZIO proved matter in production: typed errors as part
of the signature, structured concurrency where a child cannot outlive its
scope, resource safety on cancellation, and retry/timeout as ordinary values.

### Effects as a platform boundary: Roc

The closest existing thing to kofun-boot's whole thesis.
[Roc splits an application from its platform](https://www.roc-lang.org/platforms):
the platform provides memory management and I/O and determines how the program
starts; the application stays pure. In execution terms, [the app returns a
chain of tasks to the platform, the platform runs them and resumes the app
with the results](https://github.com/roc-lang/roc/wiki/Roc-concepts-explained).
Because the platform owns every I/O primitive, [a platform author can
implement sandboxing](https://gotopia.tech/articles/293/intro-to-roc-innovation-in-functional-programming)
— capability security as a consequence of the architecture rather than a
feature added to it.

Read that against `docs/DESIGN.md`'s opening sentence — *an application is a
pure function from its capabilities to its behaviour; kofun-boot is the shell
that wires, serves, replays, and measures it* — and they are the same claim.
Roc puts the shell in another language; kofun-boot puts it in Kofun, in the
same program.

### Capabilities as configuration: WASI, Tauri

Two non-FP systems arrived at capability security from operational pressure.
[A WASI Preview 2 component carries a WIT world declaring every interface it
imports and exports, and components compose by linking exports to
imports](https://eunomia.dev/blog/2025/02/16/wasi-and-the-webassembly-component-model-current-status/) —
a capability list as a build artifact. Tauri v2's default-deny
capability/permission/scope ACL is the same posture expressed in JSON
(see [`DESKTOP_FRAMEWORKS.md`](DESKTOP_FRAMEWORKS.md) §3).

Both are compensating for host languages with ambient authority. Kofun does
not have ambient authority, so the equivalent artifact is not a JSON file — it
is the type of the composition root. What is still worth importing is that
both systems **make the granted set an inspectable artifact**. A capability
record that is only visible by reading code is auditable by developers; one
that can be *printed and diffed* is auditable by an operator.

## 2. The comparison that decides it

| design | needs from the type system | usable in Kofun today | replayable |
|---|---|---|---|
| monad transformers | HKT, type classes | no | via the base monad only |
| extensible effects | HKT, type-level lists | no | depends on handlers |
| algebraic handlers | effect rows + handler lookup | not yet — named as a target | yes, handlers are pluggable |
| **effects as data (Elm)** | **a closed sum + a function** | **yes** | **trivially: the trace *is* the data** |
| capability record (`ReaderT`/Handle/Roc) | records and functions | **yes — already the language's model** | yes: fakes are the same record |
| runtime service (Effect-TS/ZIO) | a large library and 3–6 weeks | no | partially |

Two rows are green in the middle column, and they are complementary rather
than competing:

- the **capability record** answers *how does the shell reach the world*;
- **effects as data** answers *how does the core ask for something to happen*.

Together they are exactly Functional Core / Imperative Shell, with the `Cmd`
sum as the interface between the halves, and the capability record as the
thing only the shell holds.

## 3. What kofun-boot takes

| from | what |
|---|---|
| Elm | `Cmd`/`Sub` as inert data interpreted by the runtime — the one design that needs nothing the compiler lacks |
| Elm's failure modes | make the `Cmd` set **open to the application** and the interpreter an ordinary Kofun function, so ports, effect managers and correlation are not special cases |
| Roc | the platform/application split as the framework's spine; the shell owns every I/O primitive, so sandboxing is a consequence |
| `ReaderT` / Bluefin's handles | value-level capabilities passed as arguments; this is already Kofun's model, and the most experienced community converged on it |
| Effect-TS / ZIO | the *operational* list: typed errors in the signature, structured concurrency, resource safety under cancellation, retry and timeout as values |
| Koka / OCaml 5 | the destination: when effect rows land, the capability record becomes a checked row and the FCIS grep gate is replaced by a type rule |
| WASI / Tauri | the granted capability set should be a printable, diffable artifact, not only readable code |

## 4. What kofun-boot refuses

- **A `Monad` abstraction.** Not expressible today, and Elm is the proof it is
  not required for the clarity we are actually after. Sequencing is an
  implementation detail; *effects being inert data* is the understandable part.
- **A monomorphic `Cmd` closed to the framework.** Elm's four documented pain
  points all trace back to this.
- **Waiting for effect rows.** The design must run on today's compiler and
  *upgrade* when rows land, which is why the capability record and the `Cmd`
  sum are specified as separate things: rows replace the first, not the second.
- **A 3–6 week ramp.** If a developer cannot write a correct handler on day
  one, the design failed regardless of its type-theoretic pedigree.

The resulting design is written up in
[`docs/architecture/EFFECTS.md`](../architecture/EFFECTS.md).

## Sources

- [effectful](https://github.com/haskell-effectful/effectful) ·
  [Bluefin](https://hackage.haskell.org/package/bluefin/docs/Bluefin.html) ·
  [fused-effects](https://github.com/robrix/fused-effects)
- [Koka](https://github.com/koka-lang/koka) ·
  [Algebraic handler lookup in Koka, Eff, OCaml and Unison](https://interjectedfuture.com/algebraic-handler-lookup-in-koka-eff-ocaml-and-unison/) ·
  [Efficient compilation of algebraic effect handlers](https://dl.acm.org/doi/10.1145/3485479) ·
  [Algebraic effects for functional programming (Leijen)](https://www.microsoft.com/en-us/research/wp-content/uploads/2016/08/algeff-tr-2016-v2.pdf)
- [The biggest problem with Elm](https://cscalfani.medium.com/the-biggest-problem-with-elm-4faecaa58b77) ·
  [Hard things about ports being Tasks](https://gist.github.com/alpacaaa/13335246234042395813d97af029b10f) ·
  [Design of large Elm apps](https://groups.google.com/g/elm-discuss/c/_cfOu88oCx4/m/madaA1rBAQAJ)
- [Effect-TS](https://www.effect.website/) ·
  [Effect-TS in production, 2026](https://noqta.tn/en/blog/effect-ts-functional-typescript-production-ai-2026)
- [Roc: platforms and apps](https://www.roc-lang.org/platforms) ·
  [Roc concepts explained](https://github.com/roc-lang/roc/wiki/Roc-concepts-explained) ·
  [Intro to Roc](https://gotopia.tech/articles/293/intro-to-roc-innovation-in-functional-programming)
- [WASI and the component model: current status](https://eunomia.dev/blog/2025/02/16/wasi-and-the-webassembly-component-model-current-status/)
