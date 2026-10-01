%% An empty supervisor. cowboy brings its own tree; this exists so the
%% application callback has something to return.
-module(hello_cloud_sup).
-behaviour(supervisor).

-export([start_link/0, init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    {ok, {#{strategy => one_for_one, intensity => 1, period => 5}, []}}.
