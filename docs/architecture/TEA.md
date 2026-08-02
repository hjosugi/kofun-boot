# Architecture: one update loop, three shells

Decided 2026-08-02. Sources:
[`docs/research/WEB_FRAMEWORKS.md`](../research/WEB_FRAMEWORKS.md) §4,
[`docs/research/RENDER_BACKENDS.md`](../research/RENDER_BACKENDS.md),
[`docs/research/EFFECT_SYSTEMS.md`](../research/EFFECT_SYSTEMS.md).

## The decision

kofun-boot has **one** application shape — The Elm Architecture — and three
interpreters of it. The application author writes four pure functions; which
shell runs them decides whether the result is an HTTP server, a desktop
window, or a server-driven UI over a wire.

```kofun
fn init(flags: Flags) -> Started            # Started = { model: Model, cmd: Cmd }
fn update(msg: Msg, model: Model) -> Stepped # Stepped = { model: Model, cmd: Cmd }
fn view(model: Model) -> View
fn subscriptions(model: Model) -> Sub
```

All four are pure. None of them can name a capability. `Cmd` and `Sub` are the
inert data of [`EFFECTS.md`](EFFECTS.md); `View` is a closed ADT, **not
markup**.

## Why the same loop serves a request and paints a window

Because an HTTP request/response cycle *is* an `update` step whose model is
per-request, and a desktop frame *is* a `view` of a long-lived model. The
difference between the two is entirely in the shell:

| | server shell | desktop shell | server-driven shell |
|---|---|---|---|
| `Msg` source | a parsed request | window events, IME, timers | events forwarded over a wire |
| model lifetime | one request (plus injected state) | the process | one session, on the server |
| `view` output | a response body projection | a render tree for a backend | a **diff** of the render tree |
| `Cmd` interpreter | net/db/clock capabilities | the same, plus window ops | the same, on the server |

The three columns share `init`, `update`, `view` and `subscriptions`
unmodified. That claim is either true or it is not, so it is a gate: **the same
application module, exercised through all available shells, must produce the
same `Cmd`/`Msg` trace.**

This is also the direct answer to the LiveView/htmx question in the web
dossier. Phoenix keeps state on the server and ships diffs, and
[Dashbit's own write-up](https://dashbit.co/blog/latency-rendering-liveview)
is honest that every event round-trips. That is a *deployment choice*, not an
architecture — and it is only available as a choice if `view` returns a data
structure that can be diffed. It cannot be a choice for a framework whose
`view` returns a string of HTML.

## `View` is an ADT, and that is the load-bearing decision

Stated once more because the entire desktop roadmap rests on it: if the
application's view type is HTML, then every renderer must implement HTML, and
[the evidence for what that costs](../research/RENDER_BACKENDS.md) is that the
best-resourced attempt in the field is still pre-alpha after years.

If the view type is a closed sum we chose, a renderer is an interpreter of a
vocabulary we defined, and "replace the webview with something native" becomes
*add a second interpreter* — schedulable, gateable, and reversible.

Three rules keep it that way:

1. **No escape hatch that leaks the backend.** No `RawHtml` constructor. The
   moment one exists, every other backend has to implement HTML, and the
   property is gone. An application that genuinely needs a web-only embed
   declares a backend-specific node whose *absence* on other backends is a
   typed case the application must handle.
2. **The vocabulary is chosen for what native toolkits can do**, not for what
   CSS can express. Flexbox-class layout, text, images, inputs, scroll
   containers, canvas. Not: arbitrary selectors, cascade, filters, grid
   subgrid.
3. **Styling is values, not a cascade.** A cascade is a global, order-dependent
   computation over the whole tree — the opposite of everything else in this
   framework — and reimplementing one is most of what makes an HTML engine
   expensive.

## Diffing, and where it runs

`view` is pure and total, so the shell can call it, diff against the previous
tree, and emit patch operations. The diff runs **in Kofun, in the same
process** — which is why the desktop backend has no serialisation boundary to
optimise, only patch operations to apply.

Two consequences worth stating as design commitments:

- **Keyed children are mandatory for dynamic lists.** Every framework that made
  keys optional shipped a class of state-loss bug that its users then had to
  learn about. The contract requires a key on children of a dynamic container,
  and an unkeyed dynamic list is a build failure, not a runtime warning.
- **The diff is deterministic and its output is inspectable.** The patch stream
  is data, so it is replayable, and a renderer backend can be tested against a
  recorded patch stream with no window open at all. This is how a native
  backend gets tested in CI before it can pass rung 5 of the ladder in
  [`RENDER_BACKENDS.md`](../research/RENDER_BACKENDS.md) §4.

## What this fixes about Elm, deliberately

From the failure list in [`EFFECT_SYSTEMS.md`](../research/EFFECT_SYSTEMS.md):

| Elm's problem | why it happened | what changes here |
|---|---|---|
| ports do not pair requests with responses | ports are one-way channels | every `Cmd` carries `on_result: MsgId` |
| a port-as-`Task` may never terminate | foreign code owns the callback | the interpreter owns the deadline; a timeout is a `Msg` |
| effect managers stalled | `Cmd` is closed to the framework | `Cmd` is open; an interpreter is an ordinary function |
| cancellation is hard to express | no scope concept | effects are scope-bound (blocked on kofun #898) |
| the model must hold data that should be in scope | `update` returns to a single dispatch point | unchanged — this is the honest cost of TEA, and it is the price of replay |

The last row matters. This design does not pretend TEA is free. Threading
temporary state through the model is genuinely more ceremony than a local
`await`, and the compensation is that every run is replayable and every state
transition is a value you can print. That is a trade worth making for
production software and not obviously worth making for a script — so the
framework should say so, rather than claim the trade does not exist.

## Boundaries this design does not yet cross

- **`view` for the server shell** is a projection to a response body. Whether
  HTML generation for the server shell shares the `View` ADT or is a separate
  templating surface is **an open decision**, and it is filed as one rather
  than assumed. Sharing it buys server-driven UI for free; not sharing it
  avoids constraining server HTML to the native-renderable vocabulary.
- **Model persistence and hot reload** are not designed here.
- **Concurrency inside `update`** does not exist and will not: `update` is
  synchronous and pure. Concurrency lives in the interpreter, which is why the
  L6 lane is blocked on the language rather than on this document.
