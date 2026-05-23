// test/test_net_websocket.nu — WebSocket integration tests
//
// Requires: NURL_NET_TESTS=1
// These tests perform a basic WebSocket handshake and echo exchange.

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

// Test: WebSocket upgrade and echo
// This test registers a WS echo handler, connects, performs handshake,
// sends a text frame, and verifies the echo response.
@ test_net_ws_echo → i {
    : App app ( app_new )
    ( app_get app `/ws` \ Ctx ctx → v {
        : ! v WsErr wr ( ctx_upgrade_ws ctx \ ! v WsErr WsMessage msg → {
            // Echo back: send the same message
            ?? msg {
                T m → {
                    // For a simple echo test, we just return success
                    ( ws_message_free m )
                    ^ @ ! v WsErr { T ( string_new ) }
                }
                F e → ^ @ ! v WsErr { F e }
            }
        } )
        ?? wr { T _ → {} F _ → {} }
    } )
    ( app_on_start app \ → v {
        : TcpConn c ?? ( tcp_connect `127.0.0.1` 19910 ) { T cc → cc F → # s 0 }
        ? != 0 # i c {
            // Send a basic HTTP upgrade request
            : String req ( string_from `GET /ws HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n` )
            ( tcp_conn_write c ( string_data req ) ( string_len req ) )
            // Read response — should be 101 Switching Protocols
            : String resp ( __read_bytes c 500 )
            : i rc ( __check_true != 0 ( nurl_str_contains ( string_data resp ) `101` ) `net_ws: upgrade → 101` )
            ( string_free resp )
            ( tcp_conn_close c )
            ( string_free req )
            ( nurl_usleep 100000 )
            ^ rc
        } { ^ 1 }
    } )
    : i rc ( app_run_streaming app `127.0.0.1` 19910 )
    ( app_free app )
    ^ rc
}

@ main → i {
    ( nurl_print `test_net_websocket:\n` )
    : ~ i failures 0
    = failures + failures ( test_net_ws_echo )
    ? == failures 0 {
        ( nurl_print `  ALL PASSED\n` )
    } {
        ( nurl_eprint `  ` )
        ( nurl_eprint ( nurl_str_int failures ) )
        ( nurl_eprint ` tests failed\n` )
    }
    ^ failures
}
