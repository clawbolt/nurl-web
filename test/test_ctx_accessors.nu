// test/test_ctx_accessors.nu — tests for all 12 Ctx request accessors

$ `test/test_helpers.nu`

// Helper: create a Ctx from a request, run a test function, then clean up.
// The test function receives the Ctx and returns 0/1.
// We handle request/params cleanup here.
@ __with_ctx HttpRequest req Params params ( @ i Ctx ) test_fn → i {
    : Ctx ctx ( __ctx_new req params # s 0 0 1 )
    : i rc ( test_fn ctx )
    ( __ctx_free ctx )
    ^ rc
}

// ── ctx_method ──────────────────────────────────────────────────────

@ test_ctx_method_get → i {
    : HttpRequest req ( __make_test_request `GET` `/hello` `` )
    : Params params ( __make_params )
    : Ctx ctx ( __ctx_new req params # s 0 0 1 )
    : s m ( ctx_method ctx )
    : i rc ( __assert_eq_s m `GET` `ctx_method GET` )
    ( __ctx_free ctx )
    ( string_free . req method ) ( string_free . req path ) ( string_free . req query )
    ( vec_free [QueryPair] . params pairs )
    ^ rc
}

@ test_ctx_method_post → i {
    : HttpRequest req ( __make_test_request `POST` `/data` `` )
    : Params params ( __make_params )
    : Ctx ctx ( __ctx_new req params # s 0 0 1 )
    : s m ( ctx_method ctx )
    : i rc ( __assert_eq_s m `POST` `ctx_method POST` )
    ( __ctx_free ctx )
    ( string_free . req method ) ( string_free . req path ) ( string_free . req query )
    ( vec_free [QueryPair] . params pairs )
    ^ rc
}

// ── ctx_path ────────────────────────────────────────────────────────

@ test_ctx_path → i {
    : HttpRequest req ( __make_test_request `GET` `/api/items/123` `` )
    : Params params ( __make_params )
    : Ctx ctx ( __ctx_new req params # s 0 0 1 )
    : s p ( ctx_path ctx )
    : i rc ( __assert_eq_s p `/api/items/123` `ctx_path` )
    ( __ctx_free ctx )
    ( string_free . req method ) ( string_free . req path ) ( string_free . req query )
    ( vec_free [QueryPair] . params pairs )
    ^ rc
}

// ── ctx_query_string ────────────────────────────────────────────────

@ test_ctx_query_string_empty → i {
    : HttpRequest req ( __make_test_request `GET` `/` `` )
    : Params params ( __make_params )
    : Ctx ctx ( __ctx_new req params # s 0 0 1 )
    : s q ( ctx_query_string ctx )
    : i rc ( __assert_eq_s q `` `ctx_query_string empty` )
    ( __ctx_free ctx )
    ( string_free . req method ) ( string_free . req path ) ( string_free . req query )
    ( vec_free [QueryPair] . params pairs )
    ^ rc
}

@ test_ctx_query_string_present → i {
    : HttpRequest req ( __make_test_request `GET` `/search` `q=hello&page=2` )
    : Params params ( __make_params )
    : Ctx ctx ( __ctx_new req params # s 0 0 1 )
    : s q ( ctx_query_string ctx )
    : i rc ( __assert_eq_s q `q=hello&page=2` `ctx_query_string present` )
    ( __ctx_free ctx )
    ( string_free . req method ) ( string_free . req path ) ( string_free . req query )
    ( vec_free [QueryPair] . params pairs )
    ^ rc
}

// ── ctx_param ───────────────────────────────────────────────────────

@ test_ctx_param_present → i {
    : HttpRequest req ( __make_test_request `GET` `/hello/world` `` )
    : Params params ( __make_params )
    ( __add_param params `name` `world` )
    : Ctx ctx ( __ctx_new req params # s 0 0 1 )
    : ? String result ( ctx_param ctx `name` )
    ?? result {
        T val → {
            : i rc ( __assert_eq_s ( string_data val ) `world` `ctx_param present` )
            ( string_free val )
            ( __ctx_free ctx )
            ( string_free . req method ) ( string_free . req path ) ( string_free . req query )
            ^ rc
        }
        F _ → {
            ( __ctx_free ctx )
            ( string_free . req method ) ( string_free . req path ) ( string_free . req query )
            ( nurl_eprint `FAIL: ctx_param present — got null\n` )
            ^ 1
        }
    }
}

@ test_ctx_param_absent → i {
    : HttpRequest req ( __make_test_request `GET` `/` `` )
    : Params params ( __make_params )
    : Ctx ctx ( __ctx_new req params # s 0 0 1 )
    : ? String result ( ctx_param ctx `nonexistent` )
    : i rc
    ?? result {
        T val → {
            ( string_free val )
            ( __ctx_free ctx )
            ( string_free . req method ) ( string_free . req path ) ( string_free . req query )
            ( nurl_eprint `FAIL: ctx_param absent — expected null, got value\n` )
            = rc 1
        }
        F _ → {
            ( string_free _ )
            ( __ctx_free ctx )
            ( string_free . req method ) ( string_free . req path ) ( string_free . req query )
            ( nurl_print `  PASS: ctx_param absent\n` )
            = rc 0
        }
    }
    ^ rc
}

// ── ctx_body_string ─────────────────────────────────────────────────

@ test_ctx_body_string_empty → i {
    : HttpRequest req ( __make_test_request `GET` `/` `` )
    : Params params ( __make_params )
    : Ctx ctx ( __ctx_new req params # s 0 0 1 )
    : String body ( ctx_body_string ctx )
    : i rc ( __assert_eq_s ( string_data body ) `` `ctx_body_string empty` )
    ( string_free body )
    ( __ctx_free ctx )
    ( string_free . req method ) ( string_free . req path ) ( string_free . req query )
    ( vec_free [QueryPair] . params pairs )
    ^ rc
}

@ test_ctx_body_string_content → i {
    : HttpRequest req ( __make_request_with_body `POST` `/echo` `` `{"hello":"world"}` )
    : Params params ( __make_params )
    : Ctx ctx ( __ctx_new req params # s 0 0 1 )
    : String body ( ctx_body_string ctx )
    : i rc ( __assert_eq_s ( string_data body ) `{"hello":"world"}` `ctx_body_string content` )
    ( string_free body )
    ( __ctx_free ctx )
    ( string_free . req method ) ( string_free . req path ) ( string_free . req query )
    ( vec_free [QueryPair] . params pairs )
    ^ rc
}

// ── ctx_header ──────────────────────────────────────────────────────

@ test_ctx_header_present → i {
    : HttpRequest req ( __make_request_with_header `GET` `/` `` `X-Test` `hello` )
    : Params params ( __make_params )
    : Ctx ctx ( __ctx_new req params # s 0 0 1 )
    : ? String result ( ctx_header ctx `X-Test` )
    ?? result {
        T val → {
            : i rc ( __assert_eq_s ( string_data val ) `hello` `ctx_header present` )
            ( string_free val )
            ( __ctx_free ctx )
            ( string_free . req method ) ( string_free . req path ) ( string_free . req query )
            ^ rc
        }
        F _ → {
            ( __ctx_free ctx )
            ( string_free . req method ) ( string_free . req path ) ( string_free . req query )
            ( nurl_eprint `FAIL: ctx_header present — got null\n` )
            ^ 1
        }
    }
}

@ test_ctx_header_absent → i {
    : HttpRequest req ( __make_test_request `GET` `/` `` )
    : Params params ( __make_params )
    : Ctx ctx ( __ctx_new req params # s 0 0 1 )
    : ? String result ( ctx_header ctx `X-Missing` )
    : i rc
    ?? result {
        T val → {
            ( string_free val )
            ( __ctx_free ctx )
            ( string_free . req method ) ( string_free . req path ) ( string_free . req query )
            ( nurl_eprint `FAIL: ctx_header absent — expected null\n` )
            = rc 1
        }
        F _ → {
            ( string_free _ )
            ( __ctx_free ctx )
            ( string_free . req method ) ( string_free . req path ) ( string_free . req query )
            ( nurl_print `  PASS: ctx_header absent\n` )
            = rc 0
        }
    }
    ^ rc
}

// ── main ────────────────────────────────────────────────────────────

@ main → i {
    ( nurl_print `test_ctx_accessors:\n` )
    : ~ i failures 0
    = failures + failures ( test_ctx_method_get )
    = failures + failures ( test_ctx_method_post )
    = failures + failures ( test_ctx_path )
    = failures + failures ( test_ctx_query_string_empty )
    = failures + failures ( test_ctx_query_string_present )
    = failures + failures ( test_ctx_param_present )
    = failures + failures ( test_ctx_param_absent )
    = failures + failures ( test_ctx_body_string_empty )
    = failures + failures ( test_ctx_body_string_content )
    = failures + failures ( test_ctx_header_present )
    = failures + failures ( test_ctx_header_absent )
    ? == failures 0 {
        ( nurl_print `  ALL PASSED\n` )
    } {
        ( nurl_eprint `  ` )
        ( nurl_eprint ( nurl_str_int failures ) )
        ( nurl_eprint ` tests failed\n` )
    }
    ^ failures
}
