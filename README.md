# resource_discovery

A distributed resource discovery system built with Erlang/OTP and Rebar3.

Each Erlang node runs a `resource_discovery_server` process that keeps track of local resources and discovers resources available on other connected nodes.

## Features

* Distributed resource discovery between Erlang nodes
* Local resource registration
* Resource type filtering
* Resource exchange between connected nodes
* OTP supervision tree
* Eventual consistency
* Rebar3 build and test workflow

## Architecture

```text
                    resource_discovery
                           |
                           v
                resource_discovery_sup
                           |
                           v
              resource_discovery_server
                           |
          +----------------+----------------+
          |                |                |
          v                v                v
   target_resources  local_resources  found_resources
                           |
                           v
                    Erlang cluster
                           |
              +------------+------------+
              |                         |
              v                         v
       Node A server             Node B server
```

The `resource_discovery_server` maintains three types of state:

* `target_resources` — resource types this node wants to discover
* `local_resources` — resources available on this node
* `found_resources` — resources discovered on other nodes

Resources are exchanged between connected Erlang nodes using Erlang message passing.

## Build

Compile the application with:

```bash
rebar3 compile
```

## Test

Run the test suite with:

```bash
rebar3 eunit
```

## Format

Format the Erlang source code with:

```bash
rebar3 format
```

## Shell

Start an Erlang shell with:

```bash
rebar3 shell
```

The resource discovery can then be used through its public API:

Add a resource type to discover:
```erlang
resource_discovery_server:add_target_resource_type(database).
```

Add a local resource:
```erlang
resource_discovery_server:add_local_resource(database, ResourcePid).
```

Exchange resources with connected nodes:
```erlang
resource_discovery_server:trade_resources().
```

Fetch discovered resources:
```erlang
resource_discovery_server:fetch_resources(database).
```

## License

This project is for learning and experimentation with Erlang/OTP.