// test/test_net_middleware.nu — middleware integration tests
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

// Test: body limit rejects oversized POST
@ test_net_body_limit → i {
    : App app ( app_new )
    ( app_with_body_limit app 10 )
    ( app_post app `/data` \ Ctx ctx → v {
        : String body ( ctx_body_string ctx )
        ( ctx_text ctx 200 ( string_data body ) )
        ( string_free body )
    } )
    ( app_on_start app \ → v {
        : TcpConn c ?? ( tcp_connect `127.0.0.1` 19890 ) { T cc → cc F → # s 0 }
        ? != 0 # i c {
            // Send a body larger than 10 bytes
            : String req ( string_from `POST /data HTTP/1.0\r\nHost: localhost\r\nContent-Length: 50\r\n\r\nthis body is way too long for the limit` )
            ( tcp_conn_write c ( string_data req ) ( string_len req ) )
            : String line1 ( __read_status c )
            : i rc ( __check_true != 0 ( nurl_str_contains ( string_data line1 ) `413` ) `net_mw: oversized body → 413` )
            ( string_free line1 )
            ( tcp_conn_close c )
            ( string_free req )
            ( nurl_usleep 100000 )
            ^ rc
        } { ^ 1 }
    } )
    : i rc ( app_run app `127.0.0.1` 19890 )
    ( app_free app )
    ^ rc
}

// Test: app-level middleware aborts request
@ test_net_mw_abort → i {
    : App app ( app_new )
    ( app_use app \ Ctx ctx → b {
        ( ctx_text ctx 403 `forbidden\n` )
        ^ F
    } )
    ( app_get app `/anything` \ Ctx ctx → v { ( ctx_text ctx 200 `ok\n` ) } )
    ( app_on_start app \ → v {
        : TcpConn c ?? ( tcp_connect `127.0.0.1` 19891 ) { T cc → cc F → # s 0 }
        ? != 0 # i c {
            : String req ( string_from `GET /anything HTTP/1.0\r\nHost: localhost\r\n\r\n` )
            ( tcp_conn_write c ( string_data req ) ( string_len req ) )
            : String line1 ( __read_status c )
            : i rc ( __check_true != 0 ( nurl_str_contains ( string_data line1 ) `403` ) `net_mw: middleware abort → 403` )
            ( string_free line1 )
            ( tcp_conn_close c )
            ( string_free req )
            ( nurl_usleep 100000 )
            ^ rc
        } { ^ 1 }
    } )
    : i rc ( app_run app `127.0.0.1` 19891 )
    ( app_free app )
    ^ rc
}

// Test: app-level middleware passes, handler runs
@ test_net_mw_pass → i {
    : App app ( app_new )
    ( app_use app \ Ctx ctx → b { ^ T } )
    ( app_get app `/` \ Ctx ctx → v { ( ctx_text ctx 200 `passed\n` ) } )
    ( app_on_start app \ → v {
        : TcpConn c ?? ( tcp_connect `127.0.0.1` 19892 ) { T cc → cc F → # s 0 }
        ? != 0 # i c {
            : String req ( string_from `GET / HTTP/1.0\r\nHost: localhost\r\n\r\n` )
            ( tcp_conn_write c ( string_data req ) ( string_len req ) )
            : String line1 ( __read_status c )
            : i rc ( __check_true != 0 ( nurl_str_contains ( string_data line1 ) `200` ) `net_mw: middleware pass → 200` )
            ( string_free line1 )
            ( tcp_conn_close c )
            ( string_free req )
            ( nurl_usleep 100000 )
            ^ rc
        } { ^ 1 }
    } )
    : i rc ( app_run app `127.0.0.1` 19892 )
    ( app_free app )
    ^ rc
}

@ main → i {
    ( nurl_print `test_net_middleware:\n` )
    : ~ i failures 0
    = failures + failures ( test_net_body_limit )
    = failures + failures ( test_net_mw_abort )
    = failures + failures ( test_net_mw_pass )
    ? == failures 0 {
        ( nurl_print `  ALL PASSED\n` )
    } {
        ( nurl_eprint `  ` )
        ( nurl_eprint ( nurl_str_int failures ) )
        ( nurl_eprint ` tests failed\n` )
    }
    ^ failures
}
