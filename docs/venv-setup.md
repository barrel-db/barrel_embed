# Python Virtualenv Setup

barrel_embed requires Python with specific packages. Using a virtualenv is recommended.

## Quick Start

```bash
# Using uv (recommended - fast)
./scripts/setup_venv.sh

# Or manually
uv venv .venv
uv pip install -r priv/requirements.txt --python .venv/bin/python
```

## Usage in Erlang

```erlang
{ok, State} = barrel_embed:init(#{
    embedder => {local, #{
        venv => "/absolute/path/to/.venv"
    }}
}).
```

## Installing uvloop (Optional Performance Boost)

uvloop provides a faster asyncio event loop. It's optional but recommended on Linux/macOS:

```bash
# Add uvloop to an existing venv
uv pip install uvloop --python .venv/bin/python

# Or use the full requirements file
uv pip install -r priv/requirements-full.txt --python .venv/bin/python
```

When uvloop is installed, barrel_embed automatically uses it. Check the logs for:
```
Async server ready (uvloop=True, workers=4)
```

**Note:** uvloop is not available on Windows.

## Requirements Files

| File | Contents |
|------|----------|
| `priv/requirements.txt` | Default: barrel_embed + sentence-transformers + uvloop |
| `priv/requirements-minimal.txt` | Just barrel_embed + uvloop (no ML libs) |
| `priv/requirements-full.txt` | All providers + uvloop |

## Custom Requirements

Create your own requirements file that extends the base:

```
# my-requirements.txt
-r /path/to/barrel_embed/priv/requirements.txt
my-extra-package>=1.0.0
```

Then setup:

```bash
./scripts/setup_venv.sh .venv my-requirements.txt
```

## For Dependent Applications

If your app (e.g., barrel_vectordb) uses barrel_embed as a dependency:

1. Create `priv/requirements.txt` in your app:
   ```
   -r deps/barrel_embed/priv/requirements.txt
   your-extra-packages
   ```

2. Setup venv in your app:
   ```bash
   uv venv priv/.venv
   uv pip install -r priv/requirements.txt --python priv/.venv/bin/python
   ```

3. Pass venv to barrel_embed:
   ```erlang
   VenvPath = filename:join(code:priv_dir(my_app), ".venv"),
   barrel_embed:init(#{
       embedder => {local, #{venv => VenvPath}}
   }).
   ```

## How Venv Activation Works

When you specify `venv`, barrel_embed sets these environment variables in the Python port:

- `VIRTUAL_ENV=/path/to/.venv`
- `PATH=/path/to/.venv/bin:$PATH`
- `PYTHONPATH=<priv_dir>`

This is equivalent to running `source .venv/bin/activate` before starting Python.
