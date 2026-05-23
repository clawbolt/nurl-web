// test/test_ctx_lifecycle.nu — tests for __ctx_new and __ctx_free

$ `test/test_helpers.nu`

// Test: __ctx_new creates Ctx with null response
@ test_ctx_new_null_resp → i {
    : HttpRequest req ( __make_test_request `GET` `/` `` )
    : Params params ( __make_params )
    : Ctx ctx ( __ctx_new req params # s 0 0 1 )
    : *CtxImpl impl # *CtxImpl . ctx ctl

    : i rc ( __check_true == 0 # i . impl resp `ctx_new: resp is null` )
    ( __ctx_free ctx )
    ( string_free . req method ) ( string_free . req path ) ( string_free . req query )
    ( vec_free [QueryPair] . params pairs )
    ^ rc
}

// Test: __ctx_new sets hijacked = false
@ test_ctx_new_not_hijacked → i {
    : HttpRequest req ( __make_test_request `GET` `/` `` )
    : Params params ( __make_params )
    : Ctx ctx ( __ctx_new req params # s 0 0 1 )
    : *CtxImpl impl # *CtxImpl . ctx ctl

    : i rc ( __check_false . impl hijacked `ctx_new: not hijacked` )
    ( __ctx_free ctx )
    ( string_free . req method ) ( string_free . req path ) ( string_free . req query )
    ( vec_free [QueryPair] . params pairs )
    ^ rc
}

// Test: __ctx_new sets pending_headers = null
@ test_ctx_new_no_pending_headers → i {
    : HttpRequest req ( __make_test_request `GET` `/` `` )
    : Params params ( __make_params )
    : Ctx ctx ( __ctx_new req params # s 0 0 1 )
    : *CtxImpl impl # *CtxImpl . ctx ctl

    : i rc ( __check_true == 0 # i . impl pending_headers `ctx_new: no pending headers` )
    ( __ctx_free ctx )
    ( string_free . req method ) ( string_free . req path ) ( string_free . req query )
    ( vec_free [QueryPair] . params pairs )
    ^ rc
}

// Test: __ctx_free on fresh Ctx (no response) does not crash
@ test_ctx_free_fresh → i {
    : HttpRequest req ( __make_test_request `GET` `/` `` )
    : Params params ( __make_params )
    : Ctx ctx ( __ctx_new req params # s 0 0 1 )
    ( __ctx_free ctx )
    ( string_free . req method ) ( string_free . req path ) ( string_free . req query )
    ( vec_free [QueryPair] . params pairs )
    ( nurl_print `  PASS: ctx_free on fresh Ctx\n` )
    ^ 0
}

// Test: __ctx_free after ctx_text does not crash
@ test_ctx_free_after_response → i {
    : HttpRequest req ( __make_test_request `GET` `/` `` )
    : Params params ( __make_params )
    : Ctx ctx ( __ctx_new req params # s 0 0 1 )
    ( ctx_text ctx 200 `hello` )
    : *CtxImpl impl # *CtxImpl . ctx ctl
    : i rc ( __check_true != 0 # i . impl resp `ctx_text set response` )
    ( __ctx_free ctx )
    ( string_free . req method ) ( string_free . req path ) ( string_free . req query )
    ( vec_free [QueryPair] . params pairs )
    ^ rc
}

// Test: __ctx_free after pending headers does not crash
@ test_ctx_free_after_pending_headers → i {
    : HttpRequest req ( __make_test_request `GET` `/` `` )
    : Params params ( __make_params )
    : Ctx ctx ( __ctx_new req params # s 0 0 1 )
    ( ctx_set_header ctx `X-Test` `value` )
    : *CtxImpl impl # *CtxImpl . ctx ctl
    : i rc ( __check_true != 0 # i . impl pending_headers `pending header allocated` )
    ( __ctx_free ctx )
    ( string_free . req method ) ( string_free . req path ) ( string_free . req query )
    ( vec_free [QueryPair] . params pairs )
    ^ rc
}

// Test: __ctx_free after both response and pending headers
@ test_ctx_free_full → i {
    : HttpRequest req ( __make_test_request `GET` `/` `` )
    : Params params ( __make_params )
    : Ctx ctx ( __ctx_new req params # s 0 0 1 )
    ( ctx_set_header ctx `X-Test` `value` )
    ( ctx_text ctx 200 `hello` )
    ( __ctx_free ctx )
    ( string_free . req method ) ( string_free . req path ) ( string_free . req query )
    ( vec_free [QueryPair] . params pairs )
    ( nurl_print `  PASS: ctx_free after response + pending headers\n` )
    ^ 0
}

// Test: setting response twice frees the old one
@ test_ctx_overwrite_response → i {
    : HttpRequest req ( __make_test_request `GET` `/` `` )
    : Params params ( __make_params )
    : Ctx ctx ( __ctx_new req params # s 0 0 1 )
    ( ctx_text ctx 200 `first` )
    ( ctx_text ctx 404 `second` )
    : HttpResponse resp ( ctx_respond ctx )
    : *HttpResponseImpl ri # *HttpResponseImpl . resp raw
    // Status should be 404 (second call overwrites)
    : i rc ( __check_eq_i . ri status 404 `overwrite: status is 404` )
    ( http_response_free resp )
    ( __ctx_free ctx )
    ( string_free . req method ) ( string_free . req path ) ( string_free . req query )
    ( vec_free [QueryPair] . params pairs )
    ^ rc
}

@ main → i {
    ( nurl_print `test_ctx_lifecycle:\n` )
    : ~ i failures 0
    = failures + failures ( test_ctx_new_null_resp )
    = failures + failures ( test_ctx_new_not_hijacked )
    = failures + failures ( test_ctx_new_no_pending_headers )
    = failures + failures ( test_ctx_free_fresh )
    = failures + failures ( test_ctx_free_after_response )
    = failures + failures ( test_ctx_free_after_pending_headers )
    = failures + failures ( test_ctx_free_full )
    = failures + failures ( test_ctx_overwrite_response )
    ? == failures 0 {
        ( nurl_print `  ALL PASSED\n` )
    } {
        ( nurl_eprint `  ` )
        ( nurl_eprint ( nurl_str_int failures ) )
        ( nurl_eprint ` tests failed\n` )
    }
    ^ failures
}
