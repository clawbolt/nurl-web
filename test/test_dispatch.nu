// test/test_dispatch.nu — tests for __dispatch (core request processing pipeline)

$ `test/test_helpers.nu`

// Test: basic dispatch, handler sets 200
@ test_dispatch_basic_200 → i {
    : App app ( app_new )
    : HttpRequest req ( __make_test_request `GET` `/` `` )
    : Params params ( __make_params )
    : HttpResponse resp ( __dispatch req params app ( vec_new [s] ) ( vec_new [s] )
        \ Ctx ctx → v { ( ctx_text ctx 200 `ok` ) } )
    : *HttpResponseImpl ri # *HttpResponseImpl . resp raw
    : i rc ( __check_eq_i . ri status 200 `dispatch: basic 200` )
    ( http_response_free resp )
    ( string_free . req method ) ( string_free . req path ) ( string_free . req query )
    ( app_free app )
    ^ rc
}

// Test: no response set → 500
@ test_dispatch_no_response → i {
    : App app ( app_new )
    : HttpRequest req ( __make_test_request `GET` `/` `` )
    : Params params ( __make_params )
    : HttpResponse resp ( __dispatch req params app ( vec_new [s] ) ( vec_new [s] )
        \ Ctx ctx → v { } )
    : *HttpResponseImpl ri # *HttpResponseImpl . resp raw
    : i rc ( __check_eq_i . ri status 500 `dispatch: no response → 500` )
    ( http_response_free resp )
    ( string_free . req method ) ( string_free . req path ) ( string_free . req query )
    ( app_free app )
    ^ rc
}

// Test: middleware passes → handler runs
@ test_dispatch_mw_pass → i {
    : App app ( app_new )
    : HttpRequest req ( __make_test_request `GET` `/` `` )
    : Params params ( __make_params )
    // Create middleware that returns T
    : *MwEntryImpl mw_impl # *MwEntryImpl ( nurl_alloc Z MwEntryImpl )
    = . mw_impl mw \ Ctx c → b { ^ T }
    : ( Vec s ) mw ( vec_new [s] )
    ( vec_push [s] mw # s mw_impl )
    : HttpResponse resp ( __dispatch req params app mw ( vec_new [s] )
        \ Ctx ctx → v { ( ctx_text ctx 200 `passed` ) } )
    : *HttpResponseImpl ri # *HttpResponseImpl . resp raw
    : i rc ( __check_eq_i . ri status 200 `dispatch: mw pass → handler runs` )
    ( http_response_free resp )
    ( string_free . req method ) ( string_free . req path ) ( string_free . req query )
    ( vec_free [s] mw )
    ( app_free app )
    ^ rc
}

// Test: middleware aborts → handler not called, middleware response used
@ test_dispatch_mw_abort → i {
    : App app ( app_new )
    : HttpRequest req ( __make_test_request `GET` `/` `` )
    : Params params ( __make_params )
    : *MwEntryImpl mw_impl # *MwEntryImpl ( nurl_alloc Z MwEntryImpl )
    = . mw_impl mw \ Ctx c → b {
        ( ctx_text c 401 `unauthorized\n` )
        ^ F
    }
    : ( Vec s ) mw ( vec_new [s] )
    ( vec_push [s] mw # s mw_impl )
    : HttpResponse resp ( __dispatch req params app mw ( vec_new [s] )
        \ Ctx ctx → v { ( ctx_text ctx 200 `should not run` ) } )
    : *HttpResponseImpl ri # *HttpResponseImpl . resp raw
    : i rc ( __check_eq_i . ri status 401 `dispatch: mw abort → 401` )
    ( http_response_free resp )
    ( string_free . req method ) ( string_free . req path ) ( string_free . req query )
    ( vec_free [s] mw )
    ( app_free app )
    ^ rc
}

// Test: body limit exceeded → 413
@ test_dispatch_body_limit → i {
    : App app ( app_new )
    ( app_with_body_limit app 5 )
    : HttpRequest req ( __make_request_with_body `POST` `/data` `` `hello world this is too long` )
    : Params params ( __make_params )
    : HttpResponse resp ( __dispatch req params app ( vec_new [s] ) ( vec_new [s] )
        \ Ctx ctx → v { ( ctx_text ctx 200 `ok` ) } )
    : *HttpResponseImpl ri # *HttpResponseImpl . resp raw
    : i rc ( __check_eq_i . ri status 413 `dispatch: body limit → 413` )
    ( http_response_free resp )
    ( string_free . req method ) ( string_free . req path ) ( string_free . req query )
    ( app_free app )
    ^ rc
}

// Test: body within limit → handler runs normally
@ test_dispatch_body_within_limit → i {
    : App app ( app_new )
    ( app_with_body_limit app 1000 )
    : HttpRequest req ( __make_request_with_body `POST` `/data` `` `short` )
    : Params params ( __make_params )
    : HttpResponse resp ( __dispatch req params app ( vec_new [s] ) ( vec_new [s] )
        \ Ctx ctx → v { ( ctx_text ctx 200 `ok` ) } )
    : *HttpResponseImpl ri # *HttpResponseImpl . resp raw
    : i rc ( __check_eq_i . ri status 200 `dispatch: body within limit → 200` )
    ( http_response_free resp )
    ( string_free . req method ) ( string_free . req path ) ( string_free . req query )
    ( app_free app )
    ^ rc
}

// Test: params accessible through dispatch
@ test_dispatch_with_params → i {
    : App app ( app_new )
    : HttpRequest req ( __make_test_request `GET` `/hello/world` `` )
    : Params params ( __make_params )
    ( __add_param params `name` `world` )
    : ~ s captured_name ``
    : HttpResponse resp ( __dispatch req params app ( vec_new [s] ) ( vec_new [s] )
        \ Ctx ctx → v {
            : ? String n ( ctx_param ctx `name` )
            ?? n { T v → { = captured_name ( string_data v ) ( string_free v ) } F _ → {} }
        } )
    : i rc ( __check_true != 0 ( nurl_str_eq captured_name `world` ) `dispatch: params accessible` )
    ( http_response_free resp )
    ( string_free . req method ) ( string_free . req path ) ( string_free . req query )
    ( app_free app )
    ^ rc
}

// Test: request ID increments on consecutive dispatches
@ test_dispatch_request_id → i {
    : App app ( app_new )
    : HttpRequest req1 ( __make_test_request `GET` `/` `` )
    : Params params1 ( __make_params )
    : HttpResponse resp1 ( __dispatch req1 params1 app ( vec_new [s] ) ( vec_new [s] )
        \ Ctx ctx → v { ( ctx_text ctx 200 `ok` ) } )
    ( http_response_free resp1 )
    ( string_free . req1 method ) ( string_free . req1 path ) ( string_free . req1 query )

    : HttpRequest req2 ( __make_test_request `GET` `/` `` )
    : Params params2 ( __make_params )
    : HttpResponse resp2 ( __dispatch req2 params2 app ( vec_new [s] ) ( vec_new [s] )
        \ Ctx ctx → v { ( ctx_text ctx 200 `ok` ) } )
    ( http_response_free resp2 )

    : i rc ( __check_eq_i . app next_request_id 2 `dispatch: request_id incremented` )
    ( string_free . req2 method ) ( string_free . req2 path ) ( string_free . req2 query )
    ( app_free app )
    ^ rc
}

@ main → i {
    ( nurl_print `test_dispatch:\n` )
    : ~ i failures 0
    = failures + failures ( test_dispatch_basic_200 )
    = failures + failures ( test_dispatch_no_response )
    = failures + failures ( test_dispatch_mw_pass )
    = failures + failures ( test_dispatch_mw_abort )
    = failures + failures ( test_dispatch_body_limit )
    = failures + failures ( test_dispatch_body_within_limit )
    = failures + failures ( test_dispatch_with_params )
    = failures + failures ( test_dispatch_request_id )
    ? == failures 0 {
        ( nurl_print `  ALL PASSED\n` )
    } {
        ( nurl_eprint `  ` )
        ( nurl_eprint ( nurl_str_int failures ) )
        ( nurl_eprint ` tests failed\n` )
    }
    ^ failures
}
