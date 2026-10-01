-module(hc_og_h).
-export([init/2]).

init(Req, State) ->
    Reply = cowboy_req:reply(
        200,
        #{
            <<"content-type">> => <<"image/png">>,
            <<"cache-control">> => <<"public, max-age=3600">>
        },
        hc_render:og_png(),
        Req
    ),
    {ok, Reply, State}.
