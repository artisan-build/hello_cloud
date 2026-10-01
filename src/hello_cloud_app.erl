%% The application entry point: start one cowboy listener, nothing else.
%%
%% The listener binds the IPv6 wildcard rather than 0.0.0.0, because Laravel
%% Cloud's per-instance nginx proxies to 127.0.0.1:$PORT over an IPv6-only
%% network and a Linux IPv6 wildcard socket is dual-stack by default. Nothing
%% here sets ipv6_v6only.
-module(hello_cloud_app).
-behaviour(application).

-export([start/2, stop/1]).

start(_Type, _Args) ->
    Dispatch = cowboy_router:compile([
        {'_', [
            {"/", hc_page_h, []},
            {"/og.png", hc_og_h, []}
        ]}
    ]),
    {ok, _} = cowboy:start_clear(
        hc_listener,
        #{socket_opts => [{port, port()}, inet6, {ip, {0, 0, 0, 0, 0, 0, 0, 0}}]},
        #{env => #{dispatch => Dispatch}}
    ),
    hello_cloud_sup:start_link().

stop(_State) ->
    ok = cowboy:stop_listener(hc_listener).

port() ->
    case os:getenv("PORT") of
        false -> 3000;
        "" -> 3000;
        P -> list_to_integer(P)
    end.
