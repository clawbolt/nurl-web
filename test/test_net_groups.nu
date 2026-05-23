// test/test_net_groups.nu — route group integration tests
//
// Requires: NURL_NET_TESTS=1

$ `test/test_helpers.nu`

// Helper: read response status line
@ __read_status TcpConn conn → String {
    : String buf ( string_with_cap 4096 )
    : ~ b done F
    : ~ i attempts 0
    ~ & done < attempts 100 {
        : ? u co ( tcp_conn_read_char conn )
        ?? co {
            T c → {
                ? == c 13 {} {
                    ? == c 10 { = done T } {
                        ( string_push_char buf c )
                    }
                }
            }
            F _ → {}
        }
        = attempts + attempts 1
    }
    ^ ( __string_seal buf )
}

// Test: group route responds correctly
@ test_net_group_ping → i {
    : App app ( app_new )
    : Group api ( app_group app `/api` )
    ( group_get api `/ping` \ Ctx ctx → v { ( ctx_json_str ctx 200 `{"pong":true}` ) } )
    ( app_on_start app \ → v {
        : TcpConn c ?? ( tcp_connect `127.0.0.1` 19880 ) { T cc → cc F → # s 0 }
        ? != 0 # i c {
            : String req ( string_from `GET /api/ping HTTP/1.0\r\nHost: localhost\r\n\r\n` )
            ( tcp_conn_write c ( string_data req ) ( string_len req ) )
            : String line1 ( __read_status c )
            : i rc ( __check_true != 0 ( nurl_str_contains ( string_data line1 ) `200` ) `net_group: /api/ping → 200` )
            ( string_free line1 )
            ( tcp_conn_close c )
            ( string_free req )
            ( nurl_usleep 100000 )
            ^ rc
        } { ^ 1 }
    } )
    : i rc ( app_run app `127.0.0.1` 19880 )
    ( app_free app )
    ^ rc
}

// Test: group middleware blocks unauthorized access
@ test_net_group_auth_block → i {
    : App app ( app_new )
    : Group secret ( app_group app `/api` )
    ( group_use secret \ Ctx ctx → b {
        : ? String tok ( ctx_bearer ctx )
        ?? tok {
            T t → {
                ? != 0 ( nurl_str_eq ( string_data t ) `secret-token` ) {
                    ( string_free t ) ^ T
                } {
                    ( string_free t )
                    ( ctx_text ctx 401 `unauthorized\n` )
                    ^ F
                }
            }
            F _ → {
                ( ctx_text ctx 401 `unauthorized\n` )
                ^ F
            }
        }
    } )
    ( group_get secret `/secret` \ Ctx ctx → v { ( ctx_json_str ctx 200 `{"secret":"value"}` ) } )
    ( app_on_start app \ → v {
        : TcpConn c ?? ( tcp_connect `127.0.0.1` 19881 ) { T cc → cc F → # s 0 }
        ? != 0 # i c {
            : String req ( string_from `GET /api/secret HTTP/1.0\r\nHost: localhost\r\n\r\n` )
            ( tcp_conn_write c ( string_data req ) ( string_len req ) )
            : String line1 ( __read_status c )
            : i rc ( __check_true != 0 ( nurl_str_contains ( string_data line1 ) `401` ) `net_group: no auth → 401` )
            ( string_free line1 )
            ( tcp_conn_close c )
            ( string_free req )
            ( nurl_usleep 100000 )
            ^ rc
        } { ^ 1 }
    } )
    : i rc ( app_run app `127.0.0.1` 19881 )
    ( app_free app )
    ^ rc
}

// Test: group middleware allows authorized access
@ test_net_group_auth_pass → i {
    : App app ( app_new )
    : Group secret ( app_group app `/api` )
    ( group_use secret \ Ctx ctx → b {
        : ? String tok ( ctx_bearer ctx )
        ?? tok {
            T t → {
                ? != 0 ( nurl_str_eq ( string_data t ) `secret-token` ) {
                    ( string_free t ) ^ T
                } {
                    ( string_free t )
                    ( ctx_text ctx 401 `unauthorized\n` )
                    ^ F
                }
            }
            F _ → {
                ( ctx_text ctx 401 `unauthorized\n` )
                ^ F
            }
        }
    } )
    ( group_get secret `/secret` \ Ctx ctx → v { ( ctx_json_str ctx 200 `{"secret":"value"}` ) } )
    ( app_on_start app \ → v {
        : TcpConn c ?? ( tcp_connect `127.0.0.1` 19882 ) { T cc → cc F → # s 0 }
        ? != 0 # i c {
            : String req ( string_from `GET /api/secret HTTP/1.0\r\nHost: localhost\r\nAuthorization: Bearer secret-token\r\n\r\n` )
            ( tcp_conn_write c ( string_data req ) ( string_len req ) )
            : String line1 ( __read_status c )
            : i rc ( __check_true != 0 ( nurl_str_contains ( string_data line1 ) `200` ) `net_group: valid auth → 200` )
            ( string_free line1 )
            ( tcp_conn_close c )
            ( string_free req )
            ( nurl_usleep 100000 )
            ^ rc
        } { ^ 1 }
    } )
    : i rc ( app_run app `127.0.0.1` 19882 )
    ( app_free app )
    ^ rc
}

@ main → i {
    ( nurl_print `test_net_groups:\n` )
    : ~ i failures 0
    = failures + failures ( test_net_group_ping )
    = failures + failures ( test_net_group_auth_block )
    = failures + failures ( test_net_group_auth_pass )
    ? == failures 0 {
        ( nurl_print `  ALL PASSED\n` )
    } {
        ( nurl_eprint `  ` )
        ( nurl_eprint ( nurl_str_int failures ) )
        ( nurl_eprint ` tests failed\n` )
    }
    ^ failures
}
