%%%-------------------------------------------------------------------
%% @doc
%% Resource discovery server.
%%
%% Maintains information about resources available on the local node
%% and resources discovered on other nodes in the Erlang cluster.
%%
%% The resource discovery state consists of:
%% - target_resources - resource types this node is interested in
%% - local_resources - resource instances available on this node
%% - found_resources - resource instances discovered in the cluster
%%
%% The server uses asynchronous messages for updating its state and
%% communicating with resource discovery servers on other nodes.
%%
%% Resource discovery is eventually consistent: discovered resources
%% may become stale when nodes disconnect or resources become unavailable.
%% @end
%%%-------------------------------------------------------------------

-module(resource_discovery_server).

-behaviour(gen_server).

%% API
-export([start_link/0, add_local_resource/2, add_target_resource/1, get_resources/1,
         trade_resources/0]).
%% Gen Server callbacks
-export([init/1, handle_call/3, handle_cast/2, terminate/2, code_change/3]).

-define(SERVER, ?MODULE).
-define(TRADE_DELAY_TIME, 2500).

-type resource_type() :: term().
-type resource() :: term().
-type resources() :: #{resource_type() => [resource()]}.
-type state() ::
    #{found_resources := resources(),
      local_resources := resources(),
      target_resources := [resource_type()]}.

%%====================================================================
%% API
%%====================================================================

%% @doc Starts the resource discovery server.
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%% @doc Adds a resource type and the resource to local resources map available on this node.
-spec add_local_resource(resource_type(), resource()) -> ok.
add_local_resource(Type, Resource) ->
    gen_server:call(?SERVER, {add_local_resource, {Type, Resource}}).

%% @doc Adds a resource to the list of resources this node wants to discover.
-spec add_target_resource(resource_type()) -> ok.
add_target_resource(Type) ->
    gen_server:call(?SERVER, {add_target_resource, Type}).

%% @doc Returns resources of the given type discovered in the cluster.
-spec get_resources(resource_type()) -> [resource()].
get_resources(Type) ->
    gen_server:call(?SERVER, {get_resources, Type}).

%% @doc Starts an exchange and waits five seconds as a best-effort synchronization delay.
-spec trade_resources() -> ok.
trade_resources() ->
    ok = gen_server:cast(?SERVER, trade_resources),
    case nodes() of
        [] ->
            ok;
        _ ->
            timer:sleep(?TRADE_DELAY_TIME)
    end.

%%====================================================================
%% Gen Server callbacks
%%====================================================================

-spec init([]) -> {ok, state()}.
init(_Args) ->
    {ok,
     #{found_resources => #{},
       local_resources => #{},
       target_resources => []}}.

-spec handle_call(term(), gen_server:from(), state()) ->
                     {reply, ok | [resource()] | {error, unsupported_request}, state()}.
handle_call({add_local_resource, {Type, Resource}},
            _From,
            #{local_resources := LocalResources} = State) ->
    NewLocalResources = add_resource_if_new(Type, Resource, LocalResources),
    {reply, ok, State#{local_resources => NewLocalResources}};
handle_call({add_target_resource, Type},
            _From,
            #{target_resources := TargetResources} = State) ->
    NewTargetResources = add_unique_resource(Type, TargetResources),
    {reply, ok, State#{target_resources => NewTargetResources}};
handle_call({get_resources, Type}, _From, #{found_resources := FoundResources} = State) ->
    ResourceList = maps:get(Type, FoundResources, []),
    {reply, ResourceList, State};
handle_call(_Request, _From, State) ->
    {reply, {error, unsupported_request}, State}.

-spec handle_cast(term(), state()) -> {noreply, state()}.
handle_cast(trade_resources,
            #{found_resources := FoundResources,
              local_resources := LocalResources,
              target_resources := TargetResources} =
                State) ->
    NewResources = get_resources_by_types(TargetResources, LocalResources),
    LocalFoundResources = add_resources_if_new(NewResources, FoundResources),
    lists:foreach(fun(Node) ->
                     gen_server:cast({?SERVER, Node}, {trade_resources, {node(), LocalResources}})
                  end,
                  nodes()),
    {noreply, State#{found_resources => LocalFoundResources}};
handle_cast({trade_resources, {From, RemoteResources}},
            #{found_resources := FoundResources,
              local_resources := LocalResources,
              target_resources := TargetResources} =
                State) ->
    NewResources = get_resources_by_types(TargetResources, RemoteResources),
    NewFoundResources = add_resources_if_new(NewResources, FoundResources),
    case From of
        noreply ->
            ok;
        _ ->
            gen_server:cast({?SERVER, From}, {trade_resources, {noreply, LocalResources}})
    end,
    {noreply, State#{found_resources => NewFoundResources}};
handle_cast(_Request, State) ->
    {noreply, State}.

-spec terminate(term(), state()) -> ok.
terminate(_Reason, _State) ->
    ok.

-spec code_change(term(), state(), term()) -> {ok, state()}.
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%====================================================================
%% Internal functions
%%====================================================================

-spec add_unique_resource(term(), list()) -> list().
add_unique_resource(Resource, ResourceList) ->
    case lists:member(Resource, ResourceList) of
        true ->
            ResourceList;
        false ->
            [Resource | ResourceList]
    end.

-spec add_resource_if_new(resource_type(), resource(), resources()) -> resources().
add_resource_if_new(Type, Resource, Resources) ->
    ResourceList = maps:get(Type, Resources, []),
    NewResourceList = add_unique_resource(Resource, ResourceList),
    maps:put(Type, NewResourceList, Resources).

-spec add_resources_if_new([{resource_type(), resource()}], resources()) -> resources().
add_resources_if_new(NewResources, OldResources) ->
    lists:foldl(fun({Type, Resource}, Resources) ->
                   add_resource_if_new(Type, Resource, Resources)
                end,
                OldResources,
                NewResources).

-spec get_resources_by_types([resource_type()], resources()) ->
                                [{resource_type(), resource()}].
get_resources_by_types(Types, Resources) ->
    lists:flatmap(fun(Type) ->
                     case maps:find(Type, Resources) of
                         {ok, ResourceList} ->
                             [{Type, Resource} || Resource <- ResourceList];
                         error ->
                             []
                     end
                  end,
                  Types).
