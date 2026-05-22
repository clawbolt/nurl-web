// stdlib/ext/nurl_app.nu — high-level web framework for NURL.
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
//   Ctx       — per-request context. Thin wrapper over the raw
//               HttpRequest + HttpResponse that carries state through
//               the handler + middleware chain. Read the request, build
//               the response. The framework frees both after the handler
//               returns.
//
//   Handler   — `( @ v Ctx )` closure. Receives a borrowed Ctx, writes
//               a response into it, returns void. The framework serialises
//               the response after the handler returns.
//
//   Middleware — `( @ b Ctx )` closure. Runs before the handler. Return
//               `T` to continue the chain, `F` to abort (response already
//               set). Applied in registration order. Typical uses: auth,
//               rate limiting, request logging, body size checks.
//
//   Group     — route group with shared prefix + group-local middleware.
//               Created via `app_group`. Middleware on the group applies
//               to every route in the group. Groups can nest.
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
//     ( app_with_pretty_errors App app )                 → App
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
//     ( group_use    Group g ( @ b Ctx ) mw )              → v
//
//   Server lifecycle:
//     ( app_run App app s host i port )                  → i
//     ( app_on_start App app ( @ v ) hook )              → v
//     ( app_on_stop  App app ( @ v ) hook )              → v
//
//   Ctx — request accessors (all return borrowed/raw values):
//     ( ctx_method       Ctx ctx ) → s
//     ( ctx_path         Ctx ctx ) → s
//     ( ctx_query_string Ctx ctx ) → s
//     ( ctx_header       Ctx ctx s name ) → ? String
//     ( ctx_param        Ctx ctx s name ) → ? String
//     ( ctx_body_string  Ctx ctx ) → String      // OWNED
//     ( ctx_body_json    Ctx ctx ) → ? Json       // OWNED (Some arm)
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
//   Helpers:
//     ( app_count App app ) → i                   // number of registered routes

$ `stdlib/ext/http_full.nu`

// ── Ctx (per-request context) ────────────────────────────────────────
//
// The heart of the framework. Each incoming request creates one Ctx;
// the handler (and middleware chain) mutates it; the framework reads
// the response out after the handler returns.
//
// Memory model:
//   * `.req` is BORROWED from the server — do NOT free.
//   * `.resp` starts as NULL (0). After the handler writes via
//     ctx_text / ctx_json / etc., .resp points to an OWNED
//     HttpResponse that the framework frees after serialise+write.
//   * `.params` is BORROWED from the router dispatch — do NOT free.
//   * `.state` is a generic i64 scratch slot for middleware to stash
//     per-request state (user ID, rate limit counter, etc.).

: Ctx {
    s req                // borrowed HttpRequest pointer (raw s)
    s resp               // owned HttpResponse pointer (raw s), 0 = unset
    s params             // borrowed Params pointer (raw s)
    i body_limit         // max body bytes (0 = default 10 MB)
    b responded          // T after a ctx_* response method is called
    i state              // generic i64 scratch for middleware
}

// ── Ctx constructors ─────────────────────────────────────────────────

@ __ctx_new HttpRequest req Params params i body_limit → Ctx {
    ^ @ Ctx { # s req # s 0 # s params body_limit F 0 }
}

@ __ctx_free Ctx ctx → v {
    : s rp . ctx resp
    : i raw # i rp
    ? != raw 0 {
        // Safe cast: we know it's an HttpResponse pointer
        : s hp # s rp
        : HttpResponse hr @ HttpResponse { hp }
        ( http_response_free hr )
    } {}
}

// ── Ctx request accessors ────────────────────────────────────────────

@ ctx_method Ctx ctx → s {
    : HttpRequest req @ HttpRequest { . ctx req }
    ^ ( string_data . req method )
}

@ ctx_path Ctx ctx → s {
    : HttpRequest req @ HttpRequest { . ctx req }
    ^ ( string_data . req path )
}

@ ctx_query_string Ctx ctx → s {
    : HttpRequest req @ HttpRequest { . ctx req }
    ^ ( string_data . req query )
}

@ ctx_header Ctx ctx s name → ?String {
    : HttpRequest req @ HttpRequest { . ctx req }
    ^ ( header_get . req headers name )
}

@ ctx_param Ctx ctx s name → ?String {
    : Params p @ Params { . ctx params }
    ^ ( params_get p name )
}

// Return the full body as an owned String.
@ ctx_body_string Ctx ctx → String {
    : HttpRequest req @ HttpRequest { . ctx req }
    : i blen ( vec_len [u] . req body )
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

// Parse the body as JSON. Returns Some(Json) on success, None on failure.
// Caller owns the Json in the Some arm (free with json_free).
@ ctx_body_json Ctx ctx → ?Json {
    : HttpRequest req @ HttpRequest { . ctx req }
    : i blen ( vec_len [u] . req body )
    : String s ( string_with_cap + blen 1 )
    : ~ i k 0
    ~ < k blen {
        : ? u co ( vec_get [u] . req body k )
        ?? co { T c → { ( string_push_char s c ) } F → {} }
        = k + k 1
    }
    ( __string_seal s )
    : ! Json ParseErr jr ( json_parse ( string_data s ) )
    ( string_free s )
    ?? jr {
        T j → ^ @ ?Json { T j }
        F _ → ^ @ ?Json { F ( json_null ) }
    }
}

// Get a query parameter by name.
@ ctx_query_get Ctx ctx s key → ?String {
    : HttpRequest req @ HttpRequest { . ctx req }
    : ( Vec QueryPair ) qs ( parse_query ( string_data . req query ) )
    : i n ( vec_len [QueryPair] qs )
    : ~ i k 0
    : ~ ?String result @ ?String { F ( string_new ) }
    ~ & == 0 ( vec_len [QueryPair] qs ) < k n {
        : QueryPair qp ?? ( vec_get [QueryPair] qs k ) { T q → q F → @ QueryPair { ( string_new ) ( string_new ) } }
        ? != 0 ( nurl_str_eq ( string_data . qp key ) key ) {
            = result @ ?String { T ( string_from ( string_data . qp value ) ) }
            = k n
        } {
            = k + k 1
        }
    }
    ( query_pairs_free qs )
    ^ result
}

// Get a form-urlencoded field by name.
@ ctx_form_get Ctx ctx s key → ?String {
    : HttpRequest req @ HttpRequest { . ctx req }
    : ? String ct ( header_get . req headers `Content-Type` )
    ?? ct {
        T ctype → {
            : b is_form != 0 ( nurl_str_eq ( string_data ctype ) `application/x-www-form-urlencoded` )
            ( string_free ctype )
            ? is_form {
                : ( Vec QueryPair ) pairs ( parse_form_urlencoded . req body )
                : i n ( vec_len [QueryPair] pairs )
                : ~ i k 0
                : ~ ?String result @ ?String { F ( string_new ) }
                ~ < k n {
                    : QueryPair qp ?? ( vec_get [QueryPair] pairs k ) { T q → q F → @ QueryPair { ( string_new ) ( string_new ) } }
                    ? != 0 ( nurl_str_eq ( string_data . qp key ) key ) {
                        = result @ ?String { T ( string_from ( string_data . qp value ) ) }
                        = k n
                    } { = k + k 1 }
                }
                ( query_pairs_free pairs )
                ^ result
            } { ^ @ ?String { F ( string_new ) } }
        }
        F empty → { ( string_free empty ) ^ @ ?String { F ( string_new ) } }
    }
}

// Get a named cookie from the request.
@ ctx_cookie Ctx ctx s name → ?String {
    : HttpRequest req @ HttpRequest { . ctx req }
    ^ ( request_cookie req name )
}

// Get the Bearer token from the Authorization header.
@ ctx_bearer Ctx ctx → ?String {
    : HttpRequest req @ HttpRequest { . ctx req }
    ^ ( parse_bearer_auth req )
}

// Get the Basic auth credentials from the Authorization header.
@ ctx_basic_auth Ctx ctx → ?BasicAuth {
    : HttpRequest req @ HttpRequest { . ctx req }
    ^ ( parse_basic_auth req )
}

// ── Ctx response builders ────────────────────────────────────────────
//
// Each builder creates an owned HttpResponse, stores it in ctx.resp,
// and sets ctx.responded = T. If a previous response was set, it is
// freed first (last-write-wins, matching Koa semantics).

@ __ctx_set_resp Ctx ctx HttpResponse r → v {
    // Free any previous response.
    : s old_rp . ctx resp
    : i old_raw # i old_rp
    ? != old_raw 0 {
        : s hp # s old_rp
        : HttpResponse old @ HttpResponse { hp }
        ( http_response_free old )
    } {}
    // Store new response. We repack the HttpResponse handle into
    // raw s storage because Ctx.resp is typed as `s` for the
    // null-pointer check.
    = . ctx resp # s . r raw
    = . ctx responded T
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

@ ctx_set_header Ctx ctx s name s val → v {
    // If a response is already set, mutate it in place.
    // Otherwise create a placeholder.
    : s rp . ctx resp
    : i raw # i rp
    ? != raw 0 {
        : s hp # s rp
        : HttpResponse r @ HttpResponse { hp }
        ( response_set_header r name val )
    } {
        // No response yet — create one just to hold the header.
        // This is unusual but safe; the handler should set a
        // proper response before returning.
        : HttpResponse r ( response_new status )
        ( response_set_header r name val )
        ( __ctx_set_resp ctx r )
    }
}

@ ctx_set_cookie Ctx ctx s name s val → v {
    : s rp . ctx resp
    : i raw # i rp
    ? != raw 0 {
        : s hp # s rp
        : HttpResponse r @ HttpResponse { hp }
        ( response_set_cookie r name val ( cookie_opts_default ) )
    } {
        : HttpResponse r ( response_new 200 )
        ( response_set_cookie r name val ( cookie_opts_default ) )
        ( __ctx_set_resp ctx r )
    }
}

// Escape hatch: extract the owned HttpResponse out of the context.
// Resets ctx.responded to F and ctx.resp to 0. The caller now owns
// the response and must free it.
@ ctx_respond Ctx ctx → HttpResponse {
    : s rp . ctx resp
    : i raw # i rp
    ? != raw 0 {
        : s hp # s rp
        : HttpResponse r @ HttpResponse { hp }
        = . ctx resp # s 0
        = . ctx responded F
        ^ r
    } {
        ^ ( response_status_only 204 )
    }
}

// ── App ──────────────────────────────────────────────────────────────
//
// The top-level application object. Owns a Router, a middleware chain,
// config flags, and lifecycle hooks.

// Internal middleware slot: closure handle + next pointer.
// Stored as a boxed handle (single pointer) so Vec[MwSlot] doesn't
// hit the multi-field-struct stride bug.
: MwSlotImpl {
    ( @ b Ctx ) mw
    s next       // raw pointer to next MwSlotImpl, 0 = end
}

: MwSlot { s ctl }

// Internal lifecycle hook list.
: HookList {
    ( Vec s ) hooks   // raw closure pointers
}

// Route group with shared prefix + group-local middleware.
: GroupImpl {
    App app            // borrowed parent app
    String prefix
    ( Vec s ) mw_list  // boxed MwSlot pointers
}

: Group { s ctl }

: App {
    Router router
    ( Vec s ) mw_chain       // boxed MwSlot pointers, applied in order
    b use_cors
    b use_logging
    b use_metrics
    b pretty_errors
    Metrics metrics
    i body_limit             // 0 = default 10 MB
    i idle_timeout_ms        // 0 = default 30s
    i workers                // 0 = default 16
    String static_dir        // empty = no static serving
    ( Vec s ) on_start_hooks // raw closure pointers
    ( Vec s ) on_stop_hooks  // raw closure pointers
}

// ── App construction ─────────────────────────────────────────────────

@ app_new → App {
    ^ @ App {
        ( router_new )
        ( vec_new [s] )
        F F F F
        ( metrics_new )
        0 0 0
        ( string_new )
        ( vec_new [s] )
        ( vec_new [s] )
    }
}

@ app_free App app → v {
    ( router_free . app router )
    // Free middleware chain
    ( vec_free_with [s] . app mw_chain \ s p → v {
        ? != 0 # i p {
            : *MwSlotImpl impl # *MwSlotImpl p
            ( nurl_free # s impl )
        } {}
    } )
    ( metrics_free . app metrics )
    ( string_free . app static_dir )
    // Hook closures are (fn_ptr, env_ptr) pairs stored as raw s
    // pointers — no special per-element cleanup needed.
    ( vec_free [s] . app on_start_hooks )
    ( vec_free [s] . app on_stop_hooks )
}

// ── Configuration ────────────────────────────────────────────────────

@ app_with_cors App app → App {
    = . app use_cors T
    ^ app
}

@ app_with_logging App app → App {
    = . app use_logging T
    ^ app
}

@ app_with_metrics App app → App {
    = . app use_metrics T
    ^ app
}

@ app_with_body_limit App app i max_bytes → App {
    = . app body_limit max_bytes
    ^ app
}

@ app_with_idle_timeout App app i ms → App {
    = . app idle_timeout_ms ms
    ^ app
}

@ app_with_workers App app i n → App {
    = . app workers n
    ^ app
}

@ app_with_pretty_errors App app → App {
    = . app pretty_errors T
    ^ app
}

@ app_static App app s dir → v {
    ( string_free . app static_dir )
    = . app static_dir ( string_from dir )
}

@ app_count App app → i {
    ^ ( router_count . app router )
}

// ── Middleware registration ──────────────────────────────────────────

@ app_use App app ( @ b Ctx ) mw → v {
    : *MwSlotImpl impl # *MwSlotImpl ( nurl_alloc Z MwSlotImpl )
    = . impl mw mw
    = . impl next # s 0
    ( vec_push [s] . app mw_chain # s impl )
}

// ── Internal: build the full handler closure ─────────────────────────
//
// Takes the App's router + middleware chain + config, produces a
// `( @ HttpResponse HttpRequest )` that the server can use.
// The closure:
//   1. Creates a Ctx from the HttpRequest
//   2. Runs middleware chain (if any)
//   3. If not responded, dispatches through the router
//   4. If still not responded, returns 404
//   5. Returns the response from the Ctx

@ __app_dispatch HttpRequest req Params params App app → HttpResponse {
    : i blimit . app body_limit
    ? == blimit 0 { = blimit 10485760 } {}  // default 10 MB

    : Ctx ctx ( __ctx_new req params blimit )

    // Run middleware chain.
    : i n_mw ( vec_len [s] . app mw_chain )
    : ~ b proceed T
    : ~ i mi 0
    ~ & proceed < mi n_mw {
        : s slot_p ?? ( vec_get [s] . app mw_chain mi ) { T p → p F → # s 0 }
        : i slot_raw # i slot_p
        ? != slot_raw 0 {
            : *MwSlotImpl impl # *MwSlotImpl slot_p
            : ( @ b Ctx ) f . impl mw
            : b ok ( f ctx )
            ? == ok 0 { = proceed F } {}
        } {}
        = mi + mi 1
    }

    // If middleware didn't abort, dispatch through router.
    ? proceed {
        ? != . ctx responded T {} {
            // Router dispatch — create a wrapper handler that writes into Ctx.
            : HttpResponse routed ( router_handle . app router req )
            ( __ctx_set_resp ctx routed )
        }
    } {}

    // Extract the response from the Ctx.
    : s rp . ctx resp
    : i raw # i rp
    ? != raw 0 {
        : s hp # s rp
        : HttpResponse final @ HttpResponse { hp }
        = . ctx resp # s 0
        = . ctx responded F
        ^ final
    } {
        ^ ( response_text 404 `not found\n` )
    }
}

// ── Route registration (App-level) ───────────────────────────────────
//
// Each route registers a wrapper closure on the router that converts
// between the Ctx-based handler and the raw HttpRequest/Params/HttpResponse
// contract the router expects.

@ __register_route App app s method s pattern ( @ v Ctx ) handler → v {
    // The handler closure captures `app` and `handler` by value.
    // On dispatch it creates a Ctx, calls handler, then extracts
    // the response.
    ( router_any . app router method pattern
    \ HttpRequest req Params params → HttpResponse {
        : i blimit . app body_limit
        ? == blimit 0 { = blimit 10485760 } {}

        : Ctx ctx ( __ctx_new req params blimit )

        // Run app-level middleware.
        : i n_mw ( vec_len [s] . app mw_chain )
        : ~ b proceed T
        : ~ i mi 0
        ~ & proceed < mi n_mw {
            : s slot_p ?? ( vec_get [s] . app mw_chain mi ) { T p → p F → # s 0 }
            : i slot_raw # i slot_p
            ? != slot_raw 0 {
                : *MwSlotImpl impl # *MwSlotImpl slot_p
                : ( @ b Ctx ) f . impl mw
                : b ok ( f ctx )
                ? == ok 0 { = proceed F } {}
            } {}
            = mi + mi 1
        }

        // If middleware passed, call the handler.
        ? proceed {
            ( handler ctx )
        } {}

        // Extract response.
        : s rp . ctx resp
        : i rraw # i rp
        ? != rraw 0 {
            : s hp # s rp
            : HttpResponse r @ HttpResponse { hp }
            = . ctx resp # s 0
            = . ctx responded F
            ^ r
        } {
            ^ ( response_text 500 `handler did not produce a response\n` )
        }
    } )
}

@ app_get App app s pattern ( @ v Ctx ) handler → v {
    ( __register_route app `GET` pattern handler )
}

@ app_post App app s pattern ( @ v Ctx ) handler → v {
    ( __register_route app `POST` pattern handler )
}

@ app_put App app s pattern ( @ v Ctx ) handler → v {
    ( __register_route app `PUT` pattern handler )
}

@ app_patch App app s pattern ( @ v Ctx ) handler → v {
    ( __register_route app `PATCH` pattern handler )
}

@ app_delete App app s pattern ( @ v Ctx ) handler → v {
    ( __register_route app `DELETE` pattern handler )
}

// ── Route groups ─────────────────────────────────────────────────────
//
// A Group is a scoped prefix with its own middleware. Routes registered
// on the group have the prefix prepended. Group middleware runs after
// app-level middleware but before the group's handlers.

@ app_group App app s prefix → Group {
    : *GroupImpl gi # *GroupImpl ( nurl_alloc Z GroupImpl )
    = . gi app app
    = . gi prefix ( string_from prefix )
    = . gi mw_list ( vec_new [s] )
    ^ @ Group { # s gi }
}

@ group_use Group g ( @ b Ctx ) mw → v {
    : *GroupImpl gi # *GroupImpl . g ctl
    : *MwSlotImpl impl # *MwSlotImpl ( nurl_alloc Z MwSlotImpl )
    = . impl mw mw
    = . impl next # s 0
    ( vec_push [s] . gi mw_list # s impl )
}

// Join group prefix + route pattern.
@ __group_path Group g s pattern → String {
    : *GroupImpl gi # *GroupImpl . g ctl
    : s pfx ( string_data . gi prefix )
    : i plen ( nurl_str_len pfx )
    : i slen ( nurl_str_len pattern )
    // Drop trailing slash from prefix if pattern starts with /
    : ~ i drop 0
    ? & > plen 0 == ( nurl_str_get pfx - plen 1 ) 47 { = drop 1 } {}
    : ~ i start 0
    ? & > slen 0 == ( nurl_str_get pattern 0 ) 47 { = start 1 } {}

    : String path ( string_with_cap + plen slen 1 )
    : ~ i k 0
    ~ < k - plen drop { ( string_push_char path ( nurl_str_get pfx k ) ) = k + k 1 }
    = k start
    ~ < k slen { ( string_push_char path ( nurl_str_get pattern k ) ) = k + k 1 }
    ^ path
}

@ __group_register Group g s method s pattern ( @ v Ctx ) handler → v {
    : *GroupImpl gi # *GroupImpl . g ctl
    : String full_path ( __group_path g pattern )
    : App app . gi app
    : ( Vec s ) gmw . gi mw_list
    : i n_gmw ( vec_len [s] gmw )

    ( router_any . app router method ( string_data full_path )
    \ HttpRequest req Params params → HttpResponse {
        : i blimit . app body_limit
        ? == blimit 0 { = blimit 10485760 } {}

        : Ctx ctx ( __ctx_new req params blimit )

        // App-level middleware.
        : i n_mw ( vec_len [s] . app mw_chain )
        : ~ b proceed T
        : ~ i mi 0
        ~ & proceed < mi n_mw {
            : s slot_p ?? ( vec_get [s] . app mw_chain mi ) { T p → p F → # s 0 }
            : i slot_raw # i slot_p
            ? != slot_raw 0 {
                : *MwSlotImpl impl # *MwSlotImpl slot_p
                : ( @ b Ctx ) f . impl mw
                : b ok ( f ctx )
                ? == ok 0 { = proceed F } {}
            } {}
            = mi + mi 1
        }

        // Group-level middleware.
        ? proceed {
            : ~ i gi2 0
            ~ & proceed < gi2 n_gmw {
                : s slot_p ?? ( vec_get [s] gmw gi2 ) { T p → p F → # s 0 }
                : i slot_raw # i slot_p
                ? != slot_raw 0 {
                    : *MwSlotImpl impl # *MwSlotImpl slot_p
                    : ( @ b Ctx ) f . impl mw
                    : b ok ( f ctx )
                    ? == ok 0 { = proceed F } {}
                } {}
                = gi2 + gi2 1
            }
        } {}

        ? proceed { ( handler ctx ) } {}

        : s rp . ctx resp
        : i rraw # i rp
        ? != rraw 0 {
            : s hp # s rp
            : HttpResponse r @ HttpResponse { hp }
            = . ctx resp # s 0
            = . ctx responded F
            ^ r
        } {
            ^ ( response_text 500 `handler did not produce a response\n` )
        }
    } )
    ( string_free full_path )
}

@ group_get Group g s pattern ( @ v Ctx ) handler → v {
    ( __group_register g `GET` pattern handler )
}

@ group_post Group g s pattern ( @ v Ctx ) handler → v {
    ( __group_register g `POST` pattern handler )
}

@ group_put Group g s pattern ( @ v Ctx ) handler → v {
    ( __group_register g `PUT` pattern handler )
}

@ group_patch Group g s pattern ( @ v Ctx ) handler → v {
    ( __group_register g `PATCH` pattern handler )
}

@ group_delete Group g s pattern ( @ v Ctx ) handler → v {
    ( __group_register g `DELETE` pattern handler )
}

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
//
// If `app_static` was called, register a catch-all GET route that
// serves files from the configured directory.

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
                    // No path param — serve index.html
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

// ── app_run ──────────────────────────────────────────────────────────
//
// The main entry point. Wires up all the pieces and starts the server.

@ app_run App app s host i port → i {
    // Register static route if configured.
    ( __register_static app )

    // Run on_start hooks.
    ( __run_hooks . app on_start_hooks )

    // Build the base handler that dispatches through the router.
    : ( @ HttpResponse HttpRequest ) base
    \ HttpRequest req → HttpResponse {
        // Use manual_dispatch-style routing: create empty params,
        // let router_handle do the dispatch.
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
            ? == timeout 0 { = timeout 30000 } {}

            : i wk . app workers
            ? == wk 0 { = wk 16 } {}

            ( nurl_print `[nurl-app] listening on http://` )
            ( nurl_print host )
            ( nurl_print `:` )
            ( nurl_print ( nurl_str_int port ) )
            ( nurl_print `/  routes=` )
            ( nurl_print ( nurl_str_int ( router_count . app router ) ) )
            ( nurl_print `  workers=` )
            ( nurl_print ( nurl_str_int wk ) )
            ( nurl_print `\n` )

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
