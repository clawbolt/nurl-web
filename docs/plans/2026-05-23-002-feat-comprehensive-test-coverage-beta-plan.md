---
title: "feat: Comprehensive test coverage for nurl_app.nu"
type: feat
status: active
date: 2026-05-23
deepened: 2026-05-23
origin: docs/plans/2026-05-23-001-feat-optimal-web-framework-beta-plan.md
---

# feat: Comprehensive test coverage for nurl_app.nu

## Overview

Build a complete test suite for the `nurl_app.nu` web framework. There is currently zero test coverage — no test files, no test runner, no assertion helpers. This plan creates the testing infrastructure and covers every public API surface, internal helper, edge case, and error path in the framework.

## Problem Frame

The framework has 67+ functions spanning 1041 LOC, touching memory management (boxed-handle pattern, heap allocation, borrowed pointers), HTTP parsing, routing, middleware composition, response building, streaming, and WebSocket upgrades. Every function is hand-written NURL without compiler-enforced type safety for the boxed-handle indirection. Without tests, any refactoring or bug fix risks introducing regressions that won't be caught until runtime.

The existing plan (see origin) defines the test contract: `@ test_<name> → i` returning 0 for pass / 1 for fail, with a `test.sh` runner and `NURL_NET_TESTS=1` gate for socket-dependent tests. This plan builds on that contract.

## Requirements Trace

- R1. Every public API function has at least one positive test case
- R2. Every public API function has edge-case and error-path coverage
- R3. Internal helpers (`__dispatch`, `__walk_mw`, `__ctx_new`/`__ctx_free`, `__search_pair`, `__group_path`, `__body_to_string`, `__register_static`, `__register_health`, `__prepare_run`, `__run_hooks`, `__ctx_set_resp`, `__write_response`, `__print_banner`) have direct test coverage
- R4. Memory safety: no leaks on any exit path (normal, middleware abort, no-response, hijack)
- R5. Integration tests: end-to-end request→response through `app_run` and `app_run_streaming`
- R6. Test runner with gating: pure-logic tests always run, network tests behind `NURL_NET_TESTS=1`

## Scope Boundaries

- NOT testing the underlying HTTP stack modules (`http_router.nu`, `http_server.nu`, etc.) — those are separate modules with their own tests
- NOT testing NURL compiler or runtime behavior
- NOT testing TLS, HTTP/2, or multipart — those depend on external infrastructure beyond `NURL_NET_TESTS`
- NOT changing any production code in `nurl_app.nu` — tests only
- NOT creating a mock HTTP server — integration tests use real TCP connections when `NURL_NET_TESTS=1`

## Context & Research

### Relevant Code and Patterns

**Test contract** (from origin plan): `@ test_<name> → i` returning 0/1. Test runner via shell script.

**Assertion pattern**: NURL has no built-in assertion library. Tests will use manual comparison + print:
```
? != 0 ( nurl_str_eq result expected ) {
    ( nurl_print `PASS: test_name\n` )
    ^ 0
} {
    ( nurl_print `FAIL: test_name\n` )
    ^ 1
}
```

**Testable surface classification:**

| Category | Functions | Network Required? |
|---|---|---|
| Ctx construction/lifecycle | `__ctx_new`, `__ctx_free` | No |
| Ctx request accessors | `ctx_method`, `ctx_path`, `ctx_query_string`, `ctx_header`, `ctx_param`, `ctx_body_string`, `ctx_body_json`, `ctx_query_get`, `ctx_form_get`, `ctx_cookie`, `ctx_bearer`, `ctx_basic_auth` | No |
| Ctx response builders | `ctx_text`, `ctx_html`, `ctx_json_str`, `ctx_json`, `ctx_redirect`, `ctx_status`, `ctx_set_header`, `ctx_set_cookie`, `ctx_respond`, `__ctx_set_resp` | No |
| Internal helpers | `__body_to_string`, `__search_pair`, `__group_path`, `__walk_mw` | No |
| App lifecycle | `app_new`, `app_free`, `app_with_*`, `app_static`, `app_count`, `app_use`, `app_on_start`, `app_on_stop` | No |
| Route registration | `__register_route`, `app_get/post/put/patch/delete`, `__group_register`, `group_get/post/put/patch/delete`, `app_group` | No |
| Middleware | `__walk_mw`, `__dispatch` | No |
| Static serving | `__register_static` | No (can mock) |
| Streaming | `ctx_hijack`, `ctx_stream_begin/write/end`, `ctx_upgrade_ws` | Yes |
| Server entry | `app_run`, `app_run_streaming` | Yes |
| Internal helpers | `__register_health`, `__prepare_run`, `__run_hooks`, `__print_banner`, `__write_response` | Partial |

### Institutional Learnings

- nurl-heap-cleanup-required (confidence 9): explicit free on all exit paths — tests must verify no leaks
- nurl-boxed-handle-pattern (confidence 9): all handle types use `{ s ctl }` — tests validate the pattern holds

## Key Technical Decisions

**D1. Test files organized by surface, not by function.**
Rationale: Grouping by surface area (ctx_accessors, ctx_response, app_lifecycle, etc.) keeps test files manageable (50-150 LOC each) while making coverage gaps visible by file. One mega-file would be hard to maintain.

**D2. Assertion helper function.**
Rationale: Repeating the comparison + print pattern 200+ times is noisy. A `__assert_eq_s` / `__assert_eq_i` / `__assert_eq_b` helper reduces each assertion to one line and standardizes PASS/FAIL output.

**D3. HttpRequest construction helpers.**
Rationale: Most tests need an `HttpRequest` to create a `Ctx`. Building one manually requires ~15 lines of struct initialization. A `__make_test_request` helper creates a minimal valid request with configurable method/path/query/headers/body.

**D4. Tests are pure NURL files compiled and run individually.**
Rationale: No test framework dependency. Each test file is a standalone NURL program that imports `nurl_app.nu` and returns 0 or 1. The test runner script compiles and runs each file, collecting pass/fail.

**D5. Network tests behind NURL_NET_TESTS=1 environment gate.**
Rationale: CI environments may not have network access. Pure-logic tests run everywhere. Network tests (streaming, WebSocket, app_run) only run when explicitly enabled.

**D6. No mock framework — use real Ctx/App construction.**
Rationale: NURL has no reflection, no trait system, and no mock libraries. Tests construct real `Ctx` and `App` objects and exercise them directly. This is more honest than mocking and catches real integration issues.

**D7. External type construction via raw struct initialization.**
Rationale: `HttpRequest`, `Params`, `HttpResponse`, `HeaderPair`, `QueryPair`, and `BasicAuth` are all defined in NURL stdlib modules outside this repo (`http_request.nu`, `http_router.nu`, `http_response.nu`, `http_auth.nu`). Test helpers must construct these types using NURL struct literal syntax (`@ HttpRequest { ... }`), which requires knowing the exact field layout. Since `nurl_app.nu` already imports `http_full.nu` (which aggregates all HTTP modules), the types are available at compile time. The test helpers document the assumed layout and will break if upstream changes the struct shapes — this is an accepted coupling, identical to how the production code depends on these types. If the NURL stdlib adds factory functions (e.g., `request_new`), the helpers should migrate to those.

**D8. HttpResponse verification via existing accessors, not field access.**
Rationale: Tests need to verify response status and headers. Rather than reaching into `HttpResponse` internal fields (which would couple tests to the struct layout), tests should use existing response accessor functions from `http_response.nu` (e.g., status code accessor, header accessor) where available. If no accessor exists for a needed field, the test helper accesses the response struct field directly (e.g., `. r status`), documented as a fragile coupling point. The implementing agent should check what accessors `http_response.nu` provides before choosing the approach. This keeps tests honest about what the public response API exposes.

## Open Questions

### Resolved During Planning

- **Q: Should tests modify `nurl_app.nu`?** No. Tests are separate files. If `nurl_app.nu` needs internal exposure for testing, the `__` prefixed functions are already part of the module's public surface (NURL has no visibility control).
- **Q: Single test file or multiple?** Multiple, organized by surface area. Keeps each file under 200 LOC.
- **Q: How to test `__ctx_free` doesn't leak?** Can't test directly without a memory profiler. Instead, test that calling `__ctx_free` after setting a response doesn't crash, and test that double-free is avoided. Relies on valgrind/ASAN for actual leak detection — note this in the plan.

### Deferred to Implementation

- **Exact assertion helper names and signatures** — the implementing agent decides based on what's most ergonomic
- **Whether to add a test summary counter** (total/pass/fail) to the runner script — nice to have, not blocking

## Implementation Units

- [ ] **Unit 1: Test infrastructure**

**Goal:** Create the test runner script, assertion helpers, and HttpRequest construction utilities that all other test files depend on.

**Requirements:** R6

**Dependencies:** None

**Files:**
- Create: `test/test.sh` — runner script
- Create: `test/test_helpers.nu` — assertion and construction helpers

**Approach:**
- `test.sh`: iterates over `test/test_*.nu` files, compiles each with `nurlc` (or `./nurl.sh`), runs the binary, collects exit code. Prints pass/fail per file. Skips network tests unless `NURL_NET_TESTS=1` is set (network test files are prefixed `test_net_*`).
- `test_helpers.nu`:
  - `__assert_eq_i i got i want s label → i` — returns 0 if equal, prints PASS/FAIL
  - `__assert_eq_s s got s want s label → i` — string comparison via `nurl_str_eq`
  - `__assert_eq_b b got b want s label → i` — boolean comparison
  - `__assert_true b val s label → i` — shorthand for asserting true
  - `__assert_false b val s label → i` — shorthand for asserting false
  - `__make_test_request s method s path s query → HttpRequest` — builds a minimal HttpRequest with the given method/path/query, empty headers (`vec_new [HeaderPair]`), empty body (`vec_new [u]`). Uses `@ HttpRequest { method path query headers body }` struct literal. Assumes the HttpRequest layout is `{ String method, String path, String query, Vec[HeaderPair] headers, Vec[u] body }` as used in `http_request.nu`. Will break if upstream changes the layout — this coupling is accepted (see D7).
  - `__make_request_with_body s method s path s query s body_content -> HttpRequest` -- same but with body. Converts body_content string to Vec[u] by iterating characters and pushing to a Vec.
  - `__make_request_with_header s method s path s query s header_name s header_value -> HttpRequest` -- same but with one HeaderPair in the headers Vec. Uses HeaderPair struct literal.
  - `__make_params -> Params` -- builds an empty Params. `__add_param Params p s key s value -> v` adds a QueryPair. Assumes Params layout matches http_router.nu (see D7).

**Test scenarios:**
- `test.sh` discovers and runs 0 test files without error
- `test.sh` skips `test_net_*` files when `NURL_NET_TESTS` is unset
- `test_helpers.nu` compiles without errors

**Verification:**
- `test.sh` runs successfully (exits 0 when all tests pass)
- Each assertion helper returns correct 0/1

- [ ] **Unit 2: Ctx lifecycle tests**

**Goal:** Cover `__ctx_new` and `__ctx_free` — construction, field initialization, cleanup with and without a response set.

**Requirements:** R1, R2, R4

**Dependencies:** Unit 1

**Files:**
- Create: `test/test_ctx_lifecycle.nu`

**Approach:**
- Test `__ctx_new` creates a valid Ctx with all fields initialized correctly (null resp, null pending_headers, hijacked=false)
- Test `__ctx_free` on a fresh Ctx (no response) — no crash
- Test `__ctx_free` after setting a response via `ctx_text` — no crash, response is freed
- Test `__ctx_free` after setting pending headers (no response) — no crash, Vec is freed
- Test `__ctx_free` after both response and pending headers — no crash

**Test scenarios:**
- Create Ctx, verify `.impl.resp == 0` (null response)
- Create Ctx, call `ctx_text ctx 200 "hello"`, verify `.impl.resp != 0`
- Create Ctx, call `ctx_set_header` (pending), verify `.impl.pending_headers != 0`
- Create Ctx, set header + set response, verify pending headers applied and cleared
- Create Ctx, free immediately — no crash
- Create Ctx, set response, free — no crash

**Verification:**
- All 6+ test functions return 0

- [ ] **Unit 3: Ctx request accessor tests**

**Goal:** Cover all 12 request accessors: `ctx_method`, `ctx_path`, `ctx_query_string`, `ctx_header`, `ctx_param`, `ctx_body_string`, `ctx_body_json`, `ctx_query_get`, `ctx_form_get`, `ctx_cookie`, `ctx_bearer`, `ctx_basic_auth`.

**Requirements:** R1, R2

**Dependencies:** Unit 1

**Files:**
- Create: `test/test_ctx_accessors.nu`

**Approach:**
- For each accessor, build a Ctx with a known HttpRequest state, call the accessor, verify the result
- `ctx_method`: test GET, POST, custom methods
- `ctx_path`: test `/`, `/hello`, `/api/items/123`
- `ctx_query_string`: test empty query, `?q=search`, `?a=1&b=2`
- `ctx_header`: test present header, absent header, case-sensitive lookup
- `ctx_param`: test present param, absent param, multiple params
- `ctx_body_string`: test empty body, short body, body with special characters
- `ctx_body_json`: test valid JSON, invalid JSON, empty body
- `ctx_query_get`: test present key, absent key, multiple keys with same name
- `ctx_form_get`: test with correct Content-Type, wrong Content-Type, missing Content-Type
- `ctx_cookie`: test present cookie, absent cookie, multiple cookies
- `ctx_bearer`: test valid Bearer token, missing Authorization, non-Bearer scheme
- `ctx_basic_auth`: test valid Basic auth, missing Authorization

**Test scenarios (per accessor):**
- Happy path: known input → expected output
- Empty/missing case: no data → null/empty result
- Edge case: special characters, long values, Unicode (if applicable)

**Verification:**
- All 12 accessors have at least 2 test cases each (happy + edge)
- Total test functions: 25+

- [ ] **Unit 4: Ctx response builder tests**

**Goal:** Cover all 9 response builders: `ctx_text`, `ctx_html`, `ctx_json_str`, `ctx_json`, `ctx_redirect`, `ctx_status`, `ctx_set_header`, `ctx_set_cookie`, `ctx_respond`, plus the internal `__ctx_set_resp`.

**Requirements:** R1, R2, R4

**Dependencies:** Unit 1

**Files:**
- Create: `test/test_ctx_response.nu`

**Approach:**
- Each builder: set response on a fresh Ctx, extract via `ctx_respond`, verify status code and body
- `__ctx_set_resp`: test that calling twice frees the old response (second call overwrites)
- `ctx_set_header`: test before response (pending), after response (direct), multiple headers
- `ctx_set_cookie`: test with and without existing response (note the phantom-response behavior documented in TODOS.md)
- `ctx_respond`: test when response exists (returns it), when no response (returns 204)

**Test scenarios:**
- `ctx_text` with status 200 → response has status 200, body matches
- `ctx_html` with status 200 → response has Content-Type `text/html`
- `ctx_json_str` with status 201 → response has Content-Type `application/json`
- `ctx_json` with a Json value → response has JSON body
- `ctx_redirect` with 302 → response has Location header
- `ctx_status` with 204 → response has status 204, no body
- `ctx_set_header` before response → pending_headers has 1 entry
- `ctx_set_header` after response → response has the header
- `ctx_set_header` before + after → both applied
- `ctx_set_cookie` after response → response has Set-Cookie
- `ctx_respond` when response set → returns owned response, ctx.resp becomes null
- `ctx_respond` when no response → returns 204 fallback
- Overwrite: call `ctx_text 200 "a"` then `ctx_text 404 "b"` → status is 404, body is "b"
- Pending headers applied: `ctx_set_header` then `ctx_text` → response has the header

**Verification:**
- 14+ test functions, all return 0

- [ ] **Unit 5: Internal helper tests**

**Goal:** Cover `__body_to_string`, `__search_pair`, `__group_path`, `__walk_mw`.

**Requirements:** R3

**Dependencies:** Unit 1

**Files:**
- Create: `test/test_helpers_internal.nu`

**Approach:**

**`__body_to_string`:**
- Empty body (Vec length 0) → returns empty String
- Body with ASCII content → returns matching String
- Body with single character → returns single-char String

**`__search_pair`:**
- Empty Vec → returns null (F)
- Vec with matching key → returns owned copy of value
- Vec with non-matching key → returns null (F)
- Vec with multiple entries, key in middle → returns correct value

**`__group_path` (critical — v0 had a bug here):**
- Prefix `/api` + pattern `ping` → `/api/ping` (no double slash, no missing slash)
- Prefix `/api/` + pattern `ping` → `/api/ping` (trailing slash on prefix)
- Prefix `/api` + pattern `/ping` → `/api/ping` (leading slash on pattern)
- Prefix `/api/` + pattern `/ping` → `/api/ping` (both have slashes)
- Prefix `/` + pattern `/` → `/`
- Prefix `/` + pattern `health` → `/health`
- Empty prefix `""` + pattern `/test` → `/test`

**`__walk_mw`:**
- Empty middleware list → returns T
- Single middleware returning T → returns T
- Single middleware returning F → returns F
- Multiple middleware, all T → returns T
- Multiple middleware, first F → returns F, remaining not called (verify via side effect)
- Middleware that sets a response on ctx → ctx.resp is set after walk

**Test scenarios:**
- 4 functions × 3-7 cases each = 15+ test functions

**Verification:**
- All 4 internal helpers have direct test coverage
- `__group_path` covers all 4 slash combinations explicitly

- [ ] **Unit 6: App lifecycle tests**

**Goal:** Cover `app_new`, `app_free`, all `app_with_*` config functions, `app_static`, `app_count`, `app_use`, `app_on_start`, `app_on_stop`.

**Requirements:** R1, R2

**Dependencies:** Unit 1

**Files:**
- Create: `test/test_app_lifecycle.nu`

**Approach:**
- `app_new` → verify all fields have expected defaults (router initialized, no middleware, flags false, body_limit 0, workers 0)
- `app_free` → no crash (smoke test)
- Each `app_with_*` → verify the corresponding field is set
- `app_static` → verify `static_dir` is set to the given path
- `app_count` → starts at 0, increments with each route registration
- `app_use` → adds to mw_chain (verify vec_len increases)
- `app_on_start`/`app_on_stop` → verify hooks are registered
- Config chaining: `app_with_cors ( app_with_logging ( app_new ) )` → both flags set

**Test scenarios:**
- `app_new` → default config values
- `app_free` after `app_new` → no crash
- `app_with_cors` → use_cors == T
- `app_with_logging` → use_logging == T
- `app_with_metrics` → use_metrics == T
- `app_with_body_limit 5242880` → body_limit == 5242880
- `app_with_idle_timeout 5000` → idle_timeout_ms == 5000
- `app_with_workers 4` → workers == 4
- `app_static "./public"` → static_dir contains the path
- `app_count` after 3 `app_get` calls → returns 3
- `app_use` × 2 → vec_len(mw_chain) == 2
- Config chaining → multiple flags set in one expression

**Verification:**
- 12+ test functions

- [ ] **Unit 7: Route registration tests**

**Goal:** Cover `app_get/post/put/patch/delete`, `app_group`, `group_get/post/put/patch/delete`, `group_use`, `__register_route`, `__group_register`.

**Requirements:** R1, R2, R5

**Dependencies:** Unit 1, Unit 6

**Files:**
- Create: `test/test_routes.nu`

**Approach:**
- Register routes with different HTTP methods → verify router has them (via `app_count`)
- Verify `__register_route` correctly snapshots middleware at registration time
- Register routes on a group → verify full path is correct (relies on `__group_path`)
- Register group with middleware → verify group middleware is separate from app middleware
- Nested groups (if supported) → verify prefix composition
- Register duplicate routes → verify behavior (last-write-wins or error)
- Register route with `:param` pattern → verify param extraction works through dispatch

**Test scenarios:**
- `app_get app "/" handler` → app_count == 1
- `app_post app "/data" handler` → app_count == 2
- All 5 HTTP methods registered → app_count == 5
- `app_group app "/api"` → returns valid Group
- `group_get api "/ping" handler` → app_count incremented
- Group with middleware: `group_use g mw` then `group_get` → middleware captured
- Multiple groups on same app → independent middleware chains
- Route with `:name` param → dispatch with matching path extracts param
- Middleware snapshot: register app middleware, then `app_get`, then add more middleware, then `app_get` — first route only has the initial middleware, second route has both

**Verification:**
- 8+ test functions
- Route count verification through `app_count`

- [ ] **Unit 8: Middleware and dispatch tests**

**Goal:** Cover `__walk_mw`, `__dispatch` comprehensively — the core request processing pipeline.

**Requirements:** R1, R2, R3, R4

**Dependencies:** Unit 1, Unit 2

**Files:**
- Create: `test/test_dispatch.nu`

**Approach:**
- `__dispatch` is the heart of the framework. Test it by constructing a minimal HttpRequest, calling `__dispatch` directly with various middleware/handler combinations, and verifying the returned HttpResponse.

**Test scenarios:**

*Basic dispatch:*
- No middleware, handler sets 200 → response is 200
- No middleware, handler sets 404 → response is 404
- No middleware, handler doesn't set response → returns 500 "handler did not produce a response"

*Middleware:*
- One middleware returning T → handler runs, response is handler's
- One middleware returning F + setting 401 → response is 401, handler not called
- Two middleware, both T → handler runs
- Two middleware, first T, second F → second's response, handler not called
- Middleware that doesn't set response but returns F → dispatch returns the middleware's response or synthesizes one

*Body limit:*
- Body within limit → handler runs normally
- Body exceeding limit → returns 413 without calling handler

*Params:*
- Dispatch with params → handler can access params via `ctx_param`
- Dispatch with empty params → `ctx_param` returns null

*Null request:*
- Dispatch with null request → returns 500 immediately

*Hijack:*
- Handler calls `ctx_hijack` (on a ctx with conn set) → returns synthetic 200, hijacked flag is set

*Request ID:*
- Consecutive dispatches → request_id increments

*Middleware abort with pending headers:*
- Middleware sets header + returns F + sets response → response has the header

**Verification:**
- 12+ test functions covering all dispatch paths
- Every exit path through `__dispatch` is exercised

- [ ] **Unit 9: Static serving tests**

**Goal:** Cover `__register_static` and the static file handler logic.

**Requirements:** R1, R2

**Dependencies:** Unit 1, Unit 6

**Files:**
- Create: `test/test_static.nu`

**Approach:**
- Test `__register_static` registers a `/*path` route when `static_dir` is set
- Test `__register_static` is a no-op when `static_dir` is empty
- Test path traversal rejection: `../etc/passwd` → 403
- Test normal file serving: known file → 200 with correct MIME type
- Test missing file → 404
- Test directory index: request for `/` when `index.html` exists → 200

**Test scenarios:**
- `app_static app "/nonexistent"` → route registered
- No `app_static` → no extra route registered
- `__has_dotdot_segment` with `../passwd` → true (blocked)
- `__has_dotdot_segment` with `foo/bar` → false (allowed)
- `__has_dotdot_segment` with `foo/..bar` → false (not traversal)
- Static handler with existing file → 200
- Static handler with missing file → 404

**Verification:**
- 6+ test functions

- [ ] **Unit 10: Health and hooks tests**

**Goal:** Cover `__register_health`, `__run_hooks`, `__prepare_run`, `app_on_start`, `app_on_stop`.

**Requirements:** R1, R3

**Dependencies:** Unit 1, Unit 6

**Files:**
- Create: `test/test_hooks.nu`

**Approach:**
- `__register_health` with `use_metrics = T` → `/health` route exists (app_count incremented)
- `__register_health` with `use_metrics = F` → no route added
- `__run_hooks` with empty Vec → no crash
- `__run_hooks` with 2 hooks → both execute (verify via side effect counter)
- `app_on_start` → hook appears in `on_start_hooks`
- `app_on_stop` → hook appears in `on_stop_hooks`
- `__prepare_run` → resolves config defaults (idle_timeout 30000, workers 16), calls `__register_static`, `__register_health`, `__run_hooks` for on_start
- `__print_banner` -- smoke test: call with known app config, verify it does not crash (output goes to stdout, hard to capture without subprocess; test just ensures no panic)
- `__write_response` -- construct HttpResponse + TcpConn pair, write response, verify bytes written. Only feasible with `NURL_NET_TESTS=1`; unit-level test is a no-crash smoke test with a mock conn.

**Test scenarios:**
- Health route registered when metrics on
- Health route not registered when metrics off
- Hooks run in registration order
- `__prepare_run` sets defaults on app with 0 values
- `__prepare_run` preserves non-zero values

**Verification:**
- 7+ test functions (including __print_banner smoke and __write_response smoke)

- [ ] **Unit 11: Integration tests (network-gated)**

**Goal:** End-to-end tests that start a server, send real HTTP requests, and verify responses. Gated behind `NURL_NET_TESTS=1`.

**Requirements:** R5

**Dependencies:** Unit 1 through Unit 8

**Files:**
- Create: `test/test_net_basic.nu` — basic request/response through `app_run`
- Create: `test/test_net_groups.nu` — route groups, group middleware
- Create: `test/test_net_middleware.nu` — middleware chain behavior over HTTP

**Approach:**
- Each test: build an App, register routes, start server on a random high port in a thread, send HTTP request via TCP, verify response, shut down.
- Tests check exit code and stderr output for expected behavior.
- These tests are compiled and run separately, gated by `NURL_NET_TESTS=1` in `test.sh`.

**Test scenarios:**

*Basic server:*
- GET `/` → 200 with expected body
- GET `/hello/:name` with "world" → 200 with "hello world"
- POST `/echo` with body → 200 with echoed body
- GET `/nonexistent` → 404 (from router)

*Groups:*
- GET `/api/ping` → 200
- GET `/api/items?q=test` → 200 with query in response
- GET `/api/secret` without auth → 401
- GET `/api/secret` with Bearer token → 200

*Middleware:*
- CORS: OPTIONS `/` → 200 with CORS headers
- Logging: request produces log output on stderr
- Body limit: POST with oversized body → 413

*Graceful shutdown:*
- on_start hook ran (check stderr)
- Signal handling → clean shutdown message

**Verification:**
- 10+ test functions
- All gated behind `NURL_NET_TESTS=1`
- Tests can run against both `app_run` and `app_run_streaming`

- [ ] **Unit 12: Streaming and WebSocket tests (network-gated)**

**Goal:** Cover `ctx_hijack`, `ctx_stream_begin/write/end`, `ctx_upgrade_ws`, `app_run_streaming`, `__write_response`.

**Requirements:** R5

**Dependencies:** Unit 1, Unit 2, Unit 8

**Files:**
- Create: `test/test_net_streaming.nu`
- Create: `test/test_net_websocket.nu`

**Approach:**
- Test `ctx_hijack` on streaming server → returns TcpConn
- Test `ctx_hijack` on normal server → abort/error (if detectable)
- Test SSE streaming: connect, receive multiple events, close
- Test WebSocket: connect, send message, receive echo, close
- Test `__write_response` directly: write a response to a TcpConn, read it back

**Test scenarios:**

*SSE streaming:*
- `ctx_stream_begin` + 3 × `ctx_stream_write` + `ctx_stream_end` → client receives 3 SSE events
- Stream with custom headers → headers present in response
- Stream error: client disconnects mid-stream → no crash

*WebSocket:*
- `ctx_upgrade_ws` with echo handler → send "hello", receive "hello" back
- WS close handshake → clean close
- WS invalid handshake → connection closed with error

*Non-streaming on streaming server:*
- Normal handler (no hijack) on `app_run_streaming` → normal HTTP response

**Verification:**
- 8+ test functions
- All gated behind `NURL_NET_TESTS=1`

## System-Wide Impact

- **Interaction graph:** Tests are separate from production code. They import `nurl_app.nu` and exercise its public + internal API. No production code changes.
- **CI integration:** `test.sh` returns non-zero if any test fails. Can be integrated into any CI pipeline.
- **Memory safety:** Tests exercise `__ctx_free` on all paths but cannot prove absence of leaks without valgrind/ASAN. Recommend running under memory sanitizer periodically.

## Risks & Dependencies

- **HttpRequest construction complexity (medium)** — Building a valid `HttpRequest` for testing requires understanding its internal layout (method/path/query are `String`, headers are `Vec[HeaderPair]`, body is `Vec[u]`). If the layout changes across NURL versions, test helpers break. Mitigation: helpers centralize construction; only `test_helpers.nu` needs updating.
- **External type coupling (medium)** — Test helpers assume struct layouts for `HttpRequest`, `Params`, `HeaderPair`, `QueryPair`, and `HttpResponse`. If NURL stdlib changes these layouts, tests break silently (wrong field order = wrong data = false passes). Mitigation: document the assumed layout in `test_helpers.nu` comments; if upstream adds factory functions, migrate immediately.
- **No assertion library (low)** — Manual comparison is verbose but straightforward. Mitigation: assertion helpers in `test_helpers.nu` reduce boilerplate.
- **Network test flakiness (low)** — TCP tests may fail under load or in restricted environments. Mitigation: `NURL_NET_TESTS=1` gate; tests use high random ports; retry logic in runner.
- **NURL compiler availability (low)** — Tests require `nurlc` or the `nurl.sh` wrapper. If the NURL checkout isn't available, tests can't compile. Mitigation: document the prerequisite in `test/README.md`.
- **Closure comparison limitation (low)** — NURL has no way to compare closures for equality. Middleware tests use side effects (setting a flag on Ctx.state) to verify execution order.

## Documentation / Operational Notes

- Add `test/README.md` with instructions for running tests
- Document `NURL_NET_TESTS=1` gate
- Document the assertion helper API
- Note that valgrind/ASAN should be run periodically for leak detection

## Sources & References

- **Origin document:** [docs/plans/2026-05-23-001-feat-optimal-web-framework-beta-plan.md](docs/plans/2026-05-23-001-feat-optimal-web-framework-beta-plan.md)
- **Framework source:** `stdlib/ext/nurl_app.nu` (1041 LOC, v0.2.1)
- **TODOS:** `TODOS.md` — known issues that should be verified by tests (phantom cookie response, streaming write-on-hijack)
- **Examples:** `examples/web_minimal.nu`, `examples/web_app.nu` — reference for test request construction patterns
