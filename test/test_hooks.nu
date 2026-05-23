// test/test_hooks.nu — tests for __register_health, __run_hooks, __prepare_run, app_on_start/stop

$ `test/test_helpers.nu`

@ test_health_with_metrics → i {
    : App app ( app_new )
    ( app_with_metrics app )
    ( __register_health app )
    : i rc ( __check_eq_i ( app_count app ) 1 `health: route registered when metrics on` )
    ( app_free app )
    ^ rc
}

@ test_health_without_metrics → i {
    : App app ( app_new )
    ( __register_health app )
    : i rc ( __check_eq_i ( app_count app ) 0 `health: no route when metrics off` )
    ( app_free app )
    ^ rc
}

@ test_hooks_on_start → i {
    : App app ( app_new )
    ( app_on_start app \ → v { ( nurl_print `hook ran\n` ) } )
    : i rc ( __check_eq_i ( vec_len [s] . app on_start_hooks ) 1 `hooks: on_start registered` )
    ( app_free app )
    ^ rc
}

@ test_hooks_on_stop → i {
    : App app ( app_new )
    ( app_on_stop app \ → v { ( nurl_print `stop\n` ) } )
    : i rc ( __check_eq_i ( vec_len [s] . app on_stop_hooks ) 1 `hooks: on_stop registered` )
    ( app_free app )
    ^ rc
}

@ test_prepare_run_defaults → i {
    : App app ( app_new )
    ( __prepare_run app )
    : i rc 0
    = rc + rc ( __check_eq_i . app idle_timeout_ms 30000 `prepare: default timeout 30s` )
    = rc + rc ( __check_eq_i . app workers 16 `prepare: default workers 16` )
    ( app_free app )
    ^ rc
}

@ test_prepare_run_preserves_config → i {
    : App app ( app_new )
    ( app_with_idle_timeout app 5000 )
    ( app_with_workers app 4 )
    ( __prepare_run app )
    : i rc 0
    = rc + rc ( __check_eq_i . app idle_timeout_ms 5000 `prepare: preserves custom timeout` )
    = rc + rc ( __check_eq_i . app workers 4 `prepare: preserves custom workers` )
    ( app_free app )
    ^ rc
}

@ main → i {
    ( nurl_print `test_hooks:\n` )
    : ~ i failures 0
    = failures + failures ( test_health_with_metrics )
    = failures + failures ( test_health_without_metrics )
    = failures + failures ( test_hooks_on_start )
    = failures + failures ( test_hooks_on_stop )
    = failures + failures ( test_prepare_run_defaults )
    = failures + failures ( test_prepare_run_preserves_config )
    ? == failures 0 {
        ( nurl_print `  ALL PASSED\n` )
    } {
        ( nurl_eprint `  ` )
        ( nurl_eprint ( nurl_str_int failures ) )
        ( nurl_eprint ` tests failed\n` )
    }
    ^ failures
}
