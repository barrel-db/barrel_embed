%%%-------------------------------------------------------------------
%%% @doc Local Python embedding provider
%%%
%%% Uses erlang_python with sentence-transformers for CPU-based embeddings.
%%% No GPU required, runs entirely on CPU.
%%%
%%% == Requirements ==
%%% ```
%%% pip install sentence-transformers
%%% '''
%%%
%%% == Configuration ==
%%% ```
%%% Config = #{
%%%     venv => "/path/to/.venv",                %% Virtualenv path (recommended)
%%%     model => "BAAI/bge-base-en-v1.5",        %% Model name (default, 768 dims)
%%%     timeout => 120000                        %% Timeout in ms (default)
%%% }.
%%% '''
%%%
%%% When `venv' is specified, the provider uses the venv's Python executable
%%% and properly activates the venv environment. This is the recommended way
%%% to use barrel_embed.
%%%
%%% == Supported Models ==
%%% Any model from sentence-transformers or HuggingFace.
%%%
%%% Common models:
%%% - `"BAAI/bge-base-en-v1.5"' - Default, 768 dimensions, good quality/speed
%%% - `"BAAI/bge-small-en-v1.5"' - 384 dimensions, faster
%%% - `"BAAI/bge-large-en-v1.5"' - 1024 dimensions, best quality
%%% - `"sentence-transformers/all-MiniLM-L6-v2"' - 384 dims, fast
%%% - `"sentence-transformers/all-mpnet-base-v2"' - 768 dims, high quality
%%% - `"nomic-ai/nomic-embed-text-v1.5"' - 768 dims, long context
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(barrel_embed_local).
-behaviour(barrel_embed_provider).

%% Behaviour callbacks
-export([
    embed/2,
    embed_batch/2,
    dimension/1,
    name/0,
    init/1,
    available/1
]).

-define(DEFAULT_MODEL, "BAAI/bge-base-en-v1.5").
-define(DEFAULT_TIMEOUT, 120000).
-define(DEFAULT_DIMENSION, 768).
-define(PROVIDER, <<"sentence_transformers">>).

%%====================================================================
%% Behaviour Callbacks
%%====================================================================

%% @doc Provider name.
-spec name() -> atom().
name() -> local.

%% @doc Get dimension for this provider.
-spec dimension(map()) -> pos_integer().
dimension(Config) ->
    maps:get(dimension, Config, ?DEFAULT_DIMENSION).

%% @doc Initialize the provider.
%% Initializes Python environment and loads the model.
-spec init(map()) -> {ok, map()} | {error, term()}.
init(Config) ->
    Model = maps:get(model, Config, ?DEFAULT_MODEL),
    Timeout = maps:get(timeout, Config, ?DEFAULT_TIMEOUT),
    Venv = maps:get(venv, Config, undefined),

    %% Initialize Python environment
    PyConfig = case Venv of
        undefined -> #{};
        _ -> #{venv => Venv}
    end,

    case barrel_embed_py:init(PyConfig) of
        ok ->
            ModelBin = ensure_binary(Model),
            case barrel_embed_py:load_model(?PROVIDER, ModelBin) of
                {ok, #{dimensions := Dims}} ->
                    {ok, Config#{
                        dimension => Dims,
                        model => ModelBin,
                        provider => ?PROVIDER,
                        timeout => Timeout,
                        initialized => true
                    }};
                {ok, Info} ->
                    %% No dimensions in response, use default
                    Dims = maps:get(dimensions, Info, ?DEFAULT_DIMENSION),
                    {ok, Config#{
                        dimension => Dims,
                        model => ModelBin,
                        provider => ?PROVIDER,
                        timeout => Timeout,
                        initialized => true
                    }};
                {error, Reason} ->
                    {error, Reason}
            end;
        {error, Reason} ->
            {error, {init_failed, Reason}}
    end.

%% @doc Check if provider is available.
-spec available(map()) -> boolean().
available(#{initialized := true}) ->
    true;
available(_Config) ->
    false.

%% @doc Generate embedding for a single text.
-spec embed(binary(), map()) -> {ok, [float()]} | {error, term()}.
embed(Text, Config) ->
    case embed_batch([Text], Config) of
        {ok, [Vector]} when is_list(Vector), length(Vector) > 0 ->
            {ok, Vector};
        {ok, [[]]} ->
            {error, {empty_embedding, Text}};
        {ok, []} ->
            {error, {no_embedding, Text}};
        {ok, Other} ->
            {error, {unexpected_embedding, Other}};
        {error, _} = Error ->
            Error
    end.

%% @doc Generate embeddings for multiple texts.
-spec embed_batch([binary()], map()) -> {ok, [[float()]]} | {error, term()}.
embed_batch(Texts, #{model := Model, provider := Provider, initialized := true}) ->
    TextsBin = [ensure_binary(T) || T <- Texts],
    barrel_embed_py:embed(Provider, Model, TextsBin);
embed_batch(_Texts, _Config) ->
    {error, not_initialized}.

%%====================================================================
%% Internal Functions
%%====================================================================

ensure_binary(B) when is_binary(B) -> B;
ensure_binary(L) when is_list(L) -> unicode:characters_to_binary(L).
