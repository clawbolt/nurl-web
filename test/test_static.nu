// test/test_static.nu — tests for __register_static and static file handler logic

$ `test/test_helpers.nu`

// Test: __register_static adds a route when static_dir is set
@ test_static_registers_route → i {
    : App app ( app_new )
    ( app_static app `./public` )
    ( __register_static app )
    : i rc ( __check_true > ( app_count app ) 0 `static: route registered` )
    ( app_free app )
    ^ rc
}

// Test: __register_static is no-op when static_dir is empty
@ test_static_no_dir → i {
    : App app ( app_new )
    ( __register_static app )
    : i rc ( __check_eq_i ( app_count app ) 0 `static: no route without dir` )
    ( app_free app )
    ^ rc
}

// Test: __has_dotdot_segment blocks traversal
@ test_static_dotdot_blocked → i {
    : b result ( __has_dotdot_segment `../etc/passwd` )
    : i rc ( __check_true result `dotdot: ../etc/passwd blocked` )
    ^ rc
}

// Test: __has_dotdot_segment blocks mid-path traversal
@ test_static_dotdot_mid → i {
    : b result ( __has_dotdot_segment `foo/../../etc/passwd` )
    : i rc ( __check_true result `dotdot: mid-path traversal blocked` )
    ^ rc
}

// Test: __has_dotdot_segment allows normal paths
@ test_static_dotdot_allowed → i {
    : b result ( __has_dotdot_segment `foo/bar/baz.html` )
    : i rc ( __check_false result `dotdot: normal path allowed` )
    ^ rc
}

// Test: __has_dotdot_segment allows dots in filenames (not traversal)
@ test_static_dotdot_filename → i {
    : b result ( __has_dotdot_segment `foo/..bar` )
    : i rc ( __check_false result `dotdot: ..bar filename allowed` )
    ^ rc
}

// Test: __has_dotdot_segment allows single dot
@ test_static_dotdot_single_dot → i {
    : b result ( __has_dotdot_segment `./index.html` )
    : i rc ( __check_false result `dotdot: ./ allowed` )
    ^ rc
}

// Test: static route count increases by 1 (catch-all /*path)
@ test_static_route_count → i {
    : App app ( app_new )
    ( app_get app `/api/health` \ Ctx ctx → v { ( ctx_text ctx 200 `ok` ) } )
    : i before ( app_count app )
    ( app_static app `/some/dir` )
    ( __register_static app )
    : i after ( app_count app )
    : i rc ( __check_eq_i after + before 1 `static: adds exactly 1 route` )
    ( app_free app )
    ^ rc
}

@ main → i {
    ( nurl_print `test_static:\n` )
    : ~ i failures 0
    = failures + failures ( test_static_registers_route )
    = failures + failures ( test_static_no_dir )
    = failures + failures ( test_static_dotdot_blocked )
    = failures + failures ( test_static_dotdot_mid )
    = failures + failures ( test_static_dotdot_allowed )
    = failures + failures ( test_static_dotdot_filename )
    = failures + failures ( test_static_dotdot_single_dot )
    = failures + failures ( test_static_route_count )
    ? == failures 0 {
        ( nurl_print `  ALL PASSED\n` )
    } {
        ( nurl_eprint `  ` )
        ( nurl_eprint ( nurl_str_int failures ) )
        ( nurl_eprint ` tests failed\n` )
    }
    ^ failures
}
