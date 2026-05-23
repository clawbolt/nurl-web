// test/test_ctx_response.nu — tests for Ctx response builders

$ `test/test_helpers.nu`

// Test: ctx_text sets status and body
@ test_ctx_text → i {
    : HttpRequest req ( __make_test_request `GET` `/` `` )
    : Params params ( __make_params )
    : Ctx ctx ( __ctx_new req params # s 0 0 1 )
    ( ctx_text ctx 200 `hello world` )
    : HttpResponse resp ( ctx_respond ctx )
    : *HttpResponseImpl ri # *HttpResponseImpl . resp raw
    : i rc ( __check_eq_i . ri status 200 `ctx_text: status 200` )
    ( http_response_free resp )
    ( __ctx_free ctx )
    ( string_free . req method ) ( string_free . req path ) ( string_free . req query )
    ( vec_free [QueryPair] . params pairs )
    ^ rc
}

// Test: ctx_json_str sets Content-Type
@ test_ctx_json_str → i {
    : HttpRequest req ( __make_test_request `GET` `/` `` )
    : Params params ( __make_params )
    : Ctx ctx ( __ctx_new req params # s 0 0 1 )
    ( ctx_json_str ctx 200 `{"ok":true}` )
    : HttpResponse resp ( ctx_respond ctx )
    : *HttpResponseImpl ri # *HttpResponseImpl . resp raw
    : i rc ( __check_eq_i . ri status 200 `ctx_json_str: status 200` )
    ( http_response_free resp )
    ( __ctx_free ctx )
    ( string_free . req method ) ( string_free . req path ) ( string_free . req query )
    ( vec_free [QueryPair] . params pairs )
    ^ rc
}

// Test: ctx_status with 204
@ test_ctx_status → i {
    : HttpRequest req ( __make_test_request `GET` `/` `` )
    : Params params ( __make_params )
    : Ctx ctx ( __ctx_new req params # s 0 0 1 )
    ( ctx_status ctx 204 )
    : HttpResponse resp ( ctx_respond ctx )
    : *HttpResponseImpl ri # *HttpResponseImpl . resp raw
    : i rc ( __check_eq_i . ri status 204 `ctx_status: status 204` )
    ( http_response_free resp )
    ( __ctx_free ctx )
    ( string_free . req method ) ( string_free . req path ) ( string_free . req query )
    ( vec_free [QueryPair] . params pairs )
    ^ rc
}

// Test: ctx_redirect sets status
@ test_ctx_redirect → i {
    : HttpRequest req ( __make_test_request `GET` `/` `` )
    : Params params ( __make_params )
    : Ctx ctx ( __ctx_new req params # s 0 0 1 )
    ( ctx_redirect ctx 302 `/other` )
    : HttpResponse resp ( ctx_respond ctx )
    : *HttpResponseImpl ri # *HttpResponseImpl . resp raw
    : i rc ( __check_eq_i . ri status 302 `ctx_redirect: status 302` )
    ( http_response_free resp )
    ( __ctx_free ctx )
    ( string_free . req method ) ( string_free . req path ) ( string_free . req query )
    ( vec_free [QueryPair] . params pairs )
    ^ rc
}

// Test: ctx_respond returns 204 when no response set
@ test_ctx_respond_no_response → i {
    : HttpRequest req ( __make_test_request `GET` `/` `` )
    : Params params ( __make_params )
    : Ctx ctx ( __ctx_new req params # s 0 0 1 )
    : HttpResponse resp ( ctx_respond ctx )
    : *HttpResponseImpl ri # *HttpResponseImpl . resp raw
    : i rc ( __check_eq_i . ri status 204 `ctx_respond: fallback 204` )
    ( http_response_free resp )
    ( __ctx_free ctx )
    ( string_free . req method ) ( string_free . req path ) ( string_free . req query )
    ( vec_free [QueryPair] . params pairs )
    ^ rc
}

// Test: ctx_set_header before response creates pending headers
@ test_ctx_set_header_pending → i {
    : HttpRequest req ( __make_test_request `GET` `/` `` )
    : Params params ( __make_params )
    : Ctx ctx ( __ctx_new req params # s 0 0 1 )
    ( ctx_set_header ctx `X-Custom` `value1` )
    : *CtxImpl impl # *CtxImpl . ctx ctl
    : i rc ( __check_true != 0 # i . impl pending_headers `pending headers allocated` )
    ( __ctx_free ctx )
    ( string_free . req method ) ( string_free . req path ) ( string_free . req query )
    ( vec_free [QueryPair] . params pairs )
    ^ rc
}

// Test: ctx_set_header after response applies directly
@ test_ctx_set_header_direct → i {
    : HttpRequest req ( __make_test_request `GET` `/` `` )
    : Params params ( __make_params )
    : Ctx ctx ( __ctx_new req params # s 0 0 1 )
    ( ctx_text ctx 200 `ok` )
    ( ctx_set_header ctx `X-Direct` `yes` )
    : *CtxImpl impl # *CtxImpl . ctx ctl
    // Pending headers should still be null (applied directly to response)
    : i rc ( __check_true == 0 # i . impl pending_headers `no pending after direct set` )
    ( __ctx_free ctx )
    ( string_free . req method ) ( string_free . req path ) ( string_free . req query )
    ( vec_free [QueryPair] . params pairs )
    ^ rc
}

// Test: pending headers applied when response is set
@ test_ctx_pending_headers_applied → i {
    : HttpRequest req ( __make_test_request `GET` `/` `` )
    : Params params ( __make_params )
    : Ctx ctx ( __ctx_new req params # s 0 0 1 )
    ( ctx_set_header ctx `X-Pending` `before` )
    ( ctx_text ctx 200 `ok` )
    : *CtxImpl impl # *CtxImpl . ctx ctl
    // Pending headers should be cleared after being applied
    : i rc ( __check_true == 0 # i . impl pending_headers `pending cleared after apply` )
    ( __ctx_free ctx )
    ( string_free . req method ) ( string_free . req path ) ( string_free . req query )
    ( vec_free [QueryPair] . params pairs )
    ^ rc
}

// Test: overwrite response (last write wins)
@ test_ctx_overwrite → i {
    : HttpRequest req ( __make_test_request `GET` `/` `` )
    : Params params ( __make_params )
    : Ctx ctx ( __ctx_new req params # s 0 0 1 )
    ( ctx_text ctx 200 `first` )
    ( ctx_text ctx 404 `second` )
    : HttpResponse resp ( ctx_respond ctx )
    : *HttpResponseImpl ri # *HttpResponseImpl . resp raw
    : i rc ( __check_eq_i . ri status 404 `overwrite: last write wins` )
    ( http_response_free resp )
    ( __ctx_free ctx )
    ( string_free . req method ) ( string_free . req path ) ( string_free . req query )
    ( vec_free [QueryPair] . params pairs )
    ^ rc
}

@ main → i {
    ( nurl_print `test_ctx_response:\n` )
    : ~ i failures 0
    = failures + failures ( test_ctx_text )
    = failures + failures ( test_ctx_json_str )
    = failures + failures ( test_ctx_status )
    = failures + failures ( test_ctx_redirect )
    = failures + failures ( test_ctx_respond_no_response )
    = failures + failures ( test_ctx_set_header_pending )
    = failures + failures ( test_ctx_set_header_direct )
    = failures + failures ( test_ctx_pending_headers_applied )
    = failures + failures ( test_ctx_overwrite )
    ? == failures 0 {
        ( nurl_print `  ALL PASSED\n` )
    } {
        ( nurl_eprint `  ` )
        ( nurl_eprint ( nurl_str_int failures ) )
        ( nurl_eprint ` tests failed\n` )
    }
    ^ failures
}
