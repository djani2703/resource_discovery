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

add_target_resource_type() ->
    ok = resource_discovery_server:add_target_resource_type(test_resource),

    State = sys:get_state(resource_discovery_server),

    ?assertEqual([test_resource], maps:get(target_resources, State)).

add_duplicate_target_resource_type() ->
    ok = resource_discovery_server:add_target_resource_type(test_resource),
    ok = resource_discovery_server:add_target_resource_type(test_resource),

    State = sys:get_state(resource_discovery_server),

    ?assertEqual([test_resource], maps:get(target_resources, State)).

add_local_resource() ->
    Resource = self(),

    ok = resource_discovery_server:add_local_resource(test_resource, Resource),

    State = sys:get_state(resource_discovery_server),

    ?assertEqual(#{test_resource => [Resource]}, maps:get(local_resources, State)).

add_duplicate_local_resource() ->
    Resource = self(),

    ok = resource_discovery_server:add_local_resource(test_resource, Resource),
    ok = resource_discovery_server:add_local_resource(test_resource, Resource),

    State = sys:get_state(resource_discovery_server),

    ?assertEqual(#{test_resource => [Resource]}, maps:get(local_resources, State)).

fetch_resources() ->
    Resource = self(),

    sys:replace_state(resource_discovery_server,
                      fun(State) -> State#{found_resources => #{test_resource => [Resource]}} end),

    ?assertEqual([Resource], resource_discovery_server:fetch_resources(test_resource)).

trade_resources_local() ->
    Resource = self(),

    ok = resource_discovery_server:add_target_resource_type(test_resource),
    ok = resource_discovery_server:add_local_resource(test_resource, Resource),

    ok = resource_discovery_server:trade_resources(),

    ?assertEqual([Resource], resource_discovery_server:fetch_resources(test_resource)).

%% ============================================================
%% Test fixture
%% ============================================================

resource_discovery_test_() ->
    {setup,
     fun setup/0,
     fun cleanup/1,
     [fun add_target_resource_type/0,
      fun add_duplicate_target_resource_type/0,
      fun add_local_resource/0,
      fun add_duplicate_local_resource/0,
      fun fetch_resources/0,
      fun trade_resources_local/0]}.
