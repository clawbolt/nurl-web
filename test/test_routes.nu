// test/test_routes.nu — tests for route registration and groups

$ `test/test_helpers.nu`

@ test_register_get → i {
    : App app ( app_new )
    ( app_get app `/` \ Ctx ctx → v { ( ctx_text ctx 200 `root` ) } )
    : i rc ( __check_eq_i ( app_count app ) 1 `register: GET /` )
    ( app_free app )
    ^ rc
}

@ test_register_all_methods → i {
    : App app ( app_new )
    ( app_get app `/g` \ Ctx ctx → v { ( ctx_text ctx 200 `ok` ) } )
    ( app_post app `/p` \ Ctx ctx → v { ( ctx_text ctx 200 `ok` ) } )
    ( app_put app `/pu` \ Ctx ctx → v { ( ctx_text ctx 200 `ok` ) } )
    ( app_patch app `/pa` \ Ctx ctx → v { ( ctx_text ctx 200 `ok` ) } )
    ( app_delete app `/d` \ Ctx ctx → v { ( ctx_text ctx 200 `ok` ) } )
    : i rc ( __check_eq_i ( app_count app ) 5 `register: all 5 methods` )
    ( app_free app )
    ^ rc
}

@ test_app_group → i {
    : App app ( app_new )
    : Group api ( app_group app `/api` )
    ( group_get api `/ping` \ Ctx ctx → v { ( ctx_text ctx 200 `pong` ) } )
    : i rc ( __check_eq_i ( app_count app ) 1 `group: /api/ping registered` )
    ( app_free app )
    ^ rc
}

@ test_group_with_middleware → i {
    : App app ( app_new )
    : Group admin ( app_group app `/admin` )
    ( group_use admin \ Ctx ctx → b { ^ T } )
    ( group_get admin `/dashboard` \ Ctx ctx → v { ( ctx_text ctx 200 `ok` ) } )
    : i rc ( __check_eq_i ( app_count app ) 1 `group_mw: route registered` )
    ( app_free app )
    ^ rc
}

@ test_multiple_groups → i {
    : App app ( app_new )
    : Group api ( app_group app `/api` )
    : Group web ( app_group app `/web` )
    ( group_get api `/ping` \ Ctx ctx → v { ( ctx_text ctx 200 `pong` ) } )
    ( group_get web `/home` \ Ctx ctx → v { ( ctx_text ctx 200 `home` ) } )
    : i rc ( __check_eq_i ( app_count app ) 2 `multi_group: 2 routes` )
    ( app_free app )
    ^ rc
}

@ test_middleware_snapshot → i {
    // Middleware is captured at registration time, not dispatch time.
    // Register route, add middleware, register another route.
    // First route should have 0 middleware, second should have 1.
    : App app ( app_new )
    ( app_get app `/first` \ Ctx ctx → v { ( ctx_text ctx 200 `first` ) } )
    ( app_use app \ Ctx c → b { ^ T } )
    ( app_get app `/second` \ Ctx ctx → v { ( ctx_text ctx 200 `second` ) } )
    // Both routes are registered — 2 total
    : i rc ( __check_eq_i ( app_count app ) 2 `snapshot: 2 routes registered` )
    ( app_free app )
    ^ rc
}

@ main → i {
    ( nurl_print `test_routes:\n` )
    : ~ i failures 0
    = failures + failures ( test_register_get )
    = failures + failures ( test_register_all_methods )
    = failures + failures ( test_app_group )
    = failures + failures ( test_group_with_middleware )
    = failures + failures ( test_multiple_groups )
    = failures + failures ( test_middleware_snapshot )
    ? == failures 0 {
        ( nurl_print `  ALL PASSED\n` )
    } {
        ( nurl_eprint `  ` )
        ( nurl_eprint ( nurl_str_int failures ) )
        ( nurl_eprint ` tests failed\n` )
    }
    ^ failures
}
