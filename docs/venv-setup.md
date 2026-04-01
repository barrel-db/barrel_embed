# Python Virtualenv Setup

barrel_embed automatically manages a Python virtualenv with required dependencies.

## Automatic Setup (v2.2.0+)

Starting with v2.2.0, barrel_embed automatically:

1. Creates a venv at `priv/.venv` on application startup
2. Installs uvloop for async performance (required on Unix)
3. Installs provider-specific dependencies when providers are initialized

**No manual setup required for most use cases.**

```erlang
%% Just start using it - venv is created automatically
{ok, State} = barrel_embed:init(#{
    embedder => {fastembed, #{}}  %% fastembed deps installed automatically
}).
```

## Venv Management API

```erlang
%% Get venv path
Path = barrel_embed:venv_path().
%% => "_build/default/lib/barrel_embed/priv/.venv"

%% Check if uvloop is installed
barrel_embed:has_uvloop().
%% => true

%% Manually install provider deps
barrel_embed:install_provider(fastembed).
%% => ok

%% Recreate venv from scratch
barrel_embed:refresh_venv().
%% => {ok, "/path/to/.venv"}
```

## Custom Venv Location

Set a custom venv path via application config:

```erlang
%% In sys.config
{barrel_embed, [
    {venv_dir, "/opt/barrel_embed/venv"}
]}.

%% Or at runtime (before app starts)
application:set_env(barrel_embed, venv_dir, "/opt/barrel_embed/venv").
```

## Manual Setup (Optional)

If you prefer manual control or need custom packages:

```bash
# Using uv (recommended - fast)
uv venv .venv
uv pip install uvloop fastembed --python .venv/bin/python

# Or using pip
python3 -m venv .venv
.venv/bin/pip install uvloop fastembed
```

Then pass the venv path explicitly:

```erlang
{ok, State} = barrel_embed:init(#{
    embedder => {fastembed, #{
        venv => "/absolute/path/to/.venv"
    }}
}).
```

## Provider Dependencies

| Provider | Packages | Size |
|----------|----------|------|
| `fastembed` | fastembed | ~100MB |
| `local` | sentence-transformers | ~2GB |
| `splade` | transformers, torch | ~2GB |
| `colbert` | transformers, torch | ~2GB |
| `clip` | transformers, torch, pillow | ~2GB |

Dependencies are installed on-demand when a provider is first initialized.

## uvloop Requirement

uvloop is required on Unix systems and installed automatically. It provides significant performance improvements for the async embedding server.

Check uvloop status:
```erlang
barrel_embed:has_uvloop().
%% => true (Unix) or false (Windows)
```

The Python server logs uvloop status on startup:
```
Async server ready (uvloop=True, workers=4)
```

## Troubleshooting

### Venv Creation Failed

If venv creation fails, check:

1. Python 3 is installed: `python3 --version`
2. venv module is available: `python3 -m venv --help`
3. Write permissions to priv directory

### uvloop Installation Failed

uvloop requires a C compiler. On Debian/Ubuntu:
```bash
apt-get install build-essential python3-dev
```

On macOS, install Xcode command line tools:
```bash
xcode-select --install
```

### Provider Deps Failed

For providers using PyTorch (local, splade, colbert, clip):
- Ensure sufficient disk space (~2GB)
- May take several minutes on first install

## For Dependent Applications

If your app uses barrel_embed as a dependency:

```erlang
%% Option 1: Use barrel_embed's managed venv (recommended)
{ok, State} = barrel_embed:init(#{
    embedder => {fastembed, #{}}  %% Uses managed venv automatically
}).

%% Option 2: Use your own venv
VenvPath = filename:join(code:priv_dir(my_app), ".venv"),
{ok, State} = barrel_embed:init(#{
    embedder => {fastembed, #{venv => VenvPath}}
}).
```
