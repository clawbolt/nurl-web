---
title: "feat: Design the optimal, robustest NURL web framework"
type: feat
status: active
date: 2026-05-23
---

# feat: Redesign nurl_app as an optimal, production-grade web framework

## Overview

Redesign and rewrite `stdlib/ext/nurl_app.nu` from first principles. The current v0 prototype has structural problems — fragile raw-pointer casts, tripled middleware dispatch code, a broken Ctx type-punning scheme, no streaming support, and a confused double-dispatch architecture. This plan produces a framework that is correct under NURL's single-owner memory model, composable without code duplication, and extensible enough to cover the full HTTP stack (WebSocket upgrades, SSE streaming, multipart, HTTP/2) without escape hatches.

## Problem Frame

NURL already has a remarkably complete low-level HTTP stack (~8,100 LOC across 14 stdlib modules): TCP sockets, HTTP/1.1 + HTTP/2 server with keep-alive and pipelining, a router with pattern matching, middleware combinators, static files, auth, multipart, WebSocket, TLS, and Prometheus metrics. But using these raw modules directly requires ~980 lines of boilerplate for a single API server (see `nurlapi/main.nu`), with manual string-comparison dispatch, raw pointer management, and no middleware composition.

The web framework should give developers a FastAPI/Koa-level ergonomics layer that composes correctly with NURL's ownership model, avoids the multi-field-struct-in-Vec stride bug, and exposes the full power of the underlying stack through a unified API surface.

## Requirements Trace

- R1. **Safe Ctx design** — Ctx must use proper NURL structs, not raw `s` pointer punning. Every field must be type-safe and ownership-correct.
- R2. **Single middleware dispatch path** — one shared dispatch function, called from both app-level and group-level routes. Zero code duplication of the middleware chain walk.
- R3. **Correct handler-to-router bridge** — the framework must properly thread `Params` from the router into the `Ctx`, not discard them.
- R4. **Streaming support** — handlers must be able to upgrade to WebSocket or initiate SSE/chunked streaming without escaping the framework.
- R5. **Group composition** — route groups with prefix merging and scoped middleware, nestable, without copying the app's entire middleware chain.
- R6. **Error recovery** — per-request error handling that converts panics/parse-errors into proper 5xx/4xx responses, not worker-thread deaths.
- R7. **Full-stack integration** — one-line opt-in for static files, CORS, logging, metrics, body limits, multipart parsing.
- R8. **NURL-idiomatic memory** — all types follow single-owner + auto-drop. No raw pointer casts, no manual `# s` type punning for user-visible types.
- R9. **Zero runtime/compiler changes** — pure NURL stdlib module, like every other `stdlib/ext/*.nu` file.

## Scope Boundaries

- NOT a template engine, ORM, or session library — those are separate modules
- NOT a replacement for the existing HTTP stack modules — this layers on top
- NOT changing nurlc, runtime.c, or any compiler behavior
- NOT supporting async/await (NURL doesn't have it — thread-per-conn is the model)
- NOT a client-side framework — server only

## Context & Research

### Relevant Code and Patterns

**Existing HTTP stack** (`stdlib/ext/`):
- `http_router.nu` (449 LOC) — Router with `:param`/`*wildcard` patterns, `Params` via `Vec[QueryPair]`, boxed `RouteImpl` to avoid Vec stride bug. This is the routing foundation.
- `http_server.nu` (814 LOC) — Keep-alive server with pipelining, carry buffer, thread pool (`server_run_pool`), panic recovery via `recover`, configurable limits.
- `http_middleware.nu` (258 LOC) — `with_access_log`, `Metrics`, `with_metrics`, Prometheus exposition. Closure-wrapping pattern.
- `http_request.nu` (1045 LOC) — `HttpRequest`, `ParsedHeadOk`, `header_get`, `parse_query`, `parse_form_urlencoded`, `read_body`.
- `http_response.nu` (426 LOC) — `HttpResponse`, `response_text/json/redirect/error`, chunked streaming.
- `http_static.nu` (221 LOC) — `serve_static`, `mime_for_ext`, `__has_dotdot_segment`.
- `http_auth.nu` (337 LOC) — Basic/Bearer auth, cookies.
- `http_multipart.nu` (514 LOC) — `MultipartPart`, `parse_multipart_form`.
- `websocket.nu` (1094 LOC) — RFC 6455 full implementation, `ws_serve_messages`.
- `http2_server.nu` (106 LOC) — ALPN-dispatch wrapper.
- `http_full.nu` (88 LOC) — batteries-included aggregator.

**Key NURL memory constraints** (from `docs/MEMORY.md`):
- Single-owner, deterministic drop. No GC, no RC (except closures).
- `@ T { ... }` struct literal = fresh allocation = owned.
- `: ~ T` mutable capture in closures = pointer capture = escape analysis warns.
- Multi-field structs in `Vec[T]` trigger stride bug on Linux/pthread/clang -O2. Solution: boxed single-pointer handles (`Route { s ctl }` pattern).
- `! T E` Ok arm: multi-field structs must be heap-boxed. Single-field (Vec, raw s) works directly.

**Existing pattern: boxed handle** (from `http_router.nu`):
```
: RouteImpl { String method, String pattern, ( @ HttpResponse HttpRequest Params ) handler }
: Route { s ctl }
```
RouteImpl is heap-allocated via `nurl_alloc`; Route stores a single `s` pointer. `Vec[Route]` is safe because each slot is 8 bytes.

**Existing pattern: middleware as closure wrapping** (from `http_router.nu` + `http_middleware.nu`):
```
( with_access_log inner ) → ( @ HttpResponse HttpRequest )
```
Each middleware takes the inner handler closure and returns a new one. Composition is left-to-right. The framework should use this existing pattern rather than inventing its own.

### Current v0 Bugs and Design Flaws

1. **Ctx stores HttpRequest as raw `s`**: `@ HttpRequest { . ctx req }` casts a borrowed `s` pointer into an HttpRequest. This is a type-punning violation that misleads the borrow checker and risks undefined behavior if the pointer is null or stale.

2. **Triple middleware dispatch**: The same middleware-chain-walk loop appears three times — in `__register_route`, `__group_register`, and `app_run`'s `manual_dispatch`. Any bug fix must be applied three times.

3. **Params not threaded**: `__register_route` receives `Params params` from the router but the `Ctx` is built with a raw `s` pointer for `.params`. The `ctx_param` accessor reconstructs a `Params` from the raw pointer. If the router frees Params after the handler returns (it does), the Ctx holds a dangling pointer.

4. **Double dispatch**: `app_run` wraps `router_handle` in a base handler closure, but `__register_route` also wraps the handler through the router. The request flows through two handler layers unnecessarily.

5. **No WebSocket/SSE path**: The `( @ v Ctx )` handler signature can only produce a single HttpResponse. There's no way to upgrade the connection or stream data.

6. **Static serving ordering**: `__register_static` adds a `/*path` catch-all after user routes, which is correct, but uses `dir_copy` captured by the closure — this is a `: ~` pointer capture that the borrow checker will flag.

7. **ctx_set_header creates phantom responses**: When no response exists yet, `ctx_set_header` creates a `response_new 200` just to hold the header. The status 200 is arbitrary and will be wrong if the handler later calls `ctx_text 404 ...`.

### External References

- FastAPI: decorator-based routing, dependency injection, automatic OpenAPI docs. The key insight is the handler receives a typed request context and returns a typed response.
- Koa: `ctx` object with cascading middleware (onion model). Each middleware calls `await next()` — in NURL's synchronous model, this becomes returning `T` to continue.
- Express: route groups via `Router()` instances with their own middleware stack, mountable at a prefix.
- Go net/http: `Handler` interface with `ServeHTTP(ResponseWriter, *Request)`. The ResponseWriter is a mutable writer, not a value — similar to how Ctx should work.

## Key Technical Decisions

**D1. Ctx is a heap-boxed handle, not an inline struct.**
Rationale: Ctx contains borrowed pointers (req, params) that cannot be moved or copied safely. Making it a single-pointer handle (`Ctx { s ctl }`) avoids the Vec stride bug and matches the established Route/Router pattern. The internal `CtxImpl` lives on the heap.

**D2. Handler signature is `( @ v Ctx )` for normal responses and `( @ HttpResponse HttpRequest Params )` for streaming/upgrades.**
Rationale: Normal handlers write into Ctx. Streaming handlers need direct access to the TcpConn and can't produce a single HttpResponse. Rather than forcing streaming through Ctx, expose it as an escape hatch.

**D3. Single dispatch function `__dispatch`.**
Rationale: The middleware walk + handler call + response extraction is written once and captured by every route registration. No duplication.

**D4. Middleware is a `Vec[s]` of boxed `( @ b Ctx )` closures, not a linked list.**
Rationale: Simpler allocation model. Vec iteration is well-tested in the codebase. The boxed handle pattern avoids stride bugs.

**D5. Group middleware is merged at registration time, not at dispatch time.**
Rationale: When a route is registered on a group, the group's middleware is prepended to the app's middleware and baked into the route's dispatch closure. No per-request group lookups. This matches how Express routers work.

**D6. Ctx does NOT own the request or params — it borrows them.**
Rationale: The server owns the HttpRequest lifecycle. The router owns Params. Ctx borrows both through the boxed `CtxImpl` pointer. This matches the existing handler contract exactly and avoids ownership conflicts.

**D7. Response is stored as an `s` raw pointer (nullable HttpResponse*).**
Rationale: HttpResponse is a multi-field struct. Storing it inline in CtxImpl would make CtxImpl a multi-field struct with a multi-field sub-field — the stride bug. Storing as `s` (pointer) avoids this. The null check (`# i rp == 0`) replaces the `responded` boolean.

**D8. WebSocket upgrade returns from the handler via a special status code.**
Rationale: The handler calls `ctx_upgrade_ws ctx handler` which sets a flag on CtxImpl. After the handler returns, the dispatch code checks the flag and, if set, performs the WebSocket handshake + serve loop using the existing `ws_perform_handshake` + `ws_serve_messages`. This avoids changing the handler signature.

## Open Questions

### Resolved During Planning

- **Q: Should Ctx be generic over response type?** No. NURL doesn't have generics over return types in a useful way. Ctx is a concrete type with a single response slot.
- **Q: Should middleware support post-handler hooks?** Yes, via the Koa onion model: middleware receives both a `Ctx` and a `next` callback. In NURL's synchronous model, the middleware runs before the handler, and the response is available in Ctx after the handler returns. Post-handler logic reads from Ctx after `next` returns. **Revision**: NURL closures can't easily compose as `next()` calls without heap-allocating continuation closures. Simpler: middleware runs before the handler only. Post-handler concerns (logging, metrics) use the existing `with_access_log` / `with_metrics` wrappers on the outer handler, which already see the completed response.

### Deferred to Implementation

- **Exact naming conventions** for public API functions (e.g., `app_get` vs `app.route_get` vs `get`). The framework should follow NURL stdlib's `snake_case_verb_noun` pattern.
- **Whether to provide automatic OpenAPI/schema generation**. Deferred — requires a separate module.
- **TLS integration API**. The framework should pass through to `tcp_listen_tls` when configured, but the exact API shape can be decided during implementation.

## High-Level Technical Design

> *This illustrates the intended approach and is directional guidance for review, not implementation specification. The implementing agent should treat it as context, not code to reproduce.*

### Type hierarchy

```
CtxImpl (heap-allocated)
├── s req             // borrowed HttpRequest pointer
├── s resp            // owned HttpResponse pointer (nullable)
├── s params          // borrowed Params pointer
├── s conn            // borrowed TcpConn (for streaming/upgrade)
├── i body_limit
├── i state           // generic scratch for middleware
├── b ws_upgrade      // WebSocket upgrade requested
└── s ws_handler      // boxed WebSocket message handler

Ctx { s ctl }         // single-pointer handle → CtxImpl

MwEntry { s ctl }     // single-pointer handle → MwEntryImpl
MwEntryImpl
├── ( @ b Ctx ) mw    // the middleware closure

App
├── Router router
├── ( Vec s ) middleware    // Vec of MwEntry handles
├── AppConfig config        // tunables
├── Metrics metrics
├── String static_dir
└── ( Vec s ) on_start / on_stop hooks

GroupImpl
├── App app             // borrowed parent
├── String prefix
└── ( Vec s ) middleware // group-scoped

Group { s ctl }
```

### Single dispatch flow

```
__dispatch(req, params, app_mw, group_mw, handler)
  1. Create CtxImpl on heap (borrows req, params)
  2. Walk app_mw: for each MwEntry, call mw(ctx) → if F, return ctx.resp or 500
  3. Walk group_mw: same
  4. Call handler(ctx) → handler writes response into ctx
  5. If ctx.resp == null → synthesize 500 "no response"
  6. If ctx.ws_upgrade → extract TcpConn from ctx, perform WS handshake, serve
  7. Return ctx.resp (transfer ownership)
  8. Free CtxImpl (does NOT free req/params/resp — those have distinct owners)
```

### Route registration

```
app_get(app, pattern, handler):
  merged_mw = app.middleware  // snapshot at registration time
  router_get(app.router, pattern, \ req params → HttpResponse {
    ^ __dispatch(req, params, merged_mw, empty_vec, handler)
  })

group_get(group, pattern, handler):
  merged_mw = group.middleware ++ app.middleware  // group mw runs after app mw
  full_path = group.prefix + pattern
  router_get(app.router, full_path, \ req params → HttpResponse {
    ^ __dispatch(req, params, app.middleware, group.middleware, handler)
  })
```

### Ctx request accessors

All accessors dereference through the Ctx handle to CtxImpl, then use proper `@ HttpRequest { . impl req }` to reconstruct the borrowed HttpRequest reference. No raw `s` punning — the pointer came from the server, is guaranteed valid for the handler's duration, and the accessor documents the borrow.

### Ctx response builders

Each builder allocates an `HttpResponse`, stores it in `ctx.resp` (freeing any previous one), and sets the appropriate status/headers/body. The `__ctx_set_resp` helper handles the free-then-assign atomically.

### Streaming / SSE / WebSocket

For WebSocket:
```
ctx_upgrade_ws Ctx ctx ( @ ! v WsErr WsMessage ) handler → v
  → sets impl.ws_upgrade = T, impl.ws_handler = handler
```

After dispatch returns, the framework checks `ws_upgrade`. If true, it performs `ws_perform_handshake` + `ws_serve_messages` on the borrowed `TcpConn`, then returns a synthetic 101 response from the handshake.

For SSE / streaming: handlers that need raw streaming use `ctx_stream_begin` which calls `response_begin_chunked` on the TcpConn directly. The handler writes chunks and calls `ctx_stream_end`. The dispatch layer sees that streaming has started and skips the normal `response_serialize + write` path.

## Implementation Units

- [ ] **Unit 1: Ctx type redesign**

**Goal:** Replace the raw-pointer-punning Ctx with a proper heap-boxed handle pattern.

**Requirements:** R1, R8

**Dependencies:** None

**Files:**
- Modify: `stdlib/ext/nurl_app.nu` — replace Ctx struct and all accessors
- Test: `compiler/tests/nurl_app_ctx.nu` (new, unconditional — pure-value tests)

**Approach:**
- Define `CtxImpl` as a heap-allocated struct with properly typed borrowed pointers for `req`, `params`, `conn`
- Define `Ctx { s ctl }` as the single-pointer handle
- All `ctx_*` accessors dereference through `# *CtxImpl . ctx ctl`
- `HttpRequest` is reconstructed via `@ HttpRequest { . impl req_field }` — this is a borrow, not a cast
- Remove the `responded` boolean — null check on `.resp` pointer is sufficient
- Add `conn` field (borrowed TcpConn) for streaming/upgrade support

**Patterns to follow:**
- `Route { s ctl }` / `RouteImpl` from `http_router.nu` — identical boxed-handle pattern
- `Regex { s ctl }` from `regex.nu` — another precedent

**Test scenarios:**
- Create a Ctx, set a text response, verify status and body through Ctx accessors
- Set two responses on the same Ctx — second overwrites first, no leak
- Call ctx_param with a populated Params, get the value back
- Call ctx_body_string on a request with a known body

**Verification:**
- Ctx struct has no raw `s` fields that are later type-punned
- All accessors use `# *CtxImpl` dereference
- No `@ HttpRequest { . ctx req }` style casts

- [ ] **Unit 2: Single dispatch function**

**Goal:** Extract the middleware-walk + handler-call + response-extraction into one reusable `__dispatch` function, eliminating the tripled code.

**Requirements:** R2, R3

**Dependencies:** Unit 1

**Files:**
- Modify: `stdlib/ext/nurl_app.nu` — add `__dispatch`, remove duplicated walk loops

**Approach:**
- `__dispatch` takes `(HttpRequest req, Params params, TcpConn conn, (Vec s) app_mw, (Vec s) group_mw, ( @ v Ctx ) handler) → HttpResponse`
- Creates Ctx from req/params/conn
- Walks app_mw then group_mw — returns the middleware's response if any middleware returns F
- Calls handler(ctx)
- Extracts response from ctx, synthesizes 500 if null
- Returns the owned HttpResponse
- `__register_route` and `__group_register` both call `router_*` with a closure that calls `__dispatch`
- Remove the separate `__app_dispatch` function

**Patterns to follow:**
- `router_handle` from `http_router.nu` — linear scan + first-match + return pattern

**Test scenarios:**
- Dispatch with no middleware, handler returns 200 → response is 200
- Dispatch with one middleware that returns F and sets 401 → response is 401, handler never called
- Dispatch with middleware that returns T, then handler sets 200 → response is 200
- Dispatch with handler that doesn't set a response → fallback 500

**Verification:**
- Grep for middleware-walk loop pattern — should appear exactly once
- `__app_dispatch` function no longer exists

- [ ] **Unit 3: App and Group redesign**

**Goal:** Clean up the App struct (remove unused fields, correct the middleware chain), and make Group compose correctly.

**Requirements:** R5, R7, R8

**Dependencies:** Unit 2

**Files:**
- Modify: `stdlib/ext/nurl_app.nu` — App, Group, config functions

**Approach:**
- App struct uses `AppConfig` sub-struct for tunables (body_limit, idle_timeout, workers) to keep the App fields count manageable
- App.middleware is `Vec[s]` of boxed `MwEntry { s ctl }` handles — identical pattern to the Router's `Vec[Route]`
- `app_use` appends an MwEntry
- `app_get`/etc. call `__register_route` which snapshots the current middleware chain into the dispatch closure
- `app_group` returns a `Group { s ctl }` handle with its own `Vec[s]` middleware
- `group_get`/etc. call `__group_register` which passes both app_mw and group_mw to `__dispatch`
- `app_with_*` config functions remain builder-pattern style (return App for chaining)
- Remove `pretty_errors` flag (not implemented, just a boolean)
- Fix `app_static` to register routes in correct order (before catch-all, after user routes)

**Patterns to follow:**
- `App` builder pattern from the existing code, but with `AppConfig` sub-struct
- Group prefix joining from the existing `__group_path`

**Test scenarios:**
- Create app, register 3 routes, verify `app_count` returns 3
- Create app with middleware, create group with middleware, register group route, verify both middleware run in order
- Create app with `app_static "./public"`, register `/api/health`, verify `/api/health` doesn't hit static handler

**Verification:**
- `App` struct has no raw `s` punning fields
- Group prefix concatenation handles trailing/leading slashes correctly
- Static route is registered after all user routes

- [ ] **Unit 4: Streaming and WebSocket integration**

**Goal:** Add streaming (SSE/chunked) and WebSocket upgrade paths to Ctx and dispatch.

**Requirements:** R4

**Dependencies:** Unit 1, Unit 2

**Files:**
- Modify: `stdlib/ext/nurl_app.nu` — add streaming/WS support to CtxImpl and dispatch
- Test: `compiler/tests/nurl_app_streaming.nu` (gated behind `NURL_NET_TESTS=1`)

**Approach:**
- CtxImpl gets `b streaming_active` and `b ws_upgrade` flags
- `ctx_stream_begin Ctx ctx i status (Vec Header) headers → ! v NetErr` — calls `response_begin_chunked` on the borrowed TcpConn
- `ctx_stream_write Ctx ctx s data → ! v NetErr` — calls `response_write_chunk`
- `ctx_stream_end Ctx ctx → ! v NetErr` — calls `response_end_chunked`
- `ctx_upgrade_ws Ctx ctx ( @ ! v WsErr WsMessage ) handler → v` — sets ws_upgrade flag, stores handler
- After `__dispatch` returns: if ws_upgrade is set, perform handshake + serve loop
- If streaming_active is set, skip normal response serialize+write (streaming already wrote to conn)
- The dispatch function returns a synthetic 200 when streaming/WS took over

**Patterns to follow:**
- `http_response.nu` chunked streaming API — `response_begin_chunked` / `response_write_chunk` / `response_end_chunked`
- `websocket.nu` — `ws_perform_handshake` + `ws_serve_messages`

**Test scenarios:**
- Handler calls `ctx_stream_begin` + `ctx_stream_write` + `ctx_stream_end` — client receives chunked response
- Handler calls `ctx_upgrade_ws` — client establishes WebSocket, sends message, receives echo
- Handler sets normal response (no streaming/WS) — normal HTTP response, no conn upgrade

**Verification:**
- Streaming handler completes without memory leaks
- WebSocket upgrade completes full close handshake
- Non-streaming handlers are unaffected

- [ ] **Unit 5: Configuration, lifecycle, and integration polish**

**Goal:** Wire up all configuration options, lifecycle hooks, and the server startup path correctly.

**Requirements:** R6, R7

**Dependencies:** Unit 3, Unit 4

**Files:**
- Modify: `stdlib/ext/nurl_app.nu` — `app_run`, lifecycle hooks, config
- Modify: `examples/web_app.nu` — update to new API
- Modify: `examples/web_minimal.nu` — update to new API

**Approach:**
- `app_run` builds the final handler closure:
  1. Wraps with `with_access_log` if `app_with_logging` was called
  2. Wraps with `with_metrics` if `app_with_metrics` was called
  3. Wraps with `with_cors_default` if `app_with_cors` was called
  4. Base closure calls `router_handle` which dispatches through `__dispatch` closures
- `app_run` calls `tcp_listen`, creates `HttpServer` with configured timeout/workers, calls `server_run_pool`
- `signal_install_shutdown` wired automatically
- `app_on_start` / `app_on_stop` hooks run before/after the server loop
- Panic recovery is handled by the existing `http_server.nu`'s `recover` in `__serve_keepalive_loop` — no framework-level recovery needed
- Body limit is applied by setting `HttpLimits.body_default_max` on the server (requires `server_new_complete` instead of `server_new_with_timeout`)

**Patterns to follow:**
- `static_server.nu` example — canonical middleware composition order
- `nurlapi/main.nu` — production server setup with workers and config

**Test scenarios:**
- `app_run` with default config starts and responds to requests
- `app_on_start` hook runs before server accepts connections
- Ctrl+C triggers clean shutdown and `app_on_stop` hook runs
- Custom body limit rejects oversized POST with 413
- Custom worker count starts the correct number of threads

**Verification:**
- Server starts, serves requests, and shuts down cleanly
- All `app_with_*` options have a visible effect
- No memory leaks after shutdown

- [ ] **Unit 6: Examples and documentation**

**Goal:** Update examples to exercise the new API and verify ergonomics.

**Requirements:** R1-R9 (all, by demonstration)

**Dependencies:** Unit 5

**Files:**
- Modify: `examples/web_minimal.nu` — minimal 5-route server
- Modify: `examples/web_app.nu` — full demo with groups, auth, streaming, WS
- Create: `examples/web_api.nu` — REST API example with JSON CRUD
- Modify: `README.md` — update API reference

**Approach:**
- `web_minimal.nu` — 3 routes: `/`, `/hello/:name`, POST `/echo`. Under 30 LOC.
- `web_app.nu` — full demo: index page, health, metrics, API group with CRUD, protected admin group with bearer auth, SSE endpoint, WebSocket echo.
- `web_api.nu` — REST API: in-memory `Vec[Json]` store, GET/POST/PUT/DELETE, JSON body parsing, error responses.
- README updated with accurate API surface after implementation.

**Test scenarios:**
- Each example compiles and starts without error
- `web_minimal.nu` responds correctly to curl for all 3 routes
- `web_app.nu` demonstrates middleware, groups, and streaming

**Verification:**
- All 3 examples are under 200 LOC each
- README API reference matches the implemented surface

## System-Wide Impact

- **Interaction graph:** The framework sits entirely above the existing HTTP stack. It imports `http_full.nu` (which aggregates all HTTP modules). No existing module is modified.
- **Error propagation:** Panics in handlers are caught by `http_server.nu`'s `recover` and converted to 500 responses. Parse errors in the request become 4xx from the server layer. The framework's own errors (null response, middleware abort) become 500/401/etc.
- **State lifecycle risks:** Ctx is created per-request, freed after dispatch. No cross-request state leaks. App and Group are created once, freed at program exit. Middleware closures captured by value — no aliasing.
- **API surface parity:** The framework exposes a superset of the router's API (all HTTP methods + groups + middleware). It does not expose every `http_server.nu` knob (e.g., `server_new_with_dos`, `server_new_complete`) — those remain available by dropping down to the raw modules.
- **Integration coverage:** The framework integrates with WebSocket, SSE, multipart, and metrics through Ctx methods, without requiring the user to import those modules separately.

## Risks & Dependencies

- **Multi-field struct stride bug (medium)** — The boxed-handle pattern (Ctx/MwEntry/Group all use `{ s ctl }`) mitigates this. Risk: if any new struct accidentally inlines a multi-field type into a Vec, the bug returns. Mitigation: every collection element type must be a single-pointer handle.
- **Closure capture semantics (low)** — NURL closures capture by value for immutable bindings, by pointer for `: ~` mutable multi-field structs. The dispatch closures capture `app.middleware` (a Vec, single-handle) — safe. Risk: if group middleware Vec is captured and later mutated, the captured copy is stale. Mitigation: middleware is snapshot-captured at registration time, not dispatch time.
- **TcpConn borrow lifetime for streaming (medium)** — The framework borrows TcpConn from the server for streaming/WS. The server expects to close the conn after the handler returns. Risk: streaming writes after dispatch returns would write to a closed socket. Mitigation: streaming must complete inside the handler — the dispatch layer blocks until the handler returns.
- **No existing test infrastructure for nurl_app (low)** — Tests must be added from scratch. Mitigation: the framework's pure-logic parts (Ctx accessors, response builders, middleware walk) can be tested without sockets.

## Sources & References

- **Existing framework prototype:** `stdlib/ext/nurl_app.nu` (947 LOC, v0)
- **HTTP stack:** `stdlib/ext/http_*.nu`, `stdlib/ext/websocket.nu` (~8,100 LOC total)
- **NURL memory model:** `docs/MEMORY.md`
- **NURL gotchas:** `docs/GOTCHAS.md`
- **HTTP server plan:** `HTTP_SERVER_PLAN.md`
- **Grammar:** `spec/grammar_v2.0.ebnf`
- **Route boxed-handle pattern:** `http_router.nu` lines 73-84
- **Middleware closure pattern:** `http_router.nu` lines 310-340, `http_middleware.nu`
