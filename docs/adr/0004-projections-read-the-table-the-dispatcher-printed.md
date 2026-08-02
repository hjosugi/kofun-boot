# 4. Projections read the table the dispatcher printed

Date: 2026-08-02 · Status: accepted

## Context

The framework's central promise is that routes, validation, the OpenAPI
document, and the typed client are four projections of one declaration, so
drift between any pair is a build failure rather than a review comment.

The obvious implementation is a Kofun function `boot_openapi(table) -> Text`.
The executable slice refuses it:

```
$ kofun run projection.kofun
error[E2S15]: Core function `method_name` requires Int or concrete enum
              parameters and return
```

`Text` is not a Core return type today. `contracts/boot.kofun` declares
`fn boot_openapi(table: RouteTable) -> Text` and is pinned at that boundary,
which is the honest place for it — but it does not execute, so the promise
cannot rest on it yet.

## Decision

The projection reads the bytes the shell already prints.

`seed/router/shell.kofun` emits the compiled table as its first twelve lines,
because the gate pins it there. `scripts/openapi.sh` consumes exactly those
bytes and emits the document. So the document is generated *from the table the
dispatcher ran*, not from a second declaration that resembles it — which is
the property that matters, and it holds regardless of what language the
generator is written in.

One seam is real and is gated rather than hidden: path *names* live in the
projection, because the slice has no `Text` in a record and the table carries
path codes. The gate therefore requires every code the seed emits to have a
name, so a route added to the table without a name fails the build instead of
appearing in the document as a number.

## Consequences

The promise is kept today, with a generator in shell rather than in Kofun, and
the seam that the constraint forces is the one thing the gate watches hardest.
When `Text` returns land, `boot_openapi` moves into Kofun and the generator
becomes a thin caller; the gate does not change, because it already checks the
property rather than the implementation.

The cost is that the document's shape is specified twice — once in the
canonical contract, once in the generator — until that move happens. The
recorded golden is what keeps them honest in the meantime.
