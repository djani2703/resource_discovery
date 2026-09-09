%%%-------------------------------------------------------------------
%% @doc
%% Resource Discovery OTP application.
%%
%% This application starts the supervision tree for the resource_discovery
%% system. The system is based on a supervisor that manages the
%% resource_discovery gen_server process responsible for tracking local
%% resources and discovering resources available on other Erlang nodes.
%%
%% The application itself does not manage state directly; it only starts
%% the top-level supervisor.
%% @end
%%%-------------------------------------------------------------------

-module(resource_discovery_app).

-behaviour(application).

-export([start/2, stop/1]).

%%====================================================================
%% API
%%====================================================================

%% @doc Starts the resource discovery supervision tree.
-spec start(application:start_type(), term()) -> {ok, pid()} | {error, term()}.
start(_StartType, _StartArgs) ->
    resource_discovery_sup:start_link().

%% @doc Stops the resource_discovery application.
-spec stop(term()) -> ok.
stop(_State) ->
    ok.
