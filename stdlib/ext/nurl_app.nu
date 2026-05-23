// stdlib/ext/nurl_app.nu — high-level web framework for NURL.  v0.2.2
//
// Inspired by FastAPI, Koa, and Express. Layers ergonomics on top of
// the existing Phase 1–9 HTTP stack:
//
//   * Phase 1:  tcp_listen / tcp_accept / TcpConn           (std/net)
//   * Phase 2:  HttpRequest / parse_request_head             (ext/http_request)
//   * Phase 3:  HttpResponse / response_text / response_json (ext/http_response)
//   * Phase 4-5: server_new / server_run / server_run_pool   (ext/http_server)
//   * Phase 6:  Router / router_get / router_handle / Params (ext/http_router)
//   * Phase 7:  serve_static / auth / cookies                (ext/http_static, ext/http_auth)
//   * Phase 8:  with_access_log / with_metrics / Metrics      (ext/http_middleware)
//   * Phase 9:  multipart / WebSocket / HTTP/2 / TLS          (ext/websocket, ...)
//
// Pure NURL stdlib module — no compiler or runtime changes required.
//
// ── Quick start ──────────────────────────────────────────────────────
//
//     $ `stdlib/ext/nurl_app.nu`
//
//     @ main → i {
//       : App app ( app_new )
//       ( app_get  app `/`          \ Ctx ctx → v { ( ctx_text ctx 200 `hello world\n` ) } )
//       ( app_get  app `/api/ping`  \ Ctx ctx → v { ( ctx_json_str ctx 200 `{"pong":true}` ) } )
//       ( app_post app `/api/echo`  \ Ctx ctx → v {
//         ( ctx_json_str ctx 200 ( ctx_body_string ctx ) )
//       } )
//       ^ ( app_run app `0.0.0.0` 8080 )
//     }
//
// ── Core concepts ────────────────────────────────────────────────────
//
//   App       — top-level application builder. Owns Router + middleware
//               chain + config. Created via `app_new`, routes registered
//               via `app_get` / `app_post` / etc., run via `app_run`.
//
//   Ctx       — per-request context. Heap-allocated via boxed-handle
//               pattern (Ctx { s ctl } → CtxImpl). Read the request,
//               build the response. The framework frees CtxImpl on all
//               exit paths after the handler returns.
//
//   Handler   — `( @ v Ctx )` closure. Receives a borrowed Ctx, writes
//               a response into it, returns void. The framework serialises
//               the response after the handler returns.
//
//   Middleware — `( @ b Ctx )` closure. Runs before the handler. Return
//               `T` to continue the chain, `F` to abort (response already
//               set). Applied in registration order.
//
//   Group     — route group with shared prefix + group-local middleware.
//               Created via `app_group`. Middleware on the group applies
//               to every route in the group.
//
//   Streaming — call `ctx_hijack` to take ownership of the TcpConn for
//               WebSocket or SSE. Only available via `app_run_streaming`.
//
// ── API ──────────────────────────────────────────────────────────────
//
//   App construction:
//     ( app_new )                                        → App
//     ( app_free App app )                               → v
//
//   Configuration (call before app_run):
//     ( app_with_cors App app )                          → App
//     ( app_with_logging App app )                       → App
//     ( app_with_metrics App app )                       → App
//     ( app_with_body_limit App app i max_bytes )        → App
//     ( app_with_idle_timeout App app i ms )             → App
//     ( app_with_workers App app i n )                   → App
//     ( app_static App app s dir )                       → v
//
//   Route registration:
//     ( app_get    App app s pattern ( @ v Ctx ) handler ) → v
//     ( app_post   App app s pattern ( @ v Ctx ) handler ) → v
//     ( app_put    App app s pattern ( @ v Ctx ) handler ) → v
//     ( app_patch  App app s pattern ( @ v Ctx ) handler ) → v
//     ( app_delete App app s pattern ( @ v Ctx ) handler ) → v
//
//   Middleware:
//     ( app_use App app ( @ b Ctx ) mw )                 → v
//
//   Route groups:
//     ( app_group App app s prefix )                     → Group
//     ( group_get    Group g s pattern ( @ v Ctx ) h )    → v
//     ( group_post   Group g s pattern ( @ v Ctx ) h )    → v
//     ( group_put    Group g s pattern ( @ v Ctx ) h )    → v
//     ( group_patch  Group g s pattern ( @ v Ctx ) h )    → v
//     ( group_delete Group g s pattern ( @ v Ctx ) h )    → v
//     ( group_use    Group g ( @ b Ctx ) mw )             → v
//
//   Server lifecycle:
//     ( app_run App app s host i port )                  → i
//     ( app_run_streaming App app s host i port )        → i
//     ( app_on_start App app ( @ v ) hook )              → v
//     ( app_on_stop  App app ( @ v ) hook )              → v
//
//   Ctx — request accessors:
//     ( ctx_method       Ctx ctx ) → s
//     ( ctx_path         Ctx ctx ) → s
//     ( ctx_query_string Ctx ctx ) → s
//     ( ctx_header       Ctx ctx s name ) → ? String
//     ( ctx_param        Ctx ctx s name ) → ? String
//     ( ctx_body_string  Ctx ctx ) → String            // OWNED
//     ( ctx_body_json    Ctx ctx ) → ! Json ParseErr    // OWNED (Ok arm)
//     ( ctx_query_get    Ctx ctx s key ) → ? String
//     ( ctx_form_get     Ctx ctx s key ) → ? String
//     ( ctx_cookie       Ctx ctx s name ) → ? String
//     ( ctx_bearer       Ctx ctx ) → ? String
//     ( ctx_basic_auth   Ctx ctx ) → ? BasicAuth
//
//   Ctx — response builders (each sets status + body + Content-Type):
//     ( ctx_text        Ctx ctx i status s body ) → v
//     ( ctx_html        Ctx ctx i status s body ) → v
//     ( ctx_json_str    Ctx ctx i status s body ) → v
//     ( ctx_json        Ctx ctx i status Json j ) → v
//     ( ctx_redirect    Ctx ctx i status s url )  → v
//     ( ctx_status      Ctx ctx i status )        → v
//     ( ctx_set_header  Ctx ctx s name s val )    → v
//     ( ctx_set_cookie  Ctx ctx s name s val )    → v
//
//     ( ctx_respond Ctx ctx ) → HttpResponse       // OWNED, for escape hatches
//
//   Streaming (app_run_streaming only):
//     ( ctx_hijack Ctx ctx ) → TcpConn              // one-way door, owns conn
//     ( ctx_stream_begin Ctx ctx i status ) → ! v NetErr
//     ( ctx_stream_write Ctx ctx s data ) → ! v NetErr
//     ( ctx_stream_end Ctx ctx ) → ! v NetErr
//     ( ctx_upgrade_ws Ctx ctx ( @ ! v WsErr WsMessage ) handler ) → ! v WsErr
//
//   Helpers:
//     ( app_count App app ) → i                   // number of registered routes

$ `stdlib/ext/http_full.nu`

// ── Version ──────────────────────────────────────────────────────────
: __NURL_APP_VERSION s `0.2.2`

// ── Internal: CtxImpl (heap-allocated per-request state) ─────────────
//
// Boxed-handle pattern: Ctx { s ctl } → single pointer to CtxImpl.
// Avoids the Vec multi-field-struct stride bug. Same pattern as
// Route { s ctl } in http_router.nu.
//
// Memory model:
//   req     — BORROWED from server, do NOT free
//   resp    — OWNED HttpResponse pointer, 0 = null
//   params  — BORROWED from router dispatch, do NOT free
//   conn    — BORROWED TcpConn, only non-zero on streaming path
//   pending — OWNED Vec of HeaderPair, applied when response is set

: CtxImpl {
    s req                // borrowed HttpRequest
    s resp               // owned HttpResponse (0 = null)
    s params             // borrowed Params
    s conn               // borrowed TcpConn (streaming path)
    i body_limit         // max body bytes
    i request_id         // incrementing counter for log tracing
    i state              // generic scratch for middleware
    b hijacked           // handler called ctx_hijack
    s pending_headers    // heap Vec[HeaderPair] (0 = null)
    s pending_cookies     // heap Vec[PendingCookie] (0 = null)
}

: Ctx { s ctl }         // single-pointer handle → CtxImpl

// Pending cookie data for deferred cookie application.
: PendingCookie {
    String name
    String value
}


// ── Ctx constructors ─────────────────────────────────────────────────

@ __ctx_new HttpRequest req Params params s conn i body_limit i request_id → Ctx {
    : *CtxImpl impl # *CtxImpl ( nurl_alloc Z CtxImpl )
    = . impl req # s req
    = . impl resp # s 0
    = . impl params # s params
    = . impl conn conn
    = . impl body_limit body_limit
    = . impl request_id request_id
    = . impl state 0
    = . impl hijacked F
    = . impl pending_headers # s 0
    = . impl pending_cookies # s 0
    ^ @ Ctx { # s impl }
}

// Free CtxImpl and all owned data. Safe to call on any exit path.
@ __ctx_free Ctx ctx → v {
    : *CtxImpl impl # *CtxImpl . ctx ctl

    // Free owned response (if any).
    : s rp . impl resp
    ? != 0 # i rp {
        : HttpResponse r @ HttpResponse { rp }
        ( http_response_free r )
    } {}

    // Free pending headers (if any).
    : s pp . impl pending_headers
    ? != 0 # i pp {
        : ( Vec HeaderPair ) pv @ ( Vec HeaderPair ) { pp }
        // HeaderPair has no heap sub-allocations in the common case
        // (key/value are borrowed from the header string), so vec_free
        // is sufficient.
        ( vec_free [HeaderPair] pv )
    } {}

    // Free pending cookies (if any).
    : s pc . impl pending_cookies
    ? != 0 # i pc {
        : ( Vec PendingCookie ) pcv @ ( Vec PendingCookie ) { pc }
        : i cn ( vec_len [PendingCookie] pcv )
        : ~ i ci 0
        ~ < ci cn {
            : ? PendingCookie co ( vec_get [PendingCookie] pcv ci )
            ?? co { T c → { ( string_free . c name ) ( string_free . c value ) } F → {} }
            = ci + ci 1
        }
        ( vec_free [PendingCookie] pcv )
    } {}

    // Free the CtxImpl itself. Do NOT free req/params/conn — those
    // are borrowed with distinct owners.
    ( nurl_free # s impl )
}

// Convert request body Vec[u] to an owned String.
@ __body_to_string HttpRequest req → String {
    : i blen ( vec_len [u] . req body )
    ? == blen 0 { ^ ( string_new ) } {}
    : String s ( string_with_cap + blen 1 )
    : ~ i k 0
    ~ < k blen {
        : ? u co ( vec_get [u] . req body k )
        ?? co { T c → { ( string_push_char s c ) } F → {} }
        = k + k 1
    }
    ( __string_seal s )
    ^ s
}

// ── Ctx request accessors ────────────────────────────────────────────
//
// All accessors dereference through the boxed handle. Null guard at
// dispatch entry ensures req/params are valid for the handler duration.

@ ctx_method Ctx ctx → s {
    : *CtxImpl impl # *CtxImpl . ctx ctl
    : HttpRequest req @ HttpRequest { . impl req }
    ^ ( string_data . req method )
}

@ ctx_path Ctx ctx → s {
    : *CtxImpl impl # *CtxImpl . ctx ctl
    : HttpRequest req @ HttpRequest { . impl req }
    ^ ( string_data . req path )
}

@ ctx_query_string Ctx ctx → s {
    : *CtxImpl impl # *CtxImpl . ctx ctl
    : HttpRequest req @ HttpRequest { . impl req }
    ^ ( string_data . req query )
}

@ ctx_header Ctx ctx s name → ?String {
    : *CtxImpl impl # *CtxImpl . ctx ctl
    : HttpRequest req @ HttpRequest { . impl req }
    ^ ( header_get . req headers name )
}

@ ctx_param Ctx ctx s name → ?String {
    : *CtxImpl impl # *CtxImpl . ctx ctl
    : Params p @ Params { . impl params }
    ^ ( params_get p name )
}

@ ctx_body_string Ctx ctx → String {
    : *CtxImpl impl # *CtxImpl . ctx ctl
    : HttpRequest req @ HttpRequest { . impl req }
    ^ ( __body_to_string req )
}

// Parse the body as JSON. Returns Ok(Json) on success, Err(ParseErr) on failure.
// Caller owns the Json in the Ok arm (free with json_free).
@ ctx_body_json Ctx ctx → ! Json ParseErr {
    : *CtxImpl impl # *CtxImpl . ctx ctl
    : HttpRequest req @ HttpRequest { . impl req }
    : String s ( __body_to_string req )
    : ! Json ParseErr jr ( json_parse ( string_data s ) )
    ( string_free s )
    ^ jr
}

// Search a Vec[QueryPair] for a matching key. Returns owned copy of value.
@ __search_pair ( Vec QueryPair ) pairs s key → ?String {
    : i n ( vec_len [QueryPair] pairs )
    : ~ i k 0
    : ~ ?String result @ ?String { F ( string_new ) }
    ~ < k n {
        : ? QueryPair qo ( vec_get [QueryPair] pairs k )
        ?? qo { T qp → {
            ? != 0 ( nurl_str_eq ( string_data . qp key ) key ) {
                = result @ ?String { T ( string_from ( string_data . qp value ) ) }
                = k n
            } {
                = k + k 1
            }
        } F → { = k + k 1 } }
    }
    ^ result
}

@ ctx_query_get Ctx ctx s key → ?String {
    : *CtxImpl impl # *CtxImpl . ctx ctl
    : HttpRequest req @ HttpRequest { . impl req }
    : ( Vec QueryPair ) qs ( parse_query ( string_data . req query ) )
    : ?String result ( __search_pair qs key )
    ( query_pairs_free qs )
    ^ result
}

@ ctx_form_get Ctx ctx s key → ?String {
    : *CtxImpl impl # *CtxImpl . ctx ctl
    : HttpRequest req @ HttpRequest { . impl req }
    : ? String ct ( header_get . req headers `Content-Type` )
    ?? ct {
        T ctype → {
            : b is_form != 0 ( nurl_str_eq ( string_data ctype ) `application/x-www-form-urlencoded` )
            ( string_free ctype )
            ? is_form {
                : ( Vec QueryPair ) pairs ( parse_form_urlencoded . req body )
                : ?String result ( __search_pair pairs key )
                ( query_pairs_free pairs )
                ^ result
            } { ^ @ ?String { F ( string_new ) } }
        }
        F empty → { ( string_free empty ) ^ @ ?String { F ( string_new ) } }
    }
}

@ ctx_cookie Ctx ctx s name → ?String {
    : *CtxImpl impl # *CtxImpl . ctx ctl
    : HttpRequest req @ HttpRequest { . impl req }
    ^ ( request_cookie req name )
}

@ ctx_bearer Ctx ctx → ?String {
    : *CtxImpl impl # *CtxImpl . ctx ctl
    : HttpRequest req @ HttpRequest { . impl req }
    ^ ( parse_bearer_auth req )
}

@ ctx_basic_auth Ctx ctx → ?BasicAuth {
    : *CtxImpl impl # *CtxImpl . ctx ctl
    : HttpRequest req @ HttpRequest { . impl req }
    ^ ( parse_basic_auth req )
}

// ── Ctx response builders ────────────────────────────────────────────
//
// Each builder creates an owned HttpResponse, stores it in impl.resp,
// and applies any pending headers. If a previous response was set, it
// is freed first (last-write-wins, matching Koa semantics).
//
// If ctx_set_header was called before a response exists, those headers
// are stored in a pending list and applied when the first response is
// set via any ctx_* builder.

@ __ctx_set_resp Ctx ctx HttpResponse r → v {
    : *CtxImpl impl # *CtxImpl . ctx ctl

    // Free any previous response.
    : s old_rp . impl resp
    ? != 0 # i old_rp {
        : HttpResponse old @ HttpResponse { old_rp }
        ( http_response_free old )
    } {}

    // Store new response.
    = . impl resp # s . r raw

    // Apply pending headers (if any).
    : s pp . impl pending_headers
    ? != 0 # i pp {
        : ( Vec HeaderPair ) pv @ ( Vec HeaderPair ) { pp }
        : i n ( vec_len [HeaderPair] pv )
        : ~ i k 0
        ~ < k n {
            : ? HeaderPair ho ( vec_get [HeaderPair] pv k )
            ?? ho { T h → {
                ( response_set_header r ( string_data . h key ) ( string_data . h value ) )
            } F → {} }
            = k + k 1
        }
        ( vec_free [HeaderPair] pv )
        = . impl pending_headers # s 0
    } {}

    // Apply pending cookies (if any).
    : s pc . impl pending_cookies
    ? != 0 # i pc {
        : ( Vec PendingCookie ) pcv @ ( Vec PendingCookie ) { pc }
        : i cn ( vec_len [PendingCookie] pcv )
        : ~ i ci 0
        ~ < ci cn {
            : ? PendingCookie co ( vec_get [PendingCookie] pcv ci )
            ?? co { T c → {
                ( response_set_cookie r ( string_data . c name ) ( string_data . c value ) ( cookie_opts_default ) )
                ( string_free . c name ) ( string_free . c value )
            } F → {} }
            = ci + ci 1
        }
        ( vec_free [PendingCookie] pcv )
        = . impl pending_cookies # s 0
    } {}
}

@ ctx_text Ctx ctx i status s body → v {
    : HttpResponse r ( response_text status body )
    ( __ctx_set_resp ctx r )
}

@ ctx_html Ctx ctx i status s body → v {
    : HttpResponse r ( response_text status body )
    ( response_set_header r `Content-Type` `text/html; charset=utf-8` )
    ( __ctx_set_resp ctx r )
}

@ ctx_json_str Ctx ctx i status s body → v {
    : HttpResponse r ( response_text status body )
    ( response_set_header r `Content-Type` `application/json; charset=utf-8` )
    ( __ctx_set_resp ctx r )
}

@ ctx_json Ctx ctx i status Json j → v {
    : HttpResponse r ( response_json status j )
    ( __ctx_set_resp ctx r )
}

@ ctx_redirect Ctx ctx i status s url → v {
    : HttpResponse r ( response_redirect status url )
    ( __ctx_set_resp ctx r )
}

@ ctx_status Ctx ctx i status → v {
    : HttpResponse r ( response_status_only status )
    ( __ctx_set_resp ctx r )
}

// Set a header. If no response exists yet, store in pending_headers list.
@ ctx_set_header Ctx ctx s name s val → v {
    : *CtxImpl impl # *CtxImpl . ctx ctl
    : s rp . impl resp
    ? != 0 # i rp {
        // Response exists — apply directly.
        : HttpResponse r @ HttpResponse { rp }
        ( response_set_header r name val )
    } {
        // No response yet — append to pending headers.
        : s pp . impl pending_headers
        ? == 0 # i pp {
            // First pending header — create the Vec.
            = . impl pending_headers # s ( vec_new [HeaderPair] )
        } {}
        : s pp2 . impl pending_headers
        : ( Vec HeaderPair ) pv @ ( Vec HeaderPair ) { pp2 }
        : HeaderPair hp @ HeaderPair { ( string_from name ) ( string_from val ) }
        ( vec_push [HeaderPair] pv hp )
    }
}

@ ctx_set_cookie Ctx ctx s name s val → v {
    : *CtxImpl impl # *CtxImpl . ctx ctl
    : s rp . impl resp
    ? != 0 # i rp {
        // Response exists — apply directly.
        : HttpResponse r @ HttpResponse { rp }
        ( response_set_cookie r name val ( cookie_opts_default ) )
    } {
        // No response yet — append to pending cookies.
        : s pc . impl pending_cookies
        ? == 0 # i pc {
            = . impl pending_cookies # s ( vec_new [PendingCookie] )
        } {}
        : s pc2 . impl pending_cookies
        : ( Vec PendingCookie ) pcv @ ( Vec PendingCookie ) { pc2 }
        : PendingCookie c @ PendingCookie { ( string_from name ) ( string_from val ) }
        ( vec_push [PendingCookie] pcv c )
    }
}

// Extract the owned HttpResponse. Caller now owns the response.
@ ctx_respond Ctx ctx → HttpResponse {
    : *CtxImpl impl # *CtxImpl . ctx ctl
    : s rp . impl resp
    ? != 0 # i rp {
        : HttpResponse r @ HttpResponse { rp }
        = . impl resp # s 0
        ^ r
    } {
        ^ ( response_status_only 204 )
    }
}

// ── Internal: MwEntry (middleware slot) ──────────────────────────────
//
// Single-pointer handle pattern. No linked list — Vec iteration only.

: MwEntryImpl {
    ( @ b Ctx ) mw       // the middleware closure
}

: MwEntry { s ctl }      // single-pointer handle → MwEntryImpl

// ── Internal: GroupImpl ──────────────────────────────────────────────

: GroupImpl {
    App app               // borrowed parent app
    String prefix
    ( Vec s ) mw_list     // boxed MwEntry pointers
}

: Group { s ctl }

// ── App ──────────────────────────────────────────────────────────────

: App {
    Router router
    ( Vec s ) mw_chain       // boxed MwEntry pointers
    b use_cors
    b use_logging
    b use_metrics
    Metrics metrics
    i body_limit             // 0 = default 10 MB
    i idle_timeout_ms        // 0 = default 30s
    i workers                // 0 = default 16
    i next_request_id        // incrementing counter
    String static_dir        // empty = no static serving
    ( Vec s ) on_start_hooks
    ( Vec s ) on_stop_hooks
}

// ── App construction ─────────────────────────────────────────────────

@ app_new → App {
    ^ @ App {
        ( router_new )
        ( vec_new [s] )
        F F F
        ( metrics_new )
        0 0 0
        0
        ( string_new )
        ( vec_new [s] )
        ( vec_new [s] )
    }
}

@ app_free App app → v {
    ( router_free . app router )
    ( vec_free_with [s] . app mw_chain \ s p → v {
        ? != 0 # i p {
            : *MwEntryImpl impl # *MwEntryImpl p
            ( nurl_free # s impl )
        } {}
    } )
    ( metrics_free . app metrics )
    ( string_free . app static_dir )
    ( vec_free [s] . app on_start_hooks )
    ( vec_free [s] . app on_stop_hooks )
}

// ── Configuration ────────────────────────────────────────────────────

@ app_with_cors App app → App { = . app use_cors T ^ app }
@ app_with_logging App app → App { = . app use_logging T ^ app }
@ app_with_metrics App app → App { = . app use_metrics T ^ app }
@ app_with_body_limit App app i max_bytes → App { = . app body_limit max_bytes ^ app }
@ app_with_idle_timeout App app i ms → App { = . app idle_timeout_ms ms ^ app }
@ app_with_workers App app i n → App { = . app workers n ^ app }

@ app_static App app s dir → v {
    ( string_free . app static_dir )
    = . app static_dir ( string_from dir )
}

@ app_count App app → i { ^ ( router_count . app router ) }

// ── Middleware registration ──────────────────────────────────────────

@ app_use App app ( @ b Ctx ) mw → v {
    : *MwEntryImpl impl # *MwEntryImpl ( nurl_alloc Z MwEntryImpl )
    = . impl mw mw
    ( vec_push [s] . app mw_chain # s impl )
}

// ── Internal: single dispatch function ───────────────────────────────
//
// One function for all dispatch: app routes and group routes.
// Takes middleware chains and handler, creates Ctx, runs mw, calls
// handler, extracts response. Called from route closures registered
// on the router.
//
// All exit paths call __ctx_free to prevent memory leaks.

// Walk a middleware chain. Returns T if all passed, F if any aborted.
@ __walk_mw ( Vec s ) mw_list Ctx ctx → b {
    : i n ( vec_len [s] mw_list )
    : ~ b proceed T
    : ~ i mi 0
    ~ & proceed < mi n {
        : s slot_p ?? ( vec_get [s] mw_list mi ) { T p → p F → # s 0 }
        ? != 0 # i slot_p {
            : *MwEntryImpl mw_impl # *MwEntryImpl slot_p
            : ( @ b Ctx ) f . mw_impl mw
            : b ok ( f ctx )
            ? == ok 0 { = proceed F } {}
        } {}
        = mi + mi 1
    }
    ^ proceed
}

@ __dispatch HttpRequest req Params params App app ( Vec s ) app_mw ( Vec s ) group_mw ( @ v Ctx ) handler → HttpResponse {
    : i blimit . app body_limit
    ? == blimit 0 { = blimit 10485760 } {}

    // Null guard: if req pointer is null, return 500 immediately.
    : i req_raw # i . req raw
    ? == req_raw 0 {
        ^ ( response_text 500 `internal error: null request\n` )
    } {}

    // Increment request ID.
    = . app next_request_id + . app next_request_id 1
    : i rid . app next_request_id

    : Ctx ctx ( __ctx_new req params # s 0 blimit rid )

    // Enforce body limit directly from the request.
    : i body_len ( vec_len [u] . req body )
    ? > body_len blimit {
        ( __ctx_free ctx )
        ^ ( response_text 413 `request body too large\n` )
    } {}

    // Walk middleware chains (app-level first, then group-level).
    : b proceed ( __walk_mw app_mw ctx )
    ? proceed { = proceed ( __walk_mw group_mw ctx ) } {}

    // Call handler.
    ? proceed { ( handler ctx ) } {}

    // Check hijack — handler took over the connection.
    : *CtxImpl impl # *CtxImpl . ctx ctl
    ? . impl hijacked {
        // Handler owns the conn. Return a synthetic response.
        ( __ctx_free ctx )
        ^ ( response_status_only 200 )
    } {}

    // Extract response.
    : s rp . impl resp
    ? != 0 # i rp {
        : HttpResponse final @ HttpResponse { rp }
        = . impl resp # s 0
        ( __ctx_free ctx )
        ^ final
    } {
        // No response set — synthesize 500.
        ( __ctx_free ctx )
        ^ ( response_text 500 `handler did not produce a response\n` )
    }
}

// ── Route registration (App-level) ───────────────────────────────────

@ __register_route App app s method s pattern ( @ v Ctx ) handler → v {
    // Snapshot middleware at registration time.
    : ( Vec s ) mw_snapshot . app mw_chain
    ( router_any . app router method pattern
    \ HttpRequest req Params params → HttpResponse {
        ^ ( __dispatch req params app mw_snapshot ( vec_new [s] ) handler )
    } )
}

@ app_get    App app s pattern ( @ v Ctx ) handler → v { ( __register_route app `GET` pattern handler ) }
@ app_post   App app s pattern ( @ v Ctx ) handler → v { ( __register_route app `POST` pattern handler ) }
@ app_put    App app s pattern ( @ v Ctx ) handler → v { ( __register_route app `PUT` pattern handler ) }
@ app_patch  App app s pattern ( @ v Ctx ) handler → v { ( __register_route app `PATCH` pattern handler ) }
@ app_delete App app s pattern ( @ v Ctx ) handler → v { ( __register_route app `DELETE` pattern handler ) }

// ── Route groups ─────────────────────────────────────────────────────

@ app_group App app s prefix → Group {
    : *GroupImpl gi # *GroupImpl ( nurl_alloc Z GroupImpl )
    = . gi app app
    = . gi prefix ( string_from prefix )
    = . gi mw_list ( vec_new [s] )
    ^ @ Group { # s gi }
}

@ group_use Group g ( @ b Ctx ) mw → v {
    : *GroupImpl gi # *GroupImpl . g ctl
    : *MwEntryImpl impl # *MwEntryImpl ( nurl_alloc Z MwEntryImpl )
    = . impl mw mw
    ( vec_push [s] . gi mw_list # s impl )
}

// Join group prefix + route pattern. Always inserts '/' separator
// when neither prefix ends with '/' nor pattern starts with '/'.
@ __group_path Group g s pattern → String {
    : *GroupImpl gi # *GroupImpl . g ctl
    : s pfx ( string_data . gi prefix )
    : i plen ( nurl_str_len pfx )
    : i slen ( nurl_str_len pattern )

    // Determine if we need to drop trailing slash from prefix.
    : ~ i drop 0
    ? & > plen 0 == ( nurl_str_get pfx - plen 1 ) 47 { = drop 1 } {}
    // Determine if we need to skip leading slash from pattern.
    : ~ i start 0
    ? & > slen 0 == ( nurl_str_get pattern 0 ) 47 { = start 1 } {}
    // Do we need to insert a '/' separator?
    : ~ b insert_sep F
    ? & == drop 0 == start 0 { = insert_sep T } {}

    : String path ( string_with_cap + plen slen 2 )
    : ~ i k 0
    ~ < k - plen drop { ( string_push_char path ( nurl_str_get pfx k ) ) = k + k 1 }
    ? insert_sep { ( string_push_char path 47 ) } {}
    = k start
    ~ < k slen { ( string_push_char path ( nurl_str_get pattern k ) ) = k + k 1 }
    ^ path
}

@ __group_register Group g s method s pattern ( @ v Ctx ) handler → v {
    : *GroupImpl gi # *GroupImpl . g ctl
    : String full_path ( __group_path g pattern )
    : App app . gi app
    : ( Vec s ) gmw . gi mw_list
    : ( Vec s ) app_mw . app mw_chain

    ( router_any . app router method ( string_data full_path )
    \ HttpRequest req Params params → HttpResponse {
        ^ ( __dispatch req params app app_mw gmw handler )
    } )
    ( string_free full_path )
}

@ group_get    Group g s pattern ( @ v Ctx ) handler → v { ( __group_register g `GET` pattern handler ) }
@ group_post   Group g s pattern ( @ v Ctx ) handler → v { ( __group_register g `POST` pattern handler ) }
@ group_put    Group g s pattern ( @ v Ctx ) handler → v { ( __group_register g `PUT` pattern handler ) }
@ group_patch  Group g s pattern ( @ v Ctx ) handler → v { ( __group_register g `PATCH` pattern handler ) }
@ group_delete Group g s pattern ( @ v Ctx ) handler → v { ( __group_register g `DELETE` pattern handler ) }

// ── Lifecycle hooks ──────────────────────────────────────────────────

@ app_on_start App app ( @ v ) hook → v {
    ( vec_push [s] . app on_start_hooks # s hook )
}

@ app_on_stop App app ( @ v ) hook → v {
    ( vec_push [s] . app on_stop_hooks # s hook )
}

@ __run_hooks ( Vec s ) hooks → v {
    : i n ( vec_len [s] hooks )
    : ~ i k 0
    ~ < k n {
        : s raw ?? ( vec_get [s] hooks k ) { T r → r F → # s 0 }
        ? != 0 # i raw {
            : ( @ v ) f raw
            ( f )
        } {}
        = k + k 1
    }
}

// ── Static serving ───────────────────────────────────────────────────

@ __register_static App app → v {
    : i slen ( string_len . app static_dir )
    ? > slen 0 {
        : String dir_copy ( string_from ( string_data . app static_dir ) )
        ( router_get . app router `/*path`
        \ HttpRequest req Params params → HttpResponse {
            : ? String tail_opt ( params_get params `path` )
            ?? tail_opt {
                T tail → {
                    ? ( __has_dotdot_segment ( string_data tail ) ) {
                        ( string_free tail )
                        ^ ( response_text 403 `forbidden\n` )
                    } {
                        : String full ( path_join ( string_data dir_copy ) ( string_data tail ) )
                        : ! ( Vec u ) IoErr rd ( read_file_bytes ( string_data full ) )
                        ?? rd {
                            T body → {
                                : String ext ( path_extension ( string_data full ) )
                                : s mime ( mime_for_ext ( string_data ext ) )
                                ( string_free ext ) ( string_free full ) ( string_free tail )
                                : HttpResponse r ( response_new 200 )
                                ( response_set_header r `Content-Type` mime )
                                ( response_set_body_bytes r body )
                                ( vec_free [u] body )
                                ^ r
                            }
                            F _ → {
                                ( string_free full ) ( string_free tail )
                                ^ ( response_text 404 `not found\n` )
                            }
                        }
                    }
                }
                F _ → {
                    : String idx ( path_join ( string_data dir_copy ) `index.html` )
                    : ! ( Vec u ) IoErr rd ( read_file_bytes ( string_data idx ) )
                    ( string_free idx )
                    ?? rd {
                        T body → {
                            : HttpResponse r ( response_new 200 )
                            ( response_set_header r `Content-Type` `text/html; charset=utf-8` )
                            ( response_set_body_bytes r body )
                            ( vec_free [u] body )
                            ^ r
                        }
                        F _ → ^ ( response_text 404 `not found\n` )
                    }
                }
            }
        } )
        ( string_free dir_copy )
    } {}
}

// Print the startup banner. Reads resolved config from App.
@ __print_banner App app s host i port s extra → v {
    : i wk . app workers

    ( nurl_print `[nurl-app v` )
    ( nurl_print __NURL_APP_VERSION )
    ( nurl_print `] listening on http://` )
    ( nurl_print host )
    ( nurl_print `:` )
    ( nurl_print ( nurl_str_int port ) )
    ( nurl_print `/  routes=` )
    ( nurl_print ( nurl_str_int ( router_count . app router ) ) )
    ( nurl_print `  workers=` )
    ( nurl_print ( nurl_str_int wk ) )
    ( nurl_print extra )
    ( nurl_print `\n` )
}

// Register the /health endpoint if metrics are enabled.
@ __register_health App app → v {
    ? . app use_metrics {
        ( app_get app `/health` \ Ctx ctx → v {
            ( ctx_json_str ctx 200 `{"status":"ok"}` )
        } )
    } {}
}

// Prepare for server startup: resolve config defaults, register routes, run hooks.
@ __prepare_run App app → v {
    // Resolve config defaults (0 = use default).
    ? == . app idle_timeout_ms 0 { = . app idle_timeout_ms 30000 } {}
    ? == . app workers 0 { = . app workers 16 } {}

    ( __register_static app )
    ( __register_health app )
    ( __run_hooks . app on_start_hooks )
}

// ── app_run ──────────────────────────────────────────────────────────

@ app_run App app s host i port → i {
    ( __prepare_run app )

    // Build the base handler that dispatches through the router.
    : ( @ HttpResponse HttpRequest ) base
    \ HttpRequest req → HttpResponse {
        ^ ( router_handle . app router req )
    }

    // Wrap with middleware layers.
    : ( @ HttpResponse HttpRequest ) wrapped base
    ? . app use_metrics {
        = wrapped ( with_metrics . app metrics wrapped )
    } {}
    ? . app use_cors {
        = wrapped ( with_cors_default wrapped )
    } {}
    ? . app use_logging {
        = wrapped ( with_access_log wrapped )
    } {}

    // Bind.
    : ! TcpListener NetErr lr ( tcp_listen host port )
    ?? lr {
        T listener → {
            ( signal_install_shutdown listener )

            : i timeout . app idle_timeout_ms
            : i wk . app workers

            ( __print_banner app host port `` )

            : HttpServer srv ( server_new_with_timeout listener wrapped timeout )
            : ! v NetErr rr ( server_run_pool srv wk )

            ( signal_clear_shutdown )
            ( server_stop srv )

            // Run on_stop hooks.
            ( __run_hooks . app on_stop_hooks )

            ?? rr {
                T _ → {
                    ( nurl_print `[nurl-app] clean shutdown\n` )
                    ^ 0
                }
                F e → {
                    ( nurl_eprint `[nurl-app] error: ` )
                    ( nurl_eprint ( net_err_name e ) )
                    ( nurl_eprint `\n` )
                    ^ 1
                }
            }
        }
        F e → {
            ( nurl_eprint `[nurl-app] bind failed: ` )
            ( nurl_eprint ( net_err_name e ) )
            ( nurl_eprint `\n` )
            ^ 1
        }
    }
}

// ── Streaming / WebSocket support ────────────────────────────────────
//
// Available via `app_run_streaming` only. The handler calls `ctx_hijack`
// to take ownership of the TcpConn for WebSocket or SSE streaming.
//
// Architectural note: We use a custom accept loop for streaming because
// http_server.nu's handler contract is `( @ HttpResponse HttpRequest )`
// with no TcpConn access. If http_server.nu gains a streaming-aware
// handler contract in the future, the two paths can unify. See TODOS.md.

// Hijack the connection. Returns the borrowed TcpConn to the handler.
// After this call, the handler owns the connection lifecycle.
// Calling ctx_hijack on a normal app_run connection is a runtime error.
@ ctx_hijack Ctx ctx → TcpConn {
    : *CtxImpl impl # *CtxImpl . ctx ctl
    : s cp . impl conn
    ? == 0 # i cp {
        ( nurl_eprint `[nurl-app] ctx_hijack called on non-streaming connection\n` )
        ( nurl_abort 1 )
    } {}
    = . impl hijacked T
    : TcpConn conn @ TcpConn { cp }
    ^ conn
}

// SSE streaming convenience wrappers.

@ ctx_stream_begin Ctx ctx i status → ! v NetErr {
    : TcpConn conn ( ctx_hijack ctx )
    : HttpResponse r ( response_new status )
    ( response_set_header r `Content-Type` `text/event-stream` )
    ( response_set_header r `Cache-Control` `no-cache` )
    ( response_set_header r `Connection` `keep-alive` )
    // Write the response head to the connection.
    : ! v NetErr we ( response_begin_chunked conn r )
    ?? we { T _ → ^ we F e → ^ @ ! v NetErr { F e } }
    ( http_response_free r )
    ^ @ ! v NetErr { T ( string_new ) }
}

@ ctx_stream_write Ctx ctx s data → ! v NetErr {
    // The conn was already hijacked. We need to write SSE format.
    : *CtxImpl impl # *CtxImpl . ctx ctl
    : TcpConn conn @ TcpConn { . impl conn }
    : String chunk ( string_from `data: ` )
    ( string_push_str chunk data )
    ( string_push_str chunk `\n\n` )
    : ! v NetErr we ( tcp_conn_write conn ( string_data chunk ) ( string_len chunk ) )
    ( string_free chunk )
    ^ we
}

@ ctx_stream_end Ctx ctx → ! v NetErr {
    // SSE streams typically don't have an explicit end; the handler
    // simply returns. This is a no-op placeholder for future use.
    ^ @ ! v NetErr { T ( string_new ) }
}

// WebSocket upgrade convenience wrapper.
@ ctx_upgrade_ws Ctx ctx ( @ ! v WsErr WsMessage ) handler → ! v WsErr {
    : TcpConn conn ( ctx_hijack ctx )
    : ! TcpConn WsErr hr ( ws_perform_handshake conn )
    ?? hr {
        T _ → {
            // Enter message loop.
            ( ws_serve_messages conn handler )
            ^ @ ! v WsErr { T ( string_new ) }
        }
        F e → ^ @ ! v WsErr { F e }
    }
}

// ── Internal: write HttpResponse to TcpConn ──────────────────────────
//
// Used by app_run_streaming for non-hijacked responses (e.g., middleware
// abort, normal HTTP responses on the streaming port).

@ __write_response TcpConn conn HttpResponse r → ! v NetErr {
    : String serialized ( response_serialize r )
    : ! v NetErr we ( tcp_conn_write conn ( string_data serialized ) ( string_len serialized ) )
    ( string_free serialized )
    ^ we
}

// ── app_run_streaming ────────────────────────────────────────────────
//
// Separate entry point for streaming/WS support. Uses a custom accept
// loop that passes TcpConn to the dispatch function.

@ app_run_streaming App app s host i port → i {
    ( __prepare_run app )

    // Bind.
    : ! TcpListener NetErr lr ( tcp_listen host port )
    ?? lr {
        T listener → {
            ( signal_install_shutdown listener )

            : i timeout . app idle_timeout_ms
            : i wk . app workers

            ( __print_banner app host port `  streaming=enabled` )

            // Custom accept loop — bypasses http_server.nu to provide
            // TcpConn access for hijack/streaming/WS.
            : ~ b running T
            ~ running {
                : ! TcpConn NetErr ar ( tcp_accept listener )
                ?? ar {
                    T conn → {
                        : ! HttpRequest NetErr pr ( parse_request_head conn timeout )
                        ?? pr {
                            T req → {
                                : HttpResponse resp ( router_handle . app router req )
                                // Write response to conn. For hijacked connections
                                // __dispatch returns a synthetic 200; writing to the
                                // already-closed conn fails harmlessly (NetErr).
                                : ! v NetErr we ( __write_response conn resp )
                                ?? we { T _ → {} F _ → {
                                    ( nurl_eprint `[nurl-app] stream write error\n` )
                                } }
                                ( http_response_free resp )
                            }
                            F _ → {}
                        }
                        ( tcp_conn_close conn )
                    }
                    F _ → {
                        // Accept error — check for shutdown signal.
                        ? ( signal_shutdown_requested ) { = running F } {}
                    }
                }
            }

            ( signal_clear_shutdown )
            ( __run_hooks . app on_stop_hooks )

            ( nurl_print `[nurl-app] clean shutdown\n` )
            ^ 0
        }
        F e → {
            ( nurl_eprint `[nurl-app] bind failed: ` )
            ( nurl_eprint ( net_err_name e ) )
            ( nurl_eprint `\n` )
            ^ 1
        }
    }
}
