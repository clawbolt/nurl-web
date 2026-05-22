// examples/web_minimal.nu — the smallest possible nurl_app server.
//
//     ./nurl.sh examples/web_minimal.nu
//     curl http://127.0.0.1:9090/
//     curl http://127.0.0.1:9090/hello/NURL

$ `stdlib/ext/nurl_app.nu`

@ main → i {
    : App app ( app_new )
    ( app_with_cors app )
    ( app_with_logging app )

    ( app_get app `/` \ Ctx ctx → v {
        ( ctx_json_str ctx 200 `{"message":"hello from nurl_app"}` )
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

    ( app_post app `/echo` \ Ctx ctx → v {
        : String body ( ctx_body_string ctx )
        ( ctx_text ctx 200 ( string_data body ) )
        ( string_free body )
    } )

    ^ ( app_run app `0.0.0.0` 9090 )
}
