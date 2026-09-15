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
-export([start_link/0, add_target_resource_type/1, add_local_resource/2,
         fetch_resources/1, trade_resources/0]).
%% Gen Server callbacks
-export([init/1, handle_call/3, handle_cast/2, terminate/2, code_change/3]).

-define(SERVER, ?MODULE).

-type state() ::
    #{found_resources := map(),
      local_resources := map(),
      target_resources := list()}.

%%====================================================================
%% API
%%====================================================================

%% @doc Starts the resource discovery server.
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%% @doc Adds a resource type to the list of resources this node wants to discover.
-spec add_target_resource_type(term()) -> ok.
add_target_resource_type(ResourceType) ->
    gen_server:cast(?SERVER, {add_target_resource_type, ResourceType}).

%% @doc Adds a resource type and instance to local resources map available on this node.
-spec add_local_resource(term(), pid()) -> ok.
add_local_resource(ResourceType, Instance) ->
    gen_server:cast(?SERVER, {add_local_resource, {ResourceType, Instance}}).

%% @doc Returns resources of the given type discovered in the cluster.
-spec fetch_resources(term()) -> list().
fetch_resources(ResourceType) ->
    gen_server:call(?SERVER, {fetch_resources, ResourceType}).

%% @doc Exchanges local resources with resource discovery servers on connected nodes.
-spec trade_resources() -> ok.
trade_resources() ->
    gen_server:cast(?SERVER, trade_resources).

%%====================================================================
%% Gen Server callbacks
%%====================================================================

-spec init([]) -> {ok, state()}.
init(_Args) ->
    {ok,
     #{found_resources => #{},
       local_resources => #{},
       target_resources => []}}.

-spec handle_call(tuple(), gen_server:from(), state()) -> {reply, list(), state()}.
handle_call({fetch_resources, ResourceType},
            _From,
            #{found_resources := FoundResources} = State) ->
    Resources = maps:get(ResourceType, FoundResources, []),
    {reply, Resources, State}.

-spec handle_cast(tuple(), state()) -> {noreply, state()}.
handle_cast({add_target_resource_type, ResourceType},
            #{target_resources := TargetResources} = State) ->
    NewTargetResources =
        case lists:member(ResourceType, TargetResources) of
            true ->
                TargetResources;
            false ->
                [ResourceType | TargetResources]
        end,
    {noreply, State#{target_resources => NewTargetResources}};
handle_cast({add_local_resource, {ResourceType, Resource}},
            #{local_resources := LocalResources} = State) ->
    NewLocalResources = add_resource(ResourceType, Resource, LocalResources),
    {noreply, State#{local_resources => NewLocalResources}};
handle_cast(trade_resources, #{local_resources := LocalResources} = State) ->
    lists:foreach(fun(Node) ->
                     gen_server:cast({?SERVER, Node}, {trade_resources, {node(), LocalResources}})
                  end,
                  [node() | nodes()]),
    {noreply, State};
handle_cast({trade_resources, {ReplyTo, RemoteResources}},
            #{found_resources := FoundResources,
              local_resources := LocalResources,
              target_resources := TargetResources} =
                State) ->
    NeededResources = resources_by_types(TargetResources, RemoteResources),
    NewFoundResources = add_resources(NeededResources, FoundResources),
    case ReplyTo of
        noreply ->
            ok;
        _ ->
            gen_server:cast({?SERVER, ReplyTo}, {trade_resources, {noreply, LocalResources}})
    end,
    {noreply, State#{found_resources => NewFoundResources}}.

-spec terminate(term(), state()) -> ok.
terminate(_Reason, _State) ->
    ok.

-spec code_change(term(), state(), term()) -> {ok, state()}.
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%====================================================================
%% Internal functions
%%====================================================================

%% @doc Adds a resource to the resources map.
-spec add_resource(term(), pid(), map()) -> map().
add_resource(ResourceType, Resource, Resources) ->
    ResourceList = maps:get(ResourceType, Resources, []),
    NewResourceList =
        case lists:member(Resource, ResourceList) of
            true ->
                ResourceList;
            false ->
                [Resource | ResourceList]
        end,
    maps:put(ResourceType, NewResourceList, Resources).

%% @doc Adds multiple resources to the resources map.
-spec add_resources([{term(), term()}], map()) -> map().
add_resources(NewResources, ResourcesData) ->
    lists:foldl(fun({ResourceType, Resource}, Resources) ->
                   add_resource(ResourceType, Resource, Resources)
                end,
                ResourcesData,
                NewResources).

%% @doc Returns resources matching the specified resource types.
-spec resources_by_types(list(), map()) -> [{term(), term()}].
resources_by_types(TargetResources, RemoteResources) ->
    lists:foldl(fun(ResourceType, Resources) ->
                   case maps:find(ResourceType, RemoteResources) of
                       {ok, ResourceList} ->
                           [{ResourceType, Resource} || Resource <- ResourceList] ++ Resources;
                       error ->
                           Resources
                   end
                end,
                [],
                TargetResources).
