%%%-------------------------------------------------------------------
%%% @doc FastEmbed embedding provider
%%%
%%% Uses erlang_python with FastEmbed (ONNX-based) for lightweight, fast embeddings.
%%% Lighter alternative to sentence-transformers with similar quality.
%%%
%%% == Requirements ==
%%% ```
%%% pip install fastembed
%%% '''
%%%
%%% == Configuration ==
%%% ```
%%% Config = #{
%%%     venv => "/path/to/.venv",                %% Virtualenv path (recommended)
%%%     model => "BAAI/bge-small-en-v1.5",       %% Model name (default, 384 dims)
%%%     timeout => 120000                        %% Timeout in ms (default)
%%% }.
%%% '''
%%%
%%% When `venv' is specified, the provider uses the venv's Python executable
%%% and properly activates the venv environment.
%%%
%%% == Advantages over sentence-transformers ==
%%% - Smaller install size (~100MB vs ~2GB+)
%%% - No PyTorch dependency
%%% - Uses ONNX Runtime for optimized inference
%%% - Similar embedding quality
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(barrel_embed_fastembed).
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

-define(DEFAULT_MODEL, "BAAI/bge-small-en-v1.5").
-define(DEFAULT_TIMEOUT, 120000).
-define(DEFAULT_DIMENSION, 384).
-define(PROVIDER, <<"fastembed">>).

%%====================================================================
%% Behaviour Callbacks
%%====================================================================

%% @doc Provider name.
-spec name() -> atom().
name() -> fastembed.

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

    %% Validate model (warning only)
    validate_model(Model),

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
        {ok, [Vector]} -> {ok, Vector};
        {error, _} = Error -> Error
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

%% @private
%% Validate model (warning only)
validate_model(Model) ->
    ModelBin = ensure_binary(Model),
    %% Just log a warning for unknown models
    case is_known_model(ModelBin) of
        true ->
            ok;
        false ->
            error_logger:warning_msg(
                "Model ~s is not in the known list. "
                "It may still work if supported by FastEmbed.~n",
                [ModelBin]
            )
    end.

%% @private
%% Check if model is in known list (basic check)
is_known_model(<<"BAAI/bge-small-en-v1.5">>) -> true;
is_known_model(<<"BAAI/bge-base-en-v1.5">>) -> true;
is_known_model(<<"BAAI/bge-large-en-v1.5">>) -> true;
is_known_model(<<"sentence-transformers/all-MiniLM-L6-v2">>) -> true;
is_known_model(<<"nomic-ai/nomic-embed-text-v1.5">>) -> true;
is_known_model(_) -> false.
