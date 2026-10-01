-module(hc_page_h).
-export([init/2]).

init(Req, State) ->
    Host = cowboy_req:header(<<"host">>, Req, <<"localhost">>),
    Reply = cowboy_req:reply(
        200,
        #{<<"content-type">> => <<"text/html; charset=utf-8">>},
        hc_render:page(Host),
        Req
    ),
    {ok, Reply, State}.
