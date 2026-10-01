%% The shared template's seven placeholders, filled. Keep in step with main.go.
%%
%% The template, the index URL and the OG card arrive as base64 literals in the
%% generated target/gen/hc_data.hrl, so they are part of the compiled module and
%% nothing is read from the filesystem -- Laravel Cloud's is ephemeral.
-module(hc_render).

-export([page/1, og_png/0]).

-include("hc_data.hrl").

-define(LANGUAGE, <<"Erlang">>).
-define(BRANCH, <<"erlang">>).
-define(REPO_URL, <<"https://github.com/artisan-build/hello_cloud">>).

%% Host comes from the request because og:image and og:url have to be absolute.
%% The scheme is hard-coded to https: Cloud terminates TLS upstream and then
%% sends X-Forwarded-Proto: http on an https request, so that header is unusable.
page(Host) ->
    Base = iolist_to_binary(["https://", Host]),
    Index = iolist_to_binary(string:trim(base64:decode(?INDEX_URL_B64))),
    lists:foldl(
        fun({From, To}, Acc) -> binary:replace(Acc, From, To, [global]) end,
        base64:decode(?PAGE_B64),
        [
            {<<"{{LANGUAGE}}">>, ?LANGUAGE},
            {<<"{{BRANCH}}">>, ?BRANCH},
            {<<"{{BRANCH_URL}}">>, iolist_to_binary([?REPO_URL, "/tree/", ?BRANCH])},
            {<<"{{OG_IMAGE}}">>, iolist_to_binary([Base, "/og.png"])},
            {<<"{{PAGE_URL}}">>, iolist_to_binary([Base, "/"])},
            {<<"{{INDEX_URL}}">>, Index},
            {<<"{{EXTRA}}">>, <<>>}
        ]
    ).

og_png() ->
    base64:decode(?OG_B64).
