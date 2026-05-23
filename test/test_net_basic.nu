// test/test_net_basic.nu — basic HTTP integration tests through app_run
//
// Requires: NURL_NET_TESTS=1
// These tests start real servers and send HTTP requests over TCP.

$ `test/test_helpers.nu`

// Helper: read a line from TcpConn with a timeout
@ __read_response_line TcpConn conn → String {
    : String buf ( string_with_cap 4096 )
    : ~ b done F
    : ~ i attempts 0
    ~ & done < attempts 100 {
        : ? u co ( tcp_conn_read_char conn )
        ?? co {
            T c → {
                ? == c 13 {
                    // CR — skip, look for LF
                } {
                    ? == c 10 {
                        = done T
                    } {
                        ( string_push_char buf c )
                    }
                }
            }
            F _ → {
                // No data yet — busy wait (acceptable for tests)
            }
        }
        = attempts + attempts 1
    }
    ^ ( __string_seal buf )
}

// Test: basic GET / returns 200
@ test_net_get_root → i {
    : App app ( app_new )
    ( app_get app `/` \ Ctx ctx → v { ( ctx_text ctx 200 `hello\n` ) } )
    ( app_on_start app \ → v {
        // Client: connect after a short delay and send request
        : TcpConn c ?? ( tcp_connect `127.0.0.1` 19876 ) { T cc → cc F → # s 0 }
        ? != 0 # i c {
            : String req ( string_from `GET / HTTP/1.0\r\nHost: localhost\r\n\r\n` )
            ( tcp_conn_write c ( string_data req ) ( string_len req ) )
            : String line1 ( __read_response_line c )
            : i rc ( __check_true != 0 ( nurl_str_contains ( string_data line1 ) `200` ) `net: GET / → 200` )
            ( string_free line1 )
            ( tcp_conn_close c )
            ( string_free req )
            // Signal shutdown
            ( nurl_usleep 100000 )
            ^ rc
        } {
            ( nurl_eprint `FAIL: could not connect\n` )
            ^ 1
        }
    } )
    : i rc ( app_run app `127.0.0.1` 19876 )
    ( app_free app )
    ^ rc
}

// Test: GET /nonexistent returns 404
@ test_net_get_not_found → i {
    : App app ( app_new )
    ( app_get app `/` \ Ctx ctx → v { ( ctx_text ctx 200 `ok\n` ) } )
    ( app_on_start app \ → v {
        : TcpConn c ?? ( tcp_connect `127.0.0.1` 19877 ) { T cc → cc F → # s 0 }
        ? != 0 # i c {
            : String req ( string_from `GET /missing HTTP/1.0\r\nHost: localhost\r\n\r\n` )
            ( tcp_conn_write c ( string_data req ) ( string_len req ) )
            : String line1 ( __read_response_line c )
            : i rc ( __check_true != 0 ( nurl_str_contains ( string_data line1 ) `404` ) `net: GET /missing → 404` )
            ( string_free line1 )
            ( tcp_conn_close c )
            ( string_free req )
            ( nurl_usleep 100000 )
            ^ rc
        } {
            ^ 1
        }
    } )
    : i rc ( app_run app `127.0.0.1` 19877 )
    ( app_free app )
    ^ rc
}

// Test: POST /echo returns echoed body
@ test_net_post_echo → i {
    : App app ( app_new )
    ( app_post app `/echo` \ Ctx ctx → v {
        : String body ( ctx_body_string ctx )
        ( ctx_text ctx 200 ( string_data body ) )
        ( string_free body )
    } )
    ( app_on_start app \ → v {
        : TcpConn c ?? ( tcp_connect `127.0.0.1` 19878 ) { T cc → cc F → # s 0 }
        ? != 0 # i c {
            : String req ( string_from `POST /echo HTTP/1.0\r\nHost: localhost\r\nContent-Length: 5\r\n\r\nhello` )
            ( tcp_conn_write c ( string_data req ) ( string_len req ) )
            // Read status line
            : String line1 ( __read_response_line c )
            : i rc ( __check_true != 0 ( nurl_str_contains ( string_data line1 ) `200` ) `net: POST /echo → 200` )
            ( string_free line1 )
            ( tcp_conn_close c )
            ( string_free req )
            ( nurl_usleep 100000 )
            ^ rc
        } {
            ^ 1
        }
    } )
    : i rc ( app_run app `127.0.0.1` 19878 )
    ( app_free app )
    ^ rc
}

@ main → i {
    ( nurl_print `test_net_basic:\n` )
    : ~ i failures 0
    = failures + failures ( test_net_get_root )
    = failures + failures ( test_net_get_not_found )
    = failures + failures ( test_net_post_echo )
    ? == failures 0 {
        ( nurl_print `  ALL PASSED\n` )
    } {
        ( nurl_eprint `  ` )
        ( nurl_eprint ( nurl_str_int failures ) )
        ( nurl_eprint ` tests failed\n` )
    }
    ^ failures
}
