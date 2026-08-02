# Research dossiers

These documents are the survey work behind the lanes in
[`docs/ROADMAP.md`](../ROADMAP.md). They exist because "kofun-boot should be
the best application framework" is not a design — it is a wish until somebody
writes down what the incumbents actually do, which of their decisions are
forced and which are accidents, and which of them Kofun can afford.

## Method, and its limits

Each dossier follows the same rules, which are the repository's rules applied
to prose:

1. **A claim about another project names its source.** Every framework
   assertion carries a link. Where a number appears it is somebody's published
   measurement, attributed, and marked as *theirs* — not ours.
2. **Third-party numbers are never our bars.** A benchmark run on somebody
   else's box, with somebody else's handler, tells us the shape of a
   difference and nothing about ours. The bar table in `docs/ROADMAP.md` stays
   empty until our own gate fills it. A comparison we did not run is a
   hypothesis.
3. **The interesting output is a decision, not a summary.** Each dossier ends
   in *What kofun-boot takes* and *What kofun-boot refuses*, with the reason.
   A survey with no refusals did not look hard enough.
4. **Surveys decay.** Every dossier is stamped with the date it was written.
   The frameworks below ship on their own schedules; a statement about
   somebody's pre-alpha is true for about a quarter.

## The dossiers

| document | question it answers |
|---|---|
| [`WEB_FRAMEWORKS.md`](WEB_FRAMEWORKS.md) | What do the best server frameworks get right, and what is the one declaration everything should derive from? |
| [`DESKTOP_FRAMEWORKS.md`](DESKTOP_FRAMEWORKS.md) | What does a desktop app actually cost, and which costs are the webview's fault? |
| [`RENDER_BACKENDS.md`](RENDER_BACKENDS.md) | Can a webview be replaced by something native and faster — and what does that really require? |
| [`EFFECT_SYSTEMS.md`](EFFECT_SYSTEMS.md) | How do languages that take effects seriously actually handle them, and which of those designs survives a language without higher-kinded types? |

The architecture decisions these dossiers produced live one directory up, in
[`docs/architecture/`](../architecture/).

## Stamp

Written 2026-08-02 against `main` at
`af21d4cbe1fe15154a17a30e6cfd34776f765c31`.
