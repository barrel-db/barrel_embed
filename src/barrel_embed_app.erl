%%%-------------------------------------------------------------------
%%% @doc barrel_embed application callback module
%%% @end
%%%-------------------------------------------------------------------
-module(barrel_embed_app).

-behaviour(application).

-export([start/2, stop/1]).

%%====================================================================
%% Application callbacks
%%====================================================================

start(_StartType, _StartArgs) ->
    %% Collect models to preload from both preload_models and embedder config
    Models = collect_preload_models(),
    Venv = application:get_env(barrel_embed, venv, undefined),

    %% Check if erlang_python is already running
    AlreadyRunning = whereis(py_sup) =/= undefined,

    %% Setup preload BEFORE starting erlang_python so models are
    %% preloaded during interpreter initialization
    barrel_embed_preload:setup(#{models => Models, venv => Venv}),

    %% Ensure erlang_python is started (should already be via application deps)
    case application:ensure_all_started(erlang_python) of
        {ok, _} -> ok;
        {error, {already_started, _}} -> ok;
        {error, Reason} ->
            error_logger:error_msg("Failed to start erlang_python: ~p~n", [Reason])
    end,

    %% Ensure priv dir is in Python path (in case erlang_python was already running)
    barrel_embed_py:init(#{venv => Venv}),

    %% If erlang_python was already running, execute preload code manually
    %% to ensure models are loaded in the existing interpreter
    case AlreadyRunning of
        true ->
            case py_preload:get_code() of
                undefined -> ok;
                Code ->
                    case py:exec(Code) of
                        ok -> ok;
                        {error, PreloadErr} ->
                            error_logger:warning_msg(
                                "Failed to execute preload code: ~p~n", [PreloadErr])
                    end
            end;
        false ->
            ok
    end,

    barrel_embed_sup:start_link().

stop(_State) ->
    ok.

%%====================================================================
%% Internal Functions
%%====================================================================

%% @private
%% Collect models to preload from preload_models env and embedder config
collect_preload_models() ->
    %% Get explicit preload_models
    ExplicitModels = application:get_env(barrel_embed, preload_models, []),

    %% Extract models from embedder config (if any)
    EmbedderModels = case application:get_env(barrel_embed, embedder, undefined) of
        undefined -> [];
        EmbedderConfig -> extract_local_models(EmbedderConfig)
    end,

    %% Merge and deduplicate
    lists:usort(ExplicitModels ++ EmbedderModels).

%% @private
%% Extract local Python models from embedder configuration
extract_local_models({local, Config}) ->
    [local_model_spec(Config)];
extract_local_models({fastembed, Config}) ->
    [fastembed_model_spec(Config)];
extract_local_models({splade, Config}) ->
    [splade_model_spec(Config)];
extract_local_models({colbert, Config}) ->
    [colbert_model_spec(Config)];
extract_local_models({clip, Config}) ->
    [clip_model_spec(Config)];
extract_local_models(Providers) when is_list(Providers) ->
    lists:flatmap(fun extract_local_models/1, Providers);
extract_local_models(_) ->
    [].

%% @private
local_model_spec(Config) ->
    Model = maps:get(model, Config, <<"BAAI/bge-base-en-v1.5">>),
    {sentence_transformers, ensure_binary(Model)}.

fastembed_model_spec(Config) ->
    Model = maps:get(model, Config, <<"BAAI/bge-small-en-v1.5">>),
    {fastembed, ensure_binary(Model)}.

splade_model_spec(Config) ->
    Model = maps:get(model, Config, <<"naver/splade-cocondenser-ensembledistil">>),
    {splade, ensure_binary(Model)}.

colbert_model_spec(Config) ->
    Model = maps:get(model, Config, <<"colbert-ir/colbertv2.0">>),
    {colbert, ensure_binary(Model)}.

clip_model_spec(Config) ->
    Model = maps:get(model, Config, <<"openai/clip-vit-base-patch32">>),
    {clip, ensure_binary(Model)}.

ensure_binary(B) when is_binary(B) -> B;
ensure_binary(L) when is_list(L) -> unicode:characters_to_binary(L);
ensure_binary(A) when is_atom(A) -> atom_to_binary(A, utf8).
