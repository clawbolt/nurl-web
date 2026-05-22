# TODOS

## P2 — Unify streaming and normal server paths
- **What:** Replace `ctx_hijack` dual-path with a single `app_run` that handles both normal and streaming connections
- **Why:** Eliminates the architectural split, gives streaming connections keep-alive pipelining
- **Pros:** Simpler mental model, better performance on streaming connections
- **Cons:** Requires `http_server.nu` changes or a new handler contract
- **Context:** Approach C uses a custom accept loop for streaming because `http_server.nu`'s handler is `( @ HttpResponse HttpRequest )` with no TcpConn access. If NURL adds a streaming-aware handler contract, the framework can unify.
- **Effort:** L (human ~3 days) → M with CC
- **Depends on:** NURL `http_server.nu` handler contract change

## P3 — Symlink resolution for static file serving
- **What:** Add `realpath` check in static handler to prevent symlink-based directory traversal
- **Why:** `__has_dotdot_segment` blocks `../` but doesn't catch symlinks pointing outside the static dir
- **Pros:** Closes a known attack vector
- **Cons:** Requires `path_real` or equivalent in NURL stdlib
- **Context:** Finding 8 from CEO review. Chose to document the risk for v1. If NURL adds path resolution, add the check.
- **Effort:** S
- **Depends on:** NURL stdlib `path_real` or equivalent

## P3 — Middleware timing metrics
- **What:** Track per-middleware execution time in Prometheus metrics
- **Why:** Under load, knowing which middleware is slow is critical for debugging
- **Pros:** Observability wins
- **Cons:** Small perf overhead per request
- **Context:** Noted during Section 8 observability review. Deferred for v1.
- **Effort:** S

## P3 — ctx_set_cookie phantom response ordering
- **What:** `ctx_set_cookie` creates a phantom `response_new 200` when called before any response builder. If the handler later calls `ctx_text 404`, the phantom 200 (and its cookie) is freed and lost.
- **Why:** The pending-headers mechanism (D10) was designed to avoid this pattern, but cookies weren't included in it.
- **Workaround:** Call `ctx_set_cookie` *after* the response builder (e.g., after `ctx_text`, `ctx_json_str`).
- **Pros of fix:** Correct behavior regardless of call order
- **Cons of fix:** Adds a pending_cookies Vec to CtxImpl, increases complexity
- **Effort:** M
- **Depends on:** None

## P2 — Streaming accept loop writes to potentially-active conn
- **What:** After `ctx_hijack`, `app_run_streaming` still calls `__write_response` on the conn. For long-lived WebSocket handlers, this could inject garbage HTTP data onto the active connection.
- **Why:** `__dispatch` returns a synthetic 200 for hijacked connections, and the streaming loop writes it to the conn unconditionally.
- **Context:** Safe in practice because NURL's synchronous model means the handler completes before `__write_response` runs. But if a handler spawns a background task or the execution model changes, this becomes a real bug.
- **Workaround:** None currently — this is inherent to the streaming architecture.
- **Effort:** M (requires a way to distinguish hijacked responses, e.g., status 0 sentinel or tagged union)
- **Depends on:** NURL `router_any` handler return type
