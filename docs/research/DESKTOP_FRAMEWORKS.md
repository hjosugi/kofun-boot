# Dossier: desktop application frameworks

Written 2026-08-02. Every external claim links its source; every number is
somebody else's measurement, attributed as such.

The question: **what does a desktop app actually cost, and which of those
costs are the webview's fault?** The answer matters because the second
question the roadmap has to settle — *can the webview be replaced by something
native and faster?* — is unanswerable until you know what the webview is
charging you for.

## 1. The published numbers, and who published them

Third-party comparisons of Tauri v2 against Electron, [collected in 2026
round-ups](https://tech-insider.org/tauri-vs-electron-2026/):

| measure | Tauri (reported) | Electron (reported) |
|---|---|---|
| hello-world bundle | 3.2 MB | 85 MB |
| six-window app | 8.6 MB | 244 MB |
| idle resident memory | 42 MB | 168 MB |
| cold start | 380 ms | 1420 ms |
| IPC round trip | 0.12 ms | 0.45 ms |

Other round-ups give ranges rather than points — [2–10 MB for Tauri against
80–200 MB for Electron, and roughly 50 MB against 120 MB+
RSS](https://www.pkgpulse.com/guides/electron-vs-tauri-2026) — which is the
honest way to read all of these: **the orders of magnitude are the signal, the
digits are not.** None of these were measured by us and none of them are
kofun-boot bars.

## 2. Reading the table properly

The interesting result is not "Tauri wins". It is *which column each win comes
out of*.

**Binary size** is Chromium. Tauri does not ship a browser; it calls the one
already installed (WebView2, WKWebView, WebKitGTK). That saving is available
to anyone who makes the same choice, including us, and it is the largest
single number in the table.

**Memory** is the process tree. Electron pays for a Chromium multi-process
model plus a V8 isolate per renderer plus a Node main process. Tauri pays for
the system webview's process tree and a Rust binary.

**Cold start** is mostly *not* the webview. The system webview on Windows and
macOS is frequently already warm in the OS. A large share of a webview app's
start cost is parsing and executing the application's own JavaScript bundle,
then hydrating a DOM. That cost belongs to the frontend stack, not to the
renderer — which means an application whose UI logic is compiled native code
does not pay it whichever renderer it uses.

**IPC** is the one that is architectural. Tauri's 0.12 ms is the cost of
serialising a call across a language and process boundary, because in Tauri
the frontend genuinely is a different program in a different language. A
framework whose UI logic and whose shell are *the same compiled program* does
not have that boundary to cross; the "IPC" is a function call. This is the
cost kofun-boot can remove outright rather than optimise, and it is argued in
[`RENDER_BACKENDS.md`](RENDER_BACKENDS.md).

## 3. Tauri's real contribution is its security model

The size numbers get the attention; the [capability
system](https://v2.tauri.app/security/capabilities/) is the better idea and
the one worth copying.

Tauri v2 replaced v1's allowlist with three layers —
[**capabilities**](https://v2.tauri.app/reference/acl/capability/) (JSON files
saying what a given window may access),
[**permissions**](https://v2.tauri.app/reference/acl/permission/) (which
commands are allowed), and **scopes** (which paths/domains a command may
touch) — under a default-deny posture, with [the webview treated as untrusted
and every IPC surface required to declare which window may call which command
with which scope](https://deepwiki.com/tauri-apps/tauri-docs/5.8-security-and-capabilities-system).

That is a capability system bolted onto a language that does not have one, and
it works. Kofun *does* have one: there is no ambient authority, a clock is an
affine handle, the environment is a capability. So the equivalent of Tauri's
JSON ACL is, for us, **the type of the composition root** — and the equivalent
of "this window may not read the filesystem" is "this function was never
handed a filesystem capability, so it does not compile."

The part still worth importing is the *posture*, not the mechanism:
default-deny, scopes that name resources rather than operations, and a printed,
auditable manifest of what the application was actually granted.

## 4. The native-UI field, and why most of it is not ready

For the "replace the webview" question, the relevant field is native toolkits.
The most useful single data point is [boringcactus's 2025 survey of Rust GUI
libraries](https://www.boringcactus.com/2025/04/13/2025-survey-of-rust-gui-libraries.html),
which reports that **94.4% of the libraries surveyed were not
production-ready**, on criteria as basic as "does it build" and "does text
input work".

What each of the serious contenders is:

| project | model | rendering | notes |
|---|---|---|---|
| [Slint](https://github.com/slint-ui/slint) | declarative `.slint` DSL, retained | femtovg (GLES2), Skia, software, Qt | targets MCUs through desktop through wasm; Rust/C++/JS/Python bindings; tri-licence including a royalty-free option |
| [Xilem](https://github.com/linebender/xilem) | reactive view tree over the Masonry retained widget tree | Vello on wgpu, Parley/Fontique text, AccessKit | from the Druid team; self-described experimental |
| [Blitz](https://github.com/DioxusLabs/blitz) | HTML/CSS renderer | stylo, taffy, parley, vello, wgpu, accesskit | self-described **pre-alpha**; see `RENDER_BACKENDS.md` |
| GPUI (Zed) | hybrid immediate/retained | custom shaders per primitive | [rasterises the whole window on the GPU like a game, targeting 120 FPS](https://zed.dev/blog/videogame); shipped in a real product |
| egui | immediate mode | its own painter | fastest to a window; the survey's IME finding below applies |
| iced | Elm-inspired, retained | wgpu/tiny-skia | the closest existing thing to the architecture kofun-boot wants |

And the cross-platform non-Rust field, for completeness: Flutter (own engine,
own text stack, own accessibility bridge), Compose Multiplatform (Skia),
Avalonia and .NET MAUI, Qt and GTK, and
[Lynx](https://thenewstack.io/cross-platform-ui-framework-lynx-competes-with-react-native/),
ByteDance's dual-threaded engine which keeps UI work on a main thread driven
by PrimJS and everything else off it — a design worth noting because *the
threading split, not the renderer, is where it claims its wins over React
Native*.

## 5. The finding that should govern the whole desktop lane: IME

This is the most important paragraph in this dossier for a framework whose
first users write Japanese.

Drawing rectangles is solved. **Text input is not.** The 2025 survey found
that the long-standing gap in
[`winit`'s IME support](https://github.com/rust-windowing/winit/issues/1497)
propagated to most of the Rust ecosystem downstream of it; that
[egui's IME issue](https://github.com/emilk/egui/issues/248) is long-running
and that eframe on native targets still lacks working IME; and that several
libraries either hide the composition window, place it wrongly, or never
activate it at all. The libraries reported as handling IME correctly —
including Japanese input — were Dioxus, fltk, GTK 4, Relm4, GPUI, WinSafe and
Slint.

The consequence for kofun-boot is a rule, not a note:

> **A renderer backend that cannot compose Japanese text, place the candidate
> window correctly, and report its composition state to accessibility is not a
> renderer backend.** It is a demo. IME is a gate in the L9 lane, at the same
> level as "it draws a window", and it is checked before any performance
> number is recorded.

The same applies to accessibility. [AccessKit](https://accesskit.dev) is the
shared answer across Xilem, egui, and Blitz, and it is the reason a native
backend is *possible* at all without reimplementing UIAutomation, NSAccessibility
and AT-SPI. A backend without it is not shippable to anyone who needs a screen
reader, and in several jurisdictions not shippable at all.

## 6. What kofun-boot takes

| from | what |
|---|---|
| Tauri | do not ship a browser; call the one that is installed. And: default-deny capabilities with scopes, as a posture |
| Tauri, inverted | its IPC boundary exists because its frontend is another language. Ours will not be |
| GPUI | a UI can be a GPU program with a handful of primitives; you do not need a general 2D library to be fast |
| Slint | a declarative UI description compiled ahead of time, with swappable renderers behind it, down to microcontroller-class targets |
| Xilem / AccessKit / Parley | the native stack's hard parts (accessibility, text shaping) are shared infrastructure, not per-framework work |
| Lynx | keep the UI thread free; the threading model is a first-class design decision, not an implementation detail |
| boringcactus's survey | IME and accessibility are gates. 94.4% of this field failed on the basics |

## 7. What kofun-boot refuses

- **Shipping a browser engine.** Not Chromium, not Servo-by-default. An
  application's binary should be measured in kilobytes of *our* code.
- **A native renderer that renders HTML/CSS.** The reason is in
  [`RENDER_BACKENDS.md`](RENDER_BACKENDS.md) §3: it is the most expensive
  possible way to get a native renderer, and it is why the leading attempt is
  still pre-alpha.
- **"Experimental" IME.** A backend either composes Japanese correctly under a
  gate, or it is off by default and says so in its own README.
- **Publishing a Tauri comparison we did not run.** The table in §1 is
  attributed to others. The `desktop binary size vs Tauri hello` row in the
  roadmap's bar table stays empty until the L9 gate fills it, on our box, with
  both binaries named.

## Sources

- [Tauri vs Electron 2026 round-up](https://tech-insider.org/tauri-vs-electron-2026/)
- [Electron vs Tauri 2026: bundle, RAM, security](https://www.pkgpulse.com/guides/electron-vs-tauri-2026)
- [Tauri security overview](https://v2.tauri.app/security/) ·
  [capabilities](https://v2.tauri.app/security/capabilities/) ·
  [capability reference](https://v2.tauri.app/reference/acl/capability/) ·
  [permission reference](https://v2.tauri.app/reference/acl/permission/)
- [Tauri security and capabilities system](https://deepwiki.com/tauri-apps/tauri-docs/5.8-security-and-capabilities-system)
- [A 2025 survey of Rust GUI libraries](https://www.boringcactus.com/2025/04/13/2025-survey-of-rust-gui-libraries.html)
- [winit IME support issue](https://github.com/rust-windowing/winit/issues/1497) ·
  [egui IME issue](https://github.com/emilk/egui/issues/248)
- [Slint](https://github.com/slint-ui/slint) ·
  [Xilem](https://github.com/linebender/xilem) ·
  [Blitz](https://github.com/DioxusLabs/blitz)
- [Zed: rendering UI at 120 FPS on the GPU](https://zed.dev/blog/videogame)
- [Lynx vs React Native](https://thenewstack.io/cross-platform-ui-framework-lynx-competes-with-react-native/)
- [AccessKit](https://accesskit.dev)
