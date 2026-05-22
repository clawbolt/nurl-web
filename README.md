# nurl-web

A high-level web framework for [NURL](https://github.com/nurl-lang/nurl), inspired by FastAPI, Koa, and Express.

Layers ergonomic routing, middleware, request binding, and response building on top of NURL's existing HTTP/1.1 + HTTP/2 + TLS + WebSocket stack.

## Quick start

Install into an existing NURL checkout:

```bash
# Clone alongside your nurl checkout
git clone git@github1.com:clawbolt/nurl-web.git
cd nurl-web
./install.sh /path/to/nurl    # copies into nurl/stdlib/ext/
```

Then write a server:

```nurl
$ `stdlib/ext/nurl_app.nu`

@ main → i {
  : App app ( app_new )
  ( app_with_cors app )
  ( app_with_logging app )

  ( app_get app `/` \ Ctx ctx → v {
    ( ctx_json_str ctx 200 `{"hello":"world"}` )
  } )

  ( app_get app `/hello/:name` \ Ctx ctx → v {
    : ? String name ( ctx_param ctx `name` )
    ?? name {
      T n → {
        : String body ( string_from `{"hello":"` )
        ( string_push_str body ( string_data n ) )
        ( string_push_str body `"}` )
        ( ctx_json_str ctx 200 ( string_data body ) )
        ( string_free n ) ( string_free body )
      }
      F _ → { ( ctx_json_str ctx 200 `{"hello":"world"}` ) }
    }
  } )

  ^ ( app_run app `0.0.0.0` 8080 )
}
```

```bash
./nurl.sh my_server.nu
./my_server
# [nurl-app] listening on http://0.0.0.0:8080/  routes=2  workers=16
```

## Core concepts

### App

Top-level application builder. Owns the router, middleware chain, and config.

```nurl
: App app ( app_new )
( app_with_cors app )        // enable CORS
( app_with_logging app )     // access log to stderr
( app_with_metrics app )     // Prometheus counters
( app_with_body_limit app 5242880 )  // 5 MB body cap
( app_with_idle_timeout app 30000 )  // 30s keep-alive
( app_with_workers app 8 )   // 8 worker threads
```

### Ctx

Per-request context. Read the request, write the response.

**Request accessors:**

| Method | Returns | Notes |
|---|---|---|
| `ctx_method ctx` | `s` (raw) | `"GET"`, `"POST"`, etc. |
| `ctx_path ctx` | `s` (raw) | request path |
| `ctx_query_string ctx` | `s` (raw) | raw query string |
| `ctx_header ctx "name"` | `?String` | any request header |
| `ctx_param ctx "name"` | `?String` | path parameter (`:name`) |
| `ctx_body_string ctx` | `String` | full body as string (owned) |
| `ctx_body_json ctx` | `! Json ParseErr` | parsed JSON body; Err on invalid JSON |
| `ctx_query_get ctx "q"` | `?String` | query parameter |
| `ctx_form_get ctx "field"` | `?String` | form-urlencoded field |
| `ctx_cookie ctx "session"` | `?String` | named cookie |
| `ctx_bearer ctx` | `?String` | Bearer token |
| `ctx_basic_auth ctx` | `?BasicAuth` | Basic auth credentials |

**Response builders:**

```nurl
( ctx_text   ctx 200 "plain text" )
( ctx_html   ctx 200 "<b>html</b>" )
( ctx_json_str ctx 200 `{"ok":true}` )
( ctx_json   ctx 200 my_json_value )
( ctx_redirect ctx 302 "/other" )
( ctx_status ctx 204 )
( ctx_set_header ctx "X-Custom" "value" )
( ctx_set_cookie ctx "session" "abc123" )
```

### Route groups

Shared prefix + group-scoped middleware:

```nurl
: Group api ( app_group app `/api` )
( group_get api `/ping` \ Ctx ctx → v { ... } )

// Protected sub-group
: Group admin ( app_group app `/admin` )
( group_use admin \ Ctx ctx → b {
  : ? String tok ( ctx_bearer ctx )
  ?? tok { T t → {
    ? ( string_eq ( string_data t ) "secret" ) {
      ( string_free t ) ^ T
    } {
      ( string_free t )
      ( ctx_text ctx 401 `unauthorized\n` )
      ^ F
    }
  } F _ → {
    ( ctx_text ctx 401 `unauthorized\n` )
    ^ F
  } } } )
( group_get admin `/dashboard` \ Ctx ctx → v { ... } )
```

### Middleware

App-level middleware runs before every handler. Return `T` to continue, `F` to abort:

```nurl
( app_use app \ Ctx ctx → b {
  // Request logging
  ( nurl_eprint `[mw] ` )
  ( nurl_eprint ( ctx_method ctx ) )
  ( nurl_eprint ` ` )
  ( nurl_eprint ( ctx_path ctx ) )
  ( nurl_eprint `\n` )
  ^ T
} )
```

### Static files

```nurl
( app_static app `./public` )
```

Serves files from `./public/` with automatic MIME detection and path-traversal protection.

### Lifecycle hooks

```nurl
( app_on_start app \ → v {
  ( nurl_print `server is starting!\n` )
} )
( app_on_stop app \ → v {
  ( nurl_print `server is shutting down.\n` )
} )
```

### Prometheus metrics

```nurl
( app_with_metrics app )
// metrics are exposed via the App's Metrics struct —
// add a route to serve the text exposition format:
( app_get app `/metrics` \ Ctx ctx → v {
  : String body ( metrics_render . app metrics )
  ( ctx_text ctx 200 ( string_data body ) )
  ( string_free body )
} )
```

## Configuration

| Method | Default | Description |
|---|---|---|
| `app_with_cors` | off | Permissive CORS (`*`) + OPTIONS preflight |
| `app_with_logging` | off | NCSA-style access log to stderr |
| `app_with_metrics` | off | Prometheus request/latency/error counters |
| `app_with_body_limit` | 10 MB | Max request body bytes |
| `app_with_idle_timeout` | 30s | Keep-alive idle timeout |
| `app_with_workers` | 16 | Thread pool size |

## Full API reference

### App

```
app_new                                        → App
app_free App                                   → v

app_get    App s pattern ( @ v Ctx )           → v
app_post   App s pattern ( @ v Ctx )           → v
app_put    App s pattern ( @ v Ctx )           → v
app_patch  App s pattern ( @ v Ctx )           → v
app_delete App s pattern ( @ v Ctx )           → v

app_use    App ( @ b Ctx )                     → v
app_group  App s prefix                        → Group
app_static App s dir                           → v
app_count  App                                 → i

app_run    App s host i port                   → i
app_on_start App ( @ v )                       → v
app_on_stop  App ( @ v )                       → v
```

### Group

```
group_get    Group s pattern ( @ v Ctx )       → v
group_post   Group s pattern ( @ v Ctx )       → v
group_put    Group s pattern ( @ v Ctx )       → v
group_patch  Group s pattern ( @ v Ctx )       → v
group_delete Group s pattern ( @ v Ctx )       → v
group_use    Group ( @ b Ctx )                 → v
```

## Architecture

```
                    nurl_app.nu
                        │
           ┌────────────┼────────────┐
           │            │            │
     http_router    http_middleware  http_static
     http_request   http_response   http_auth
           │            │            │
           └────────────┼────────────┘
                        │
                  http_server.nu
                  (thread pool, keep-alive, pipelining)
                        │
                    std/net.nu
                  (TCP + TLS sockets)
                        │
                   runtime.c
                (POSIX / Win32 / WASI)
```

`nurl_app.nu` is pure NURL — no compiler or runtime changes. It composes the existing stdlib modules through closures and convention.

## Requirements

- NURL compiler (`nurlc`) + stdlib from [nurl-lang/nurl](https://github.com/nurl-lang/nurl)
- Install `nurl_app.nu` into `stdlib/ext/` of your NURL checkout

## License

MIT OR Apache-2.0
