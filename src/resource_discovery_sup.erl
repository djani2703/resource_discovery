%%%-------------------------------------------------------------------
%% @doc
%% Resource Discovery Supervisor.
%%
%% This supervisor manages the resource_discovery gen_server process
%% responsible for maintaining local resources and discovering resources
%% available on other Erlang nodes.
%%
%% The supervisor uses a one_for_one strategy, so if a child process
%% terminates, only that child process is restarted.
%% @end
%%%-------------------------------------------------------------------

-module(resource_discovery_sup).

-behaviour(supervisor).

%% API
-export([start_link/0]).
%% Supervisor callbacks
-export([init/1]).

-define(SERVER, ?MODULE).

%%====================================================================
%% API
%%====================================================================
%% @doc Starts the resource discovery supervisor.
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

%%====================================================================
%% Supervisor callbacks
%%====================================================================

-spec init(term()) -> {ok, {supervisor:sup_flags(), [supervisor:child_spec()]}}.
init([]) ->
    SupFlags =
        #{strategy => one_for_one,
          intensity => 1,
          period => 5},
    ChildSpecs = [],
    {ok, {SupFlags, ChildSpecs}}.
