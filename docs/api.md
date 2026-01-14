# API Reference

## barrel_embed

Main embedding coordinator module.

### init/1

Initialize embedding state from configuration.

```erlang
-spec init(Config :: map()) -> {ok, State} | {ok, undefined} | {error, term()}.
```

**Config options:**

| Key | Type | Description |
|-----|------|-------------|
| `embedder` | `provider() \| [provider()]` | Provider or provider chain |
| `dimensions` | `pos_integer()` | Embedding dimension (default: 768) |
| `batch_size` | `pos_integer()` | Batch chunk size (default: 32) |

**Returns:**

- `{ok, State}` - Initialized state
- `{ok, undefined}` - No embedder configured
- `{error, Reason}` - Initialization failed

### embed/2

Generate embedding for a single text.

```erlang
-spec embed(Text :: binary(), State) -> {ok, [float()]} | {error, term()}.
```

### embed_batch/2

Generate embeddings for multiple texts.

```erlang
-spec embed_batch(Texts :: [binary()], State) -> {ok, [[float()]]} | {error, term()}.
```

### embed_batch/3

Generate embeddings with options.

```erlang
-spec embed_batch(Texts :: [binary()], Options :: map(), State) ->
    {ok, [[float()]]} | {error, term()}.
```

**Options:**

| Key | Type | Description |
|-----|------|-------------|
| `batch_size` | `pos_integer()` | Override batch chunk size |

### dimension/1

Get embedding dimension.

```erlang
-spec dimension(State) -> pos_integer() | undefined.
```

### info/1

Get provider information.

```erlang
-spec info(State) -> map().
```

**Returns:**

```erlang
#{
    configured => boolean(),
    providers => [#{module => atom(), name => atom()}],
    dimension => pos_integer()
}
```

---

## barrel_embed_provider

Provider behaviour and utilities.

### Behaviour Callbacks

```erlang
-callback embed(Text :: binary(), Config :: map()) ->
    {ok, [float()]} | {error, term()}.

-callback embed_batch(Texts :: [binary()], Config :: map()) ->
    {ok, [[float()]]} | {error, term()}.

-callback dimension(Config :: map()) -> pos_integer().

-callback name() -> atom().

%% Optional
-callback init(Config :: map()) -> {ok, map()} | {error, term()}.
-callback available(Config :: map()) -> boolean().
```

### call_embed/3

Call provider's embed function.

```erlang
-spec call_embed(Module :: atom(), Text :: binary(), Config :: map()) ->
    {ok, [float()]} | {error, term()}.
```

### call_embed_batch/3

Call provider's embed_batch function.

```erlang
-spec call_embed_batch(Module :: atom(), Texts :: [binary()], Config :: map()) ->
    {ok, [[float()]]} | {error, term()}.
```

### check_available/2

Check if provider is available.

```erlang
-spec check_available(Module :: atom(), Config :: map()) -> boolean().
```

---

## barrel_embed_splade

SPLADE sparse embedding provider.

### embed_sparse/2

Generate sparse embedding.

```erlang
-spec embed_sparse(Text :: binary(), Config :: map()) ->
    {ok, sparse_vector()} | {error, term()}.
```

**Returns:**

```erlang
#{indices => [non_neg_integer()], values => [float()]}
```

### embed_batch_sparse/2

Generate sparse embeddings for multiple texts.

```erlang
-spec embed_batch_sparse(Texts :: [binary()], Config :: map()) ->
    {ok, [sparse_vector()]} | {error, term()}.
```

---

## barrel_embed_colbert

ColBERT multi-vector embedding provider.

### embed_multi/2

Generate multi-vector embedding (one vector per token).

```erlang
-spec embed_multi(Text :: binary(), Config :: map()) ->
    {ok, [[float()]]} | {error, term()}.
```

### embed_batch_multi/2

Generate multi-vector embeddings for multiple texts.

```erlang
-spec embed_batch_multi(Texts :: [binary()], Config :: map()) ->
    {ok, [[[float()]]]} | {error, term()}.
```

### maxsim_score/2

Calculate MaxSim score between query and document.

```erlang
-spec maxsim_score(QueryVecs :: [[float()]], DocVecs :: [[float()]]) -> float().
```

---

## barrel_embed_clip

CLIP image/text embedding provider.

### embed_image/2

Generate embedding for a base64-encoded image.

```erlang
-spec embed_image(ImageBase64 :: binary(), Config :: map()) ->
    {ok, [float()]} | {error, term()}.
```

### embed_image_batch/2

Generate embeddings for multiple images.

```erlang
-spec embed_image_batch(Images :: [binary()], Config :: map()) ->
    {ok, [[float()]]} | {error, term()}.
```

---

## barrel_embed_python_queue

Python execution rate limiter.

### init/0

Initialize the ETS table. Called automatically on application start.

```erlang
-spec init() -> ok.
```

### acquire/1

Acquire a slot for Python execution.

```erlang
-spec acquire(Timeout :: timeout()) -> ok | {error, timeout}.
```

### release/0

Release a slot after execution.

```erlang
-spec release() -> ok.
```

### max_concurrent/0

Get maximum concurrent executions.

```erlang
-spec max_concurrent() -> pos_integer().
```

### current/0

Get current number of running executions.

```erlang
-spec current() -> non_neg_integer().
```
