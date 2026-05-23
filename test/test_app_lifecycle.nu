// test/test_app_lifecycle.nu — tests for app_new, app_free, app_with_*, app_static, app_count, app_use

$ `test/test_helpers.nu`

@ test_app_new_defaults → i {
    : App app ( app_new )
    : i rc 0
    = rc + rc ( __check_false . app use_cors `app_new: cors off` )
    = rc + rc ( __check_false . app use_logging `app_new: logging off` )
    = rc + rc ( __check_false . app use_metrics `app_new: metrics off` )
    = rc + rc ( __check_eq_i . app body_limit 0 `app_new: body_limit 0` )
    = rc + rc ( __check_eq_i . app workers 0 `app_new: workers 0` )
    = rc + rc ( __check_eq_i ( vec_len [s] . app mw_chain ) 0 `app_new: no middleware` )
    ( app_free app )
    ^ rc
}

@ test_app_free_no_crash → i {
    : App app ( app_new )
    ( app_free app )
    ( nurl_print `  PASS: app_free no crash\n` )
    ^ 0
}

@ test_app_with_cors → i {
    : App app ( app_new )
    ( app_with_cors app )
    : i rc ( __check_true . app use_cors `app_with_cors` )
    ( app_free app )
    ^ rc
}

@ test_app_with_logging → i {
    : App app ( app_new )
    ( app_with_logging app )
    : i rc ( __check_true . app use_logging `app_with_logging` )
    ( app_free app )
    ^ rc
}

@ test_app_with_metrics → i {
    : App app ( app_new )
    ( app_with_metrics app )
    : i rc ( __check_true . app use_metrics `app_with_metrics` )
    ( app_free app )
    ^ rc
}

@ test_app_with_body_limit → i {
    : App app ( app_new )
    ( app_with_body_limit app 5242880 )
    : i rc ( __check_eq_i . app body_limit 5242880 `app_with_body_limit` )
    ( app_free app )
    ^ rc
}

@ test_app_with_idle_timeout → i {
    : App app ( app_new )
    ( app_with_idle_timeout app 5000 )
    : i rc ( __check_eq_i . app idle_timeout_ms 5000 `app_with_idle_timeout` )
    ( app_free app )
    ^ rc
}

@ test_app_with_workers → i {
    : App app ( app_new )
    ( app_with_workers app 4 )
    : i rc ( __check_eq_i . app workers 4 `app_with_workers` )
    ( app_free app )
    ^ rc
}

@ test_app_count → i {
    : App app ( app_new )
    : i rc 0
    = rc + rc ( __check_eq_i ( app_count app ) 0 `app_count: starts at 0` )
    ( app_get app `/` \ Ctx ctx → v { ( ctx_text ctx 200 `ok` ) } )
    = rc + rc ( __check_eq_i ( app_count app ) 1 `app_count: 1 route` )
    ( app_get app `/hello` \ Ctx ctx → v { ( ctx_text ctx 200 `ok` ) } )
    = rc + rc ( __check_eq_i ( app_count app ) 2 `app_count: 2 routes` )
    ( app_free app )
    ^ rc
}

@ test_app_use → i {
    : App app ( app_new )
    ( app_use app \ Ctx c → b { ^ T } )
    ( app_use app \ Ctx c → b { ^ T } )
    : i rc ( __check_eq_i ( vec_len [s] . app mw_chain ) 2 `app_use: 2 middleware` )
    ( app_free app )
    ^ rc
}

@ test_app_static → i {
    : App app ( app_new )
    ( app_static app `./public` )
    : i blen ( string_len . app static_dir )
    : i rc ( __check_true > blen 0 `app_static: dir set` )
    ( app_free app )
    ^ rc
}

@ test_app_config_chaining → i {
    : App app ( app_with_cors ( app_with_logging ( app_new ) ) )
    : i rc 0
    = rc + rc ( __check_true . app use_cors `chaining: cors` )
    = rc + rc ( __check_true . app use_logging `chaining: logging` )
    ( app_free app )
    ^ rc
}

@ main → i {
    ( nurl_print `test_app_lifecycle:\n` )
    : ~ i failures 0
    = failures + failures ( test_app_new_defaults )
    = failures + failures ( test_app_free_no_crash )
    = failures + failures ( test_app_with_cors )
    = failures + failures ( test_app_with_logging )
    = failures + failures ( test_app_with_metrics )
    = failures + failures ( test_app_with_body_limit )
    = failures + failures ( test_app_with_idle_timeout )
    = failures + failures ( test_app_with_workers )
    = failures + failures ( test_app_count )
    = failures + failures ( test_app_use )
    = failures + failures ( test_app_static )
    = failures + failures ( test_app_config_chaining )
    ? == failures 0 {
        ( nurl_print `  ALL PASSED\n` )
    } {
        ( nurl_eprint `  ` )
        ( nurl_eprint ( nurl_str_int failures ) )
        ( nurl_eprint ` tests failed\n` )
    }
    ^ failures
}
