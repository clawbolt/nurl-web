// test/test_helpers.nu — assertion and construction utilities for nurl_app tests.
//
// Import this file in each test:
//     $ `test/test_helpers.nu`
//
// Asserts return 0 on pass, 1 on fail. Use in @ main → i to aggregate results.

// ── String assertions ──────────────────────────────────────────────

// Assert two raw strings (s) are equal.
@ __assert_eq_s s got s want s label → i {
    ? != 0 ( nurl_str_eq got want ) {
        ^ 0
    } {
        ( nurl_eprint `FAIL: ` )
        ( nurl_eprint label )
        ( nurl_eprint ` — expected "` )
        ( nurl_eprint want )
        ( nurl_eprint `", got "` )
        ( nurl_eprint got )
        ( nurl_eprint `"\n` )
        ^ 1
    }
}

// Assert two NURL-owned Strings are equal. Frees both after comparison.
@ __assert_eq_String String got String want s label → i {
    : i rc ( __assert_eq_s ( string_data got ) ( string_data want ) label )
    ( string_free got ) ( string_free want )
    ^ rc
}

// ── Integer assertions ──────────────────────────────────────────────

@ __assert_eq_i i got i want s label → i {
    ? == got want {
        ^ 0
    } {
        ( nurl_eprint `FAIL: ` )
        ( nurl_eprint label )
        ( nurl_eprint ` — expected ` )
        ( nurl_eprint ( nurl_str_int want ) )
        ( nurl_eprint `, got ` )
        ( nurl_eprint ( nurl_str_int got ) )
        ( nurl_eprint `\n` )
        ^ 1
    }
}

// ── Boolean assertions ──────────────────────────────────────────────

@ __assert_true b val s label → i {
    ? val {
        ^ 0
    } {
        ( nurl_eprint `FAIL: ` )
        ( nurl_eprint label )
        ( nurl_eprint ` — expected true, got false\n` )
        ^ 1
    }
}

@ __assert_false b val s label → i {
    ? val {
        ( nurl_eprint `FAIL: ` )
        ( nurl_eprint label )
        ( nurl_eprint ` — expected false, got true\n` )
        ^ 1
    } {
        ^ 0
    }
}

// Assert a boolean is true, with pass message.
@ __check_true b val s label → i {
    ? val {
        ( nurl_print `  PASS: ` )
        ( nurl_print label )
        ( nurl_print `\n` )
        ^ 0
    } {
        ( nurl_eprint `  FAIL: ` )
        ( nurl_eprint label )
        ( nurl_eprint `\n` )
        ^ 1
    }
}

@ __check_false b val s label → i {
    ? val {
        ( nurl_eprint `  FAIL: ` )
        ( nurl_eprint label )
        ( nurl_eprint `\n` )
        ^ 1
    } {
        ( nurl_print `  PASS: ` )
        ( nurl_print label )
        ( nurl_print `\n` )
        ^ 0
    }
}

// ── HttpRequest construction ────────────────────────────────────────
//
// HttpRequest is a boxed-handle type from http_request.nu.
// The underlying HttpRequestImpl has fields:
//   String method, String path, String query, Vec[HeaderPair] headers, Vec[u] body
//
// We construct it using the NURL struct literal. If the layout changes,
// these helpers break — see D7 in the test plan.

@ __make_test_request s method s path s query → HttpRequest {
    ^ @ HttpRequest {
        ( string_from method )
        ( string_from path )
        ( string_from query )
        ( vec_new [HeaderPair] )
        ( vec_new [u] )
    }
}

@ __make_request_with_body s method s path s query s body_content → HttpRequest {
    : String bs ( string_from body_content )
    : i blen ( string_len bs )
    : ( Vec u ) body ( vec_with_cap [u] blen )
    : ~ i k 0
    ~ < k blen {
        ( vec_push [u] body ( string_char_at bs k ) )
        = k + k 1
    }
    ^ @ HttpRequest {
        ( string_from method )
        ( string_from path )
        ( string_from query )
        ( vec_new [HeaderPair] )
        body
    }
}

@ __make_request_with_header s method s path s query s header_name s header_value → HttpRequest {
    : ( Vec HeaderPair ) headers ( vec_new [HeaderPair] )
    : HeaderPair hp @ HeaderPair { ( string_from header_name ) ( string_from header_value ) }
    ( vec_push [HeaderPair] headers hp )
    ^ @ HttpRequest {
        ( string_from method )
        ( string_from path )
        ( string_from query )
        headers
        ( vec_new [u] )
    }
}

// ── Params construction ─────────────────────────────────────────────
//
// Params is a boxed-handle from http_router.nu.
// Underlying: { Vec[QueryPair] pairs }

@ __make_params → Params {
    ^ @ Params { ( vec_new [QueryPair] ) }
}

@ __add_param Params p s key s value → v {
    : QueryPair qp @ QueryPair { ( string_from key ) ( string_from value ) }
    ( vec_push [QueryPair] . p pairs qp )
}
