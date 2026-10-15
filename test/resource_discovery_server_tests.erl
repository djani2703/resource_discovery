-module(resource_discovery_server_tests).

-include_lib("eunit/include/eunit.hrl").

%% ============================================================
%% Setup / Cleanup
%% ============================================================

setup() ->
    application:ensure_started(resource_discovery).

cleanup(_SetupResult) ->
    application:stop(resource_discovery).

%% ============================================================
%% Tests
%% ============================================================

add_target_resource() ->
    ok = resource_discovery_server:add_target_resource(test_resource),

    State = sys:get_state(resource_discovery_server),
    TargetResources = maps:get(target_resources, State),

    ?assertEqual(TargetResources, [test_resource]).

add_duplicate_target_resource() ->
    ok = resource_discovery_server:add_target_resource(test_resource),
    ok = resource_discovery_server:add_target_resource(test_resource),

    State = sys:get_state(resource_discovery_server),
    TargetResources = maps:get(target_resources, State),

    ?assertEqual(TargetResources, [test_resource]).

add_local_resource() ->
    Resource = node(),

    ok = resource_discovery_server:add_local_resource(test_resource, Resource),

    State = sys:get_state(resource_discovery_server),
    LocalResources = maps:get(local_resources, State),

    ?assertEqual(LocalResources, #{test_resource => [Resource]}).

add_duplicate_local_resource() ->
    Resource = node(),

    ok = resource_discovery_server:add_local_resource(test_resource, Resource),
    ok = resource_discovery_server:add_local_resource(test_resource, Resource),

    State = sys:get_state(resource_discovery_server),
    LocalResources = maps:get(local_resources, State),

    ?assertEqual(LocalResources, #{test_resource => [Resource]}).

get_resources() ->
    Resource = node(),

    sys:replace_state(resource_discovery_server,
                      fun(State) -> State#{found_resources => #{test_resource => [Resource]}} end),
    Resources = resource_discovery_server:get_resources(test_resource),

    ?assertEqual([Resource], Resources).

trade_resources() ->
    Resource = node(),

    ok = resource_discovery_server:add_target_resource(test_resource),
    ok = resource_discovery_server:add_local_resource(test_resource, Resource),
    ok = resource_discovery_server:trade_resources(),

    Resources = resource_discovery_server:get_resources(test_resource),

    ?assertEqual([Resource], Resources).

%% ============================================================
%% Test fixture
%% ============================================================

resource_discovery_test_() ->
    {setup,
     fun setup/0,
     fun cleanup/1,
     [fun add_target_resource/0,
      fun add_duplicate_target_resource/0,
      fun add_local_resource/0,
      fun add_duplicate_local_resource/0,
      fun get_resources/0,
      fun trade_resources/0]}.                                                                                                %   fun trade_resources_local/0
