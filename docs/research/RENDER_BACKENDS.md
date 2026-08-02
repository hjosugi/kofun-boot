# Dossier: render backends — can the webview be replaced?

Written 2026-08-02. Every external claim links its source.

This dossier answers the roadmap's hardest question directly:

> **Can a webview-based desktop app eventually be replaced by a native one,
> and made faster? What is past Tauri?**

Short answer: **yes, but only for an application whose view is a data
structure rather than markup.** For an application that ships HTML, the
replacement is the most expensive project in the entire field, and the
evidence for that is sitting in public.

## 1. Why replacing a webview is hard — the evidence

Two teams are seriously attempting it, from opposite directions.

**Blitz** (Dioxus Labs) builds a new HTML/CSS engine out of the Rust
ecosystem's parts: [stylo for style, taffy for layout, parley for text, vello
on wgpu for painting, accesskit for accessibility, html5ever for
parsing](https://github.com/DioxusLabs/blitz). It supports flexbox, grid,
table, block and inline layout, absolute and fixed positioning, complex
selectors, media queries, CSS variables and form controls — and it is, in its
own README's words, **"currently in a pre-alpha state… still many bugs and
missing features."** Dioxus's own materials put the native renderer at
[broadly usable beta around the end of 2025 and production-ready sometime in
2026](https://dioxuslabs.com/blog/release-070/), and on Hacker News it is
still [described as an experimental native
renderer](https://news.ycombinator.com/item?id=46353240).

**Verso/Servo** goes the other way: keep the real web platform, own the
engine. Servo support was added to WRY, Tauri's webview layer, and there is
[an experimental Tauri–Verso
integration](https://v2.tauri.app/blog/tauri-verso-integration/) — which
[currently supports only a small subset of features, with window decorations,
titles and transparency still to
come](https://github.com/orgs/tauri-apps/discussions/15235).

Now read those two results together. Blitz has a talented team, the best
available components, and years of work, and it is pre-alpha — **because
HTML/CSS is the specification, and the specification is enormous.** Verso is
further along on compatibility precisely because it *is* a browser engine —
and a browser engine is the thing we were trying not to ship.

So the field's honest state is:

| path | what it costs | what it buys |
|---|---|---|
| system webview | zero engine code; a process tree; an IPC boundary | full CSS, text, IME, a11y, video, printing, hi-DPI — from the OS |
| new HTML/CSS engine (Blitz) | reimplementing the web platform | native binary, no webview process — eventually |
| embed a real engine (Servo/Verso) | shipping a browser | consistency across platforms; a *bigger* binary, not smaller |
| **native widgets, no HTML** | writing a UI vocabulary | a small engine — because the vocabulary is small |

The fourth row is the one nobody in the Tauri lineage can take, and the only
one kofun-boot can.

## 2. Why Tauri cannot take the fourth row, and we can

Tauri's application-facing contract **is the DOM**. An app ships HTML, CSS and
JavaScript. Therefore any replacement renderer must implement HTML, CSS and
JavaScript, or it is not a replacement — it is a different framework. That
constraint is not a Tauri mistake; it is the direct consequence of choosing
the web as the authoring surface, and it is what makes Blitz's job as large as
it is.

kofun-boot's application-facing contract is a **closed Kofun ADT**:

```kofun
type View =
    | Text(content: Text, style: StyleId)
    | Row(children: List[View], layout: LayoutId)
    | Column(children: List[View], layout: LayoutId)
    | Input(value: Text, on_change: MsgId)
    | Button(label: Text, on_click: MsgId)
    | ...
```

A renderer is an **interpreter of that ADT**. Consequences, and this is the
whole argument:

1. **The webview is one interpreter, not the foundation.** It renders the ADT
   by emitting DOM operations. It is the fast way to ship, and it inherits the
   OS engine's text shaping, IME, accessibility, video and printing.
2. **A native renderer is another interpreter.** It never sees HTML, so it
   never needs stylo, and it never needs a CSS cascade — because the ADT
   *already is* the layout language, and we chose it. It needs layout (taffy
   or equivalent), text shaping (parley/HarfBuzz), painting (vello/wgpu or
   platform 2D), IME plumbing, and AccessKit. That is a large project. It is
   not the web platform.
3. **The application does not change when the backend does.** The same
   `view : Model -> View` runs under both. This is the *only* mechanism by
   which "eventually replace the webview" is a schedulable engineering task
   rather than a rewrite.
4. **The comparison stops being webview-vs-native and becomes
   interpreter-vs-interpreter, measurable on the same app.** The L9 gate can
   run one application under both backends and record both numbers. That is a
   real measurement, and it is one almost nobody in this field can make.

## 3. Where the speed actually comes from

From [`DESKTOP_FRAMEWORKS.md`](DESKTOP_FRAMEWORKS.md) §2, the webview's costs
decompose into four, and they are not equal:

| cost | webview backend | native backend | who really pays it |
|---|---|---|---|
| ship a browser | **already avoided** by using the system webview | avoided | Electron only |
| JS bundle parse + execute + hydrate | **avoided by us**: there is no JS application | avoided | every JS-frontend framework, including Tauri apps |
| IPC serialisation across a language boundary | **avoided by us**: same program, same types | avoided | Tauri, by construction |
| webview process tree + DOM | paid | avoided | webview backends |

Two of those four we avoid on *both* backends, and we avoid them because of
the language, not because of the renderer. That is the honest, non-obvious
result of this dossier:

> **Most of the performance win that "going native" is supposed to deliver is
> actually the win from not having a JavaScript frontend and not having a
> cross-language IPC boundary — and kofun-boot gets both of those on the
> webview backend, on day one.**

The native backend's remaining prize is the fourth row: no webview process, no
DOM, direct GPU painting, and control over frame scheduling. [Zed's
GPUI](https://zed.dev/blog/videogame) is the proof that this is worth having —
they rasterise the whole window on the GPU with custom shaders for a handful
of primitives (rectangles, shadows, text, icons, images) and target 120 FPS.
It is a real prize. It is also, on the evidence in §1, the *smaller* half of
the total, and it arrives years later. Sequencing the lane any other way would
be trading the certain, larger win for the uncertain, smaller one.

## 4. What a native backend must earn, in order

This is the gate ladder for L9's native lane. Each rung is a gate, and no
performance number is recorded before rung 4 passes.

1. **A window, and a frame.** Draw the ADT. Resize, hi-DPI, multiple monitors
   with different scale factors.
2. **Text that is correct before it is fast.** Shaping via a real shaper,
   bidi, grapheme-correct cursor movement, font fallback across scripts.
   Kofun already carries Unicode 17 gates; the renderer must not regress the
   language's own standard.
3. **IME.** Composition string rendered inline, candidate window positioned at
   the caret, commit and cancel, preedit reported to accessibility. Japanese,
   Chinese and Korean each in the gate. Rationale and evidence:
   [`DESKTOP_FRAMEWORKS.md`](DESKTOP_FRAMEWORKS.md) §5 — this is the single
   most common failure in the field.
4. **Accessibility.** [AccessKit](https://accesskit.dev) tree published, focus
   and roles correct, verified against a platform screen reader.
5. **Platform integration.** Menus, clipboard, drag and drop, file dialogs,
   notifications, dark mode, reduced motion.
6. *Only now:* frame time, memory, binary size, cold start — against the
   webview backend, same application, same box.

Rungs 2–4 are where this field dies. Publishing a frame-rate number from a
backend that cannot accept Japanese input would be exactly the kind of claim
this repository's gate culture exists to prevent.

## 5. Further out than the native backend

Three directions worth tracking, none of them scheduled:

- **wasm32 guests.** Kofun already emits wasm32 and pins a host ABI. The same
  `View` ADT crossing a component boundary makes plugins and sandboxed
  extensions the same shape as applications. [WASI Preview 2 is stable and
  built on the component model and WIT, with Preview 3 adding native async
  I/O](https://eunomia.dev/blog/2025/02/16/wasi-and-the-webassembly-component-model-current-status/) —
  a component's WIT world is a capability list, which is the same idea as the
  capability record, written in another notation.
- **Server-driven native UI.** If `update` is transport-independent (see
  [`TEA.md`](../architecture/TEA.md)) then LiveView's trick — state on the
  server, diffs on the wire — applies to a *native window* as readily as to a
  browser. Nobody ships this well today.
- **Embedded.** [Slint reaches STM32- and RP2040-class
  targets](https://github.com/slint-ui/slint) with a software renderer.
  Kofun's native images are already kilobyte-scale. The same `View` ADT with a
  software rasteriser is not obviously out of reach, and it is a *much* better
  fit for a language with no runtime than for one with a garbage collector.

## 6. The decision

**Two backends, one application, staged; the ADT is the contract between
them.**

- **Backend A (system webview) is the default and stays supported forever.**
  It is not a stepping stone to be discarded — it is the backend that gets
  IME, accessibility, text shaping, video and printing correct on every
  platform for free, and for a large class of applications it will remain the
  right answer.
- **Backend B (native) is additive, gated, and off by default until rung 5.**
- **Refused: writing an HTML/CSS engine.** §1 is the evidence.
- **Refused: embedding a browser engine by default.** Verso stays an option a
  user may select when cross-platform rendering consistency outweighs binary
  size — never the default, because shipping a browser is the thing we are
  here not to do.

## Sources

- [Blitz README](https://github.com/DioxusLabs/blitz) ·
  [Blitz: a modular web renderer (Web Engines Hackfest slides)](https://webengineshackfest.org/2024/slides/blitz_a_truly_modular_hackable_web_renderer_by_nico_burns.pdf)
- [Dioxus 0.7 release notes](https://dioxuslabs.com/blog/release-070/) ·
  [dioxus-native on lib.rs](https://lib.rs/crates/dioxus-native)
- [Experimental Tauri–Verso integration](https://v2.tauri.app/blog/tauri-verso-integration/) ·
  [Tauri + Servo discussion](https://github.com/orgs/tauri-apps/discussions/15235) ·
  [Servo embedding update](https://servo.org/blog/2024/01/19/embedding-update/)
- [Zed: rendering UI at 120 FPS on the GPU](https://zed.dev/blog/videogame)
- [AccessKit](https://accesskit.dev) · [Slint](https://github.com/slint-ui/slint)
- [WASI and the component model: current status](https://eunomia.dev/blog/2025/02/16/wasi-and-the-webassembly-component-model-current-status/)
