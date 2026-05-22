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
