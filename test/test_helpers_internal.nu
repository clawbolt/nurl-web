// test/test_helpers_internal.nu — tests for __body_to_string, __search_pair, __group_path, __walk_mw

$ `test/test_helpers.nu`

// ── __body_to_string ────────────────────────────────────────────────

@ test_body_to_string_empty → i {
    : HttpRequest req ( __make_test_request `GET` `/` `` )
    : String result ( __body_to_string req )
    : i rc ( __check_eq_i ( string_len result ) 0 `body_to_string: empty body` )
    ( string_free result )
    ( string_free . req method ) ( string_free . req path ) ( string_free . req query )
    ^ rc
}

@ test_body_to_string_content → i {
    : HttpRequest req ( __make_request_with_body `POST` `/` `` `hello` )
    : String result ( __body_to_string req )
    : i rc ( __check_true != 0 ( nurl_str_eq ( string_data result ) `hello` ) `body_to_string: matches content` )
    ( string_free result )
    ( string_free . req method ) ( string_free . req path ) ( string_free . req query )
    ^ rc
}

// ── __search_pair ───────────────────────────────────────────────────

@ test_search_pair_empty → i {
    : ( Vec QueryPair ) pairs ( vec_new [QueryPair] )
    : ? String result ( __search_pair pairs `key` )
    : i rc
    ?? result {
        T val → {
            ( string_free val )
            ( nurl_eprint `FAIL: search_pair empty — expected null\n` )
            = rc 1
        }
        F _ → {
            ( string_free _ )
            ( nurl_print `  PASS: search_pair empty\n` )
            = rc 0
        }
    }
    ( vec_free [QueryPair] pairs )
    ^ rc
}

@ test_search_pair_found → i {
    : ( Vec QueryPair ) pairs ( vec_new [QueryPair] )
    : QueryPair qp @ QueryPair { ( string_from `name` ) ( string_from `alice` ) }
    ( vec_push [QueryPair] pairs qp )
    : ? String result ( __search_pair pairs `name` )
    : i rc
    ?? result {
        T val → {
            = rc ( __check_true != 0 ( nurl_str_eq ( string_data val ) `alice` ) `search_pair: found key` )
            ( string_free val )
        }
        F _ → {
            ( string_free _ )
            ( nurl_eprint `FAIL: search_pair found — got null\n` )
            = rc 1
        }
    }
    ( vec_free [QueryPair] pairs )
    ^ rc
}

@ test_search_pair_not_found → i {
    : ( Vec QueryPair ) pairs ( vec_new [QueryPair] )
    : QueryPair qp @ QueryPair { ( string_from `other` ) ( string_from `val` ) }
    ( vec_push [QueryPair] pairs qp )
    : ? String result ( __search_pair pairs `missing` )
    : i rc
    ?? result {
        T val → {
            ( string_free val )
            ( nurl_eprint `FAIL: search_pair not found — got value\n` )
            = rc 1
        }
        F _ → {
            ( string_free _ )
            ( nurl_print `  PASS: search_pair not found\n` )
            = rc 0
        }
    }
    ( vec_free [QueryPair] pairs )
    ^ rc
}

// ── __group_path ────────────────────────────────────────────────────
// Critical: v0 had a bug where /api + ping produced /apiping

@ test_group_path_no_slashes → i {
    : HttpRequest req ( __make_test_request `GET` `/` `` )
    : Params params ( __make_params )
    : Ctx ctx ( __ctx_new req params # s 0 0 1 )
    // We need a Group to test __group_path
    // Create a minimal app and group
    : App app ( app_new )
    : Group g ( app_group app `/api` )
    : String path ( __group_path g `ping` )
    : i rc ( __check_true != 0 ( nurl_str_eq ( string_data path ) `/api/ping` ) `group_path: /api + ping = /api/ping` )
    ( string_free path )
    ( __ctx_free ctx )
    ( app_free app )
    ( string_free . req method ) ( string_free . req path ) ( string_free . req query )
    ( vec_free [QueryPair] . params pairs )
    ^ rc
}

@ test_group_path_prefix_trailing → i {
    : App app ( app_new )
    : Group g ( app_group app `/api/` )
    : String path ( __group_path g `ping` )
    : i rc ( __check_true != 0 ( nurl_str_eq ( string_data path ) `/api/ping` ) `group_path: /api/ + ping = /api/ping` )
    ( string_free path )
    ( app_free app )
    ^ rc
}

@ test_group_path_pattern_leading → i {
    : App app ( app_new )
    : Group g ( app_group app `/api` )
    : String path ( __group_path g `/ping` )
    : i rc ( __check_true != 0 ( nurl_str_eq ( string_data path ) `/api/ping` ) `group_path: /api + /ping = /api/ping` )
    ( string_free path )
    ( app_free app )
    ^ rc
}

@ test_group_path_both_slashes → i {
    : App app ( app_new )
    : Group g ( app_group app `/api/` )
    : String path ( __group_path g `/ping` )
    : i rc ( __check_true != 0 ( nurl_str_eq ( string_data path ) `/api/ping` ) `group_path: /api/ + /ping = /api/ping` )
    ( string_free path )
    ( app_free app )
    ^ rc
}

@ test_group_path_root_prefix → i {
    : App app ( app_new )
    : Group g ( app_group app `/` )
    : String path ( __group_path g `health` )
    : i rc ( __check_true != 0 ( nurl_str_eq ( string_data path ) `/health` ) `group_path: / + health = /health` )
    ( string_free path )
    ( app_free app )
    ^ rc
}

// ── __walk_mw ───────────────────────────────────────────────────────

@ test_walk_mw_empty → i {
    : ( Vec s ) mw ( vec_new [s] )
    : HttpRequest req ( __make_test_request `GET` `/` `` )
    : Params params ( __make_params )
    : Ctx ctx ( __ctx_new req params # s 0 0 1 )
    : b result ( __walk_mw mw ctx )
    : i rc ( __check_true result `walk_mw: empty returns T` )
    ( __ctx_free ctx )
    ( string_free . req method ) ( string_free . req path ) ( string_free . req query )
    ( vec_free [QueryPair] . params pairs )
    ^ rc
}

@ test_walk_mw_pass → i {
    : App app ( app_new )
    ( app_use app \ Ctx c → b { ^ T } )
    : HttpRequest req ( __make_test_request `GET` `/` `` )
    : Params params ( __make_params )
    : Ctx ctx ( __ctx_new req params # s 0 0 1 )
    : b result ( __walk_mw . app mw_chain ctx )
    : i rc ( __check_true result `walk_mw: single pass returns T` )
    ( __ctx_free ctx )
    ( app_free app )
    ( string_free . req method ) ( string_free . req path ) ( string_free . req query )
    ( vec_free [QueryPair] . params pairs )
    ^ rc
}

@ test_walk_mw_abort → i {
    : App app ( app_new )
    ( app_use app \ Ctx c → b {
        ( ctx_text c 401 `unauthorized\n` )
        ^ F
    } )
    : HttpRequest req ( __make_test_request `GET` `/` `` )
    : Params params ( __make_params )
    : Ctx ctx ( __ctx_new req params # s 0 0 1 )
    : b result ( __walk_mw . app mw_chain ctx )
    : i rc ( __check_false result `walk_mw: abort returns F` )
    ( __ctx_free ctx )
    ( app_free app )
    ( string_free . req method ) ( string_free . req path ) ( string_free . req query )
    ( vec_free [QueryPair] . params pairs )
    ^ rc
}

// ── main ────────────────────────────────────────────────────────────

@ main → i {
    ( nurl_print `test_helpers_internal:\n` )
    : ~ i failures 0
    = failures + failures ( test_body_to_string_empty )
    = failures + failures ( test_body_to_string_content )
    = failures + failures ( test_search_pair_empty )
    = failures + failures ( test_search_pair_found )
    = failures + failures ( test_search_pair_not_found )
    = failures + failures ( test_group_path_no_slashes )
    = failures + failures ( test_group_path_prefix_trailing )
    = failures + failures ( test_group_path_pattern_leading )
    = failures + failures ( test_group_path_both_slashes )
    = failures + failures ( test_group_path_root_prefix )
    = failures + failures ( test_walk_mw_empty )
    = failures + failures ( test_walk_mw_pass )
    = failures + failures ( test_walk_mw_abort )
    ? == failures 0 {
        ( nurl_print `  ALL PASSED\n` )
    } {
        ( nurl_eprint `  ` )
        ( nurl_eprint ( nurl_str_int failures ) )
        ( nurl_eprint ` tests failed\n` )
    }
    ^ failures
}
