# Dossier: web frameworks

Written 2026-08-02. Every external claim links its source; every number is
somebody else's measurement, attributed as such.

The question: **what is the one declaration everything else should derive
from, and what does each family of framework pay for getting that wrong?**

## 1. The four families

Server frameworks differ far less in their routing than in *where the truth
about an endpoint lives*. That single choice determines whether the client,
the documentation, the validator, and the dispatcher can drift.

| family | truth lives in | examples | drift risk |
|---|---|---|---|
| Handler-first | the handler body | Express, Gin, Chi, Flask | total: docs and clients are written by hand |
| Annotation-first | decorators over the handler | FastAPI, Spring Boot, NestJS | low for docs, high for clients; reflection at startup |
| Type-first | the endpoint's *type* | [servant](http://www.servant.dev/posts/2018-07-12-servant-dsl-typelevel.html) | none, at the cost of type-level programming |
| Value-first | an endpoint *value* | [tapir](https://github.com/softwaremill/tapir), endpoints, Elysia + [Eden](https://elysiajs.com/eden/treaty/overview) | none, at the cost of a closed description AST |

### Type-first: servant

servant makes the API a type: `"users" :> Capture "id" Int :> Get '[JSON]
User`. Server, client, and docs are then *derived by instance resolution* over
that type. [servant's own explanation of why it is a type-level
DSL](http://www.servant.dev/posts/2018-07-12-servant-dsl-typelevel.html)
argues the payoff is extensibility: a user can add a new combinator and a new
interpreter without touching the library.

The cost is real and well documented: the API description is written in a
language (type-level Haskell) that is not the language the rest of the program
is written in, error messages are proportional to the type's size, and
[re-deriving a term-level view of the routes needs a separate
library](https://discourse.haskell.org/t/servant-routes-converting-servant-apis-to-term-level-representations-of-routes-and-endpoints/9327).

### Value-first: tapir, endpoints, Elysia/Eden

tapir describes an endpoint as [an immutable Scala
value](https://github.com/softwaremill/tapir/blob/v0.7.3/doc/index.md) with
input, error-output, and output parameters, then *interprets* that value as a
server, a client, or OpenAPI. Elysia reaches the same place from the other
direction: routes carry TypeBox schemas, and
[Eden Treaty](https://elysiajs.com/eden/treaty/overview) gives the client the
server's types with, in their words, no code generation and no schema files —
the route definition *is* the contract.

[The endpoints project's own
comparison](https://julienrf.github.io/endpoints/comparison.html) states the
trade-off precisely: in tapir and its relatives the description language is a
sealed AST, so users cannot extend descriptions with application-specific
concerns and interpreters cannot be partial. That is a cost — and for a
framework that wants build-time-total dispatch, it is also exactly the
property we want.

## 2. Speed, and what is actually being measured

Published numbers, all third-party:

- Elysia is reported at [over 500,000 requests per
  second](https://stacknotice.com/blog/elysiajs-bun-complete-guide-2026) in
  its own class of benchmark.
- In TechEmpower-style Rust comparisons, [`may-minihttp` is reported around
  585k req/s and `axum` around 400k
  req/s](https://kerkour.com/rust-fast-techempower-web-framework-benchmarks)
  on the PostgreSQL tests, with may-minihttp's JSON figure roughly double
  axum's.

Two things follow, and only two:

1. **The spread inside "fast" is a factor of about 1.5, not 15.** Framework
   choice among the fast tier is not where an application's latency budget
   goes. This is an argument *against* optimising dispatch past the point
   where it stops showing up, and *for* spending the effort on the things
   benchmarks do not measure: p99 under load, drain-on-deploy, and whether the
   thing is correct.
2. **The differences that do exist are structural.** may-minihttp beats axum
   by doing less per request, not by a cleverer router. Reflection at startup,
   per-request allocation, and dynamic dispatch through a middleware stack are
   the costs. All three are decisions, and all three are avoidable at
   build time.

`framework/http` in the language repository already owns the hard parts of the
serving story — an epoll HTTP/1.1 event loop with stated limits, keep-alive,
slowloris timeouts, bounded per-connection buffers, and drain on `SIGTERM`.
kofun-boot inherits a parser with *stated* limits, which is worth more than a
faster one with unstated limits.

## 3. Middleware: the onion is the problem

Express popularised `(req, res, next)`. Its descendants inherited two defects
that no amount of typing fixes:

- **Order is invisible.** What actually runs for a given route is the
  concatenation of registrations across files, decided at startup.
- **`next()` is an untyped continuation.** Whether a middleware short-circuits,
  mutates the request, or both, is not in its signature.

tower (axum) does fix the typing, at the price of type gymnastics that show up
in every error message. The alternative kofun-boot takes is older and simpler:
cross-cutting behaviour is *function composition in the shell*, written once,
in one place, where it can be read top to bottom. This is already stated in
[`docs/DESIGN.md` §8](../DESIGN.md).

## 4. Server-driven UI: the returning idea

The hypermedia revival is directly relevant, because it is the same
architecture as The Elm Architecture with the update loop moved across a
network:

- **Phoenix LiveView** keeps state on the server and ships diffs. [Dashbit's
  own write-up](https://dashbit.co/blog/latency-rendering-liveview) is candid
  that every event round-trips, that this is snappy for forms and business
  logic, and too slow for games.
- **htmx** swaps fragments; **Datastar** uses SSE and morph-swap by default
  [rather than htmx's `innerHTML`
  swap](https://www.jeffhui.net/writings/2025/datastar/).
- Reported migrations of CRUD-heavy SPAs cite [40–60% less frontend
  code](https://pockit.tools/blog/htmx-vs-react-2026-when-you-dont-need-spa/)
  against more server render load and higher interaction latency.

The lesson for kofun-boot is not "pick hypermedia". It is that **the same
`update : Msg -> Model -> (Model, Cmd Msg)` can be interpreted in three
places** — in the browser, on the server with diffs on the wire, or in a
native window — if and only if the view is a data structure rather than a
string of HTML. That is the hinge the whole framework turns on, and it is
argued in [`docs/architecture/TEA.md`](../architecture/TEA.md).

## 5. Batteries: what "boot" has to mean

Spring Boot, Rails, and Phoenix win adoption on the first hour, not the first
benchmark. The concrete inventory a developer expects:

scaffold · watch-reload · migrations · a typed client · OpenAPI · structured
logging with request correlation · health and readiness endpoints · graceful
drain · config with printed effective values · a test kit with fakes for every
capability · a benchmark you can run yourself.

Two of those deserve emphasis because frameworks routinely get them wrong:

- **Config must print what it resolved.** A framework that silently binds
  `0.0.0.0`, or silently picks a timezone, has made a security decision on the
  operator's behalf. `docs/DESIGN.md` §8 already refuses this; the config
  surface should *print the effective record at startup* and the gate should
  read it.
- **The test kit is the product.** Because every dependency is a value, the
  fakes are not a testing add-on — they are the same records the shell builds,
  with different fields. This is the single largest DX advantage the
  capability design buys, and it should be re-exported as a first-class
  package rather than left for applications to rediscover.

## 6. What kofun-boot takes

| from | what |
|---|---|
| tapir / Eden | endpoint-as-**value**, interpreted four ways; drift is a build failure |
| servant | the *ambition* of derivation — but at the value level, not the type level |
| Elysia | dispatch decided at build time; no reflection on the request path |
| `framework/http` | the event loop, its stated limits, and its drain semantics |
| FastAPI | documentation as a projection of the same declaration, never hand-written |
| LiveView | `update` is transport-independent; the view is data, so the wire can carry diffs |
| Rails / Spring Initializr | the first hour matters: `boot new` must emit code that already has the core/shell split |

## 7. What kofun-boot refuses

- **Type-level route DSLs.** Kofun's type system does not have the machinery,
  and even where it exists the error messages are a tax on every user to buy
  extensibility that a sealed AST plus a new interpreter also provides.
- **The middleware onion.** Composition in the shell, visible in one place.
- **Reflection anywhere on the request path.** Everything derived is derived at
  build time; this is what makes the dispatch table a fixed comparison rank.
- **Publishing a comparison we did not run.** The numbers in §2 are other
  people's. Ours go in the roadmap's bar table when the L5 gate produces them,
  on our box, with the handler named.

## Sources

- [servant: why a type-level DSL](http://www.servant.dev/posts/2018-07-12-servant-dsl-typelevel.html)
- [servant-routes announcement](https://discourse.haskell.org/t/servant-routes-converting-servant-apis-to-term-level-representations-of-routes-and-endpoints/9327)
- [tapir documentation](https://github.com/softwaremill/tapir/blob/v0.7.3/doc/index.md)
- [endpoints: comparison with similar tools](https://julienrf.github.io/endpoints/comparison.html)
- [Eden Treaty overview](https://elysiajs.com/eden/treaty/overview)
- [Elysia + Bun guide, 2026](https://stacknotice.com/blog/elysiajs-bun-complete-guide-2026)
- [Why Rust is fast in TechEmpower](https://kerkour.com/rust-fast-techempower-web-framework-benchmarks)
- [TechEmpower Framework Benchmarks](https://www.techempower.com/benchmarks/)
- [Latency and rendering optimizations in Phoenix LiveView](https://dashbit.co/blog/latency-rendering-liveview)
- [Datastar basics](https://www.jeffhui.net/writings/2025/datastar/)
- [htmx in 2026](https://pockit.tools/blog/htmx-vs-react-2026-when-you-dont-need-spa/)
