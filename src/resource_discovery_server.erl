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
-export([start_link/0, add_target_resource/1, add_local_resource/2, get_resources/1,
         trade_resources/0]).
%% Gen Server callbacks
-export([init/1, handle_call/3, handle_cast/2, terminate/2, code_change/3]).

-define(SERVER, ?MODULE).

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

%% @doc Adds a resource type to the list of resources this node wants to discover.
-spec add_target_resource(resource_type()) -> ok.
add_target_resource(ResourceType) ->
    gen_server:cast(?SERVER, {add_target_resource, ResourceType}).

%% @doc Adds a resource type and the resource to local resources map available on this node.
-spec add_local_resource(resource_type(), resource()) -> ok.
add_local_resource(ResourceType, Resource) ->
    gen_server:cast(?SERVER, {add_local_resource, {ResourceType, Resource}}).

%% @doc Returns resources of the given type discovered in the cluster.
-spec get_resources(resource_type()) -> [resource()].
get_resources(ResourceType) ->
    gen_server:call(?SERVER, {get_resources, ResourceType}).

%% @doc Exchanges local resources with resource discovery servers on connected nodes.
-spec trade_resources() -> ok.
trade_resources() ->
    gen_server:call(?SERVER, trade_resources).

%%====================================================================
%% Gen Server callbacks
%%====================================================================

-spec init([]) -> {ok, state()}.
init(_Args) ->
    {ok,
     #{found_resources => #{},
       local_resources => #{},
       target_resources => []}}.

-spec handle_call(tuple(), gen_server:from(), state()) -> {reply, term(), state()}.
handle_call({get_resources, ResourceType},
            _From,
            #{found_resources := FoundResources} = State) ->
    Resources = maps:get(ResourceType, FoundResources, []),
    {reply, Resources, State};
handle_call(trade_resources, _From, #{local_resources := LocalResources} = State) ->
    lists:foreach(fun(Node) ->
                     gen_server:cast({?SERVER, Node}, {trade_resources, {node(), LocalResources}})
                  end,
                  [node() | nodes()]),
    {reply, ok, State}.

-spec handle_cast(tuple(), state()) -> {noreply, state()}.
handle_cast({add_target_resource, ResourceType},
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
    NewResourceList = add_new_resource(ResourceType, Resource, LocalResources),
    NewLocalResources = maps:put(ResourceType, NewResourceList, LocalResources),
    {noreply, State#{local_resources => NewLocalResources}};
handle_cast({trade_resources, {From, RemoteResources}},
            #{found_resources := FoundResources,
              local_resources := LocalResources,
              target_resources := TargetResources} =
                State) ->
    NewResources = collect_resources_by_types(TargetResources, RemoteResources),
    NewFoundResources = add_new_resources(NewResources, FoundResources),
    case From of
        noreply ->
            ok;
        _ ->
            gen_server:cast({?SERVER, From}, {trade_resources, {noreply, LocalResources}})
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

%% @doc Adds a new resource to the resource list.
-spec add_new_resource(resource_type(), resource(), resources()) -> [resource()].
add_new_resource(ResourceType, Resource, Resources) ->
    ResourceList = maps:get(ResourceType, Resources, []),
    case lists:member(Resource, ResourceList) of
        true ->
            ResourceList;
        false ->
            [Resource | ResourceList]
    end.

%% @doc Adds multiple resources to the resources map.
-spec add_new_resources([{resource_type(), resource()}], resources()) -> resources().
add_new_resources(NewResources, ResourcesData) ->
    lists:foldl(fun({ResourceType, Resource}, Resources) ->
                   ResourceList = add_new_resource(ResourceType, Resource, Resources),
                   maps:put(ResourceType, ResourceList, Resources)
                end,
                ResourcesData,
                NewResources).

%% @doc Collects resources of the specified types
-spec collect_resources_by_types([resource_type()], resources()) ->
                                    [{resource_type(), resource()}].
collect_resources_by_types(ResourceTypes, Resources) ->
    lists:flatmap(fun(ResourceType) ->
                     case maps:find(ResourceType, Resources) of
                         {ok, ResourceList} ->
                             [{ResourceType, Resource} || Resource <- ResourceList];
                         error ->
                             []
                     end
                  end,
                  ResourceTypes).
