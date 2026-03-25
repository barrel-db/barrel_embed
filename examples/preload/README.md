# Preload Example

Demonstrates model preloading to eliminate first-request latency.

## Quick Start

```bash
cd examples/preload
docker compose up --build
```

## What it does

1. Runs embedding generation WITHOUT preload (cold start)
2. Runs embedding generation WITH preload (warm start)
3. Compares the timing

## Configuration

Models to preload are configured in `sys.config`:

```erlang
{barrel_embed, [
    {preload_models, [
        {fastembed, <<"BAAI/bge-small-en-v1.5">>}
    ]},
    {venv, <<"/opt/venv">>}
]}
```

## Manual Run

In rebar3 shell:

```erlang
%% Run comparison
preload_example:run().

%% Or individually
preload_example:run_without_preload().
preload_example:run_with_preload().
```
