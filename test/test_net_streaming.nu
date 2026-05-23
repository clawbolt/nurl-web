// test/test_net_streaming.nu — SSE streaming integration tests
//
// Requires: NURL_NET_TESTS=1

$ `test/test_helpers.nu`

// Helper: read N bytes from TcpConn
@ __read_bytes TcpConn conn i count → String {
    : String buf ( string_with_cap + count 1 )
    : ~ i k 0
    ~ < k count {
        : ? u co ( tcp_conn_read_char conn )
        ?? co { T c → { ( string_push_char buf c ) } F → {} }
        = k + k 1
    }
    ^ ( __string_seal buf )
}

// Test: SSE streaming sends events
@ test_net_sse_stream → i {
    : App app ( app_new )
    ( app_get app `/events` \ Ctx ctx → v {
        : TcpConn conn ( ctx_hijack ctx )
        // Write HTTP response head
        : String head ( string_from `HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nConnection: close\r\n\r\n` )
        ( tcp_conn_write conn ( string_data head ) ( string_len head ) )
        // Write SSE events
        : String e1 ( string_from `data: event1\n\n` )
        ( tcp_conn_write conn ( string_data e1 ) ( string_len e1 ) )
        : String e2 ( string_from `data: event2\n\n` )
        ( tcp_conn_write conn ( string_data e2 ) ( string_len e2 ) )
        ( string_free head ) ( string_free e1 ) ( string_free e2 )
    } )
    ( app_on_start app \ → v {
        : TcpConn c ?? ( tcp_connect `127.0.0.1` 19900 ) { T cc → cc F → # s 0 }
        ? != 0 # i c {
            : String req ( string_from `GET /events HTTP/1.0\r\nHost: localhost\r\n\r\n` )
            ( tcp_conn_write c ( string_data req ) ( string_len req ) )
            // Read enough to get the headers + events
            : String resp ( __read_bytes c 500 )
            : i rc ( __check_true != 0 ( nurl_str_contains ( string_data resp ) `event1` ) `net_stream: received event1` )
            // Also check event2
            ? == rc 0 {
                = rc + rc ( __check_true != 0 ( nurl_str_contains ( string_data resp ) `event2` ) `net_stream: received event2` )
            } {}
            ( string_free resp )
            ( tcp_conn_close c )
            ( string_free req )
            ( nurl_usleep 100000 )
            ^ rc
        } { ^ 1 }
    } )
    : i rc ( app_run_streaming app `127.0.0.1` 19900 )
    ( app_free app )
    ^ rc
}

// Test: normal handler on streaming server returns HTTP response
@ test_net_streaming_normal → i {
    : App app ( app_new )
    ( app_get app `/` \ Ctx ctx → v { ( ctx_text ctx 200 `hello from streaming\n` ) } )
    ( app_on_start app \ → v {
        : TcpConn c ?? ( tcp_connect `127.0.0.1` 19901 ) { T cc → cc F → # s 0 }
        ? != 0 # i c {
            : String req ( string_from `GET / HTTP/1.0\r\nHost: localhost\r\n\r\n` )
            ( tcp_conn_write c ( string_data req ) ( string_len req ) )
            : String resp ( __read_bytes c 500 )
            : i rc ( __check_true != 0 ( nurl_str_contains ( string_data resp ) `200` ) `net_stream: normal handler → 200` )
            ( string_free resp )
            ( tcp_conn_close c )
            ( string_free req )
            ( nurl_usleep 100000 )
            ^ rc
        } { ^ 1 }
    } )
    : i rc ( app_run_streaming app `127.0.0.1` 19901 )
    ( app_free app )
    ^ rc
}

@ main → i {
    ( nurl_print `test_net_streaming:\n` )
    : ~ i failures 0
    = failures + failures ( test_net_sse_stream )
    = failures + failures ( test_net_streaming_normal )
    ? == failures 0 {
        ( nurl_print `  ALL PASSED\n` )
    } {
        ( nurl_eprint `  ` )
        ( nurl_eprint ( nurl_str_int failures ) )
        ( nurl_eprint ` tests failed\n` )
    }
    ^ failures
}
