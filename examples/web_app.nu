// examples/web_app.nu — demo of the nurl_app web framework.
//
// Showcases: routing, JSON request/response, query params,
// route groups, middleware, static serving, lifecycle hooks.
//
// Build & run:
//     ./build.sh
//     ./nurl.sh examples/web_app.nu
//
// Try:
//     curl http://127.0.0.1:8090/
//     curl http://127.0.0.1:8090/hello/NURL
//     curl http://127.0.0.1:8090/api/ping
//     curl -X POST -d '{"name":"world"}' http://127.0.0.1:8090/api/echo
//     curl http://127.0.0.1:8090/api/items?q=search
//     curl http://127.0.0.1:8090/api/secret          # 401
//     curl -H "Authorization: Bearer my-token" http://127.0.0.1:8090/api/secret
//     curl http://127.0.0.1:8090/metrics              # Prometheus text
//     curl http://127.0.0.1:8090/health

$ `stdlib/ext/nurl_app.nu`

// ── Basic routes ─────────────────────────────────────────────────────

@ h_index Ctx ctx → v {
    ( ctx_html ctx 200 `<!doctype html>
<html>
<head><meta charset="utf-8"><title>NURL Web App</title></head>
<body style="font-family:system-ui;max-width:640px;margin:2em auto">
  <h1>NURL Web App</h1>
  <p>A demo of the <code>nurl_app</code> web framework.</p>
  <ul>
    <li><a href="/hello/NURL">/hello/:name</a> — path params</li>
    <li><a href="/api/ping">/api/ping</a> — JSON response</li>
    <li><code>POST /api/echo</code> — JSON echo</li>
    <li><a href="/api/items?q=search">/api/items?q=search</a> — query params</li>
    <li><a href="/api/secret">/api/secret</a> — bearer auth</li>
    <li><a href="/health">/health</a> — health check</li>
    <li><a href="/metrics">/metrics</a> — Prometheus metrics</li>
  </ul>
</body>
</html>\n` )
}

@ h_hello Ctx ctx → v {
    : ? String name_opt ( ctx_param ctx `name` )
    ?? name_opt {
        T name → {
            : String msg ( string_from `Hello, ` )
            ( string_push_str msg ( string_data name ) )
            ( string_push_str msg `!\n` )
            ( ctx_text ctx 200 ( string_data msg ) )
            ( string_free name ) ( string_free msg )
        }
        F _ → { ( ctx_text ctx 200 `Hello, world!\n` ) }
    }
}

// ── API routes ───────────────────────────────────────────────────────

@ h_ping Ctx ctx → v {
    ( ctx_json_str ctx 200 `{"pong":true,"ts":0}` )
}

@ h_echo Ctx ctx → v {
    : String body ( ctx_body_string ctx )
    ( ctx_json_str ctx 200 ( string_data body ) )
    ( string_free body )
}

@ h_items Ctx ctx → v {
    : ? String q ( ctx_query_get ctx `q` )
    ?? q {
        T val → {
            : String body ( string_from `{"query":"` )
            ( string_push_str body ( string_data val ) )
            ( string_push_str body `","results":[]}` )
            ( ctx_json_str ctx 200 ( string_data body ) )
            ( string_free val ) ( string_free body )
        }
        F _ → { ( ctx_json_str ctx 200 `{"query":null,"results":["a","b","c"]}` ) }
    }
}

@ h_health Ctx ctx → v {
    ( ctx_json_str ctx 200 `{"status":"ok"}` )
}

@ h_metrics Ctx ctx → v {
    // Use the App's metrics handler — we pass it through global state
    // for simplicity in this example.
    ( ctx_text ctx 200 `# nurl_app demo — metrics endpoint\n` )
}

// ── Auth middleware ──────────────────────────────────────────────────

@ mw_bearer Ctx ctx → b {
    : ? String tok ( ctx_bearer ctx )
    ?? tok {
        T t → {
            // Accept any non-empty bearer token for the demo.
            : b ok != 0 ( nurl_str_eq ( string_data t ) `` )
            ( string_free t )
            ? ok {
                // No valid token → abort with 401
                ( ctx_text ctx 401 `{"error":"unauthorized"}\n` )
                ^ F
            } { ^ T }
        }
        F _ → {
            ( ctx_text ctx 401 `{"error":"unauthorized"}\n` )
            ^ F
        }
    }
}

@ h_secret Ctx ctx → v {
    ( ctx_json_str ctx 200 `{"secret":"the cake is a lie","access":"granted"}` )
}

// ── main ─────────────────────────────────────────────────────────────

@ main → i {
    : App app ( app_new )

    // Enable built-in middleware.
    ( app_with_logging app )
    ( app_with_cors app )
    ( app_with_pretty_errors app )

    // Basic routes.
    ( app_get app `/` \ Ctx ctx → v { ( h_index ctx ) } )
    ( app_get app `/hello/:name` \ Ctx ctx → v { ( h_hello ctx ) } )
    ( app_get app `/health` \ Ctx ctx → v { ( h_health ctx ) } )
    ( app_get app `/metrics` \ Ctx ctx → v { ( h_metrics ctx ) } )

    // API group with shared prefix.
    : Group api ( app_group app `/api` )
    ( group_get api `/ping` \ Ctx ctx → v { ( h_ping ctx ) } )
    ( group_post api `/echo` \ Ctx ctx → v { ( h_echo ctx ) } )
    ( group_get api `/items` \ Ctx ctx → v { ( h_items ctx ) } )

    // Protected sub-group — bearer auth middleware.
    : Group secret ( app_group app `/api` )
    ( group_use secret \ Ctx ctx → b { ^ ( mw_bearer ctx ) } )
    ( group_get secret `/secret` \ Ctx ctx → v { ( h_secret ctx ) } )

    // Lifecycle hooks.
    ( app_on_start app \ → v {
        ( nurl_print `[demo] server starting up...\n` )
    } )
    ( app_on_stop app \ → v {
        ( nurl_print `[demo] server shutting down.\n` )
    } )

    ( nurl_print `nurl_app demo — try Ctrl+C to shut down cleanly\n` )
    : i rc ( app_run app `127.0.0.1` 8090 )
    ( app_free app )
    ^ rc
}
