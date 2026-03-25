%%%-------------------------------------------------------------------
%%% @doc Erlang wrapper for py:call Python integration
%%%
%%% Provides a high-level interface to the Python embedding functions
%%% using erlang_python's py:call mechanism.
%%%
%%% == Usage ==
%%% ```
%%% %% Initialize with venv
%%% ok = barrel_embed_py:init(#{venv => "/path/to/.venv"}).
%%%
%%% %% Load a model
%%% {ok, Info} = barrel_embed_py:load_model(<<"fastembed">>, <<"BAAI/bge-small-en-v1.5">>).
%%%
%%% %% Generate embeddings
%%% {ok, Embeddings} = barrel_embed_py:embed(<<"fastembed">>, <<"BAAI/bge-small-en-v1.5">>,
%%%                                          [<<"Hello">>, <<"World">>]).
%%% '''
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(barrel_embed_py).

-export([
    init/1,
    load_model/2,
    load_model/3,
    embed/3,
    embed/4,
    embed_sparse/3,
    embed_multi/3,
    embed_image/2,
    unload_model/2,
    loaded_models/0
]).

%% The Python module to call (barrel_embed.nif_api in Python path)
-define(API_MODULE, 'barrel_embed.nif_api').

%% Default timeouts
-define(DEFAULT_LOAD_TIMEOUT, 300000).  %% 5 minutes for model loading/download
-define(DEFAULT_EMBED_TIMEOUT, 60000).  %% 60 seconds for embedding

%%====================================================================
%% API
%%====================================================================

%% @doc Initialize the Python environment.
%% Activates venv if configured and adds priv dir to Python path.
%% If preload was configured via barrel_embed_preload, path setup is skipped.
-spec init(map()) -> ok | {error, term()}.
init(Config) ->
    try
        %% If preload was configured, path is already set up
        case py_preload:has_preload() of
            true ->
                %% Preload already configured venv and path
                ok;
            false ->
                %% Activate venv if configured
                case maps:get(venv, Config, undefined) of
                    undefined -> ok;
                    Venv when is_list(Venv) ->
                        py:activate_venv(unicode:characters_to_binary(Venv));
                    Venv when is_binary(Venv) ->
                        py:activate_venv(Venv)
                end,

                %% Add priv dir to Python path
                PrivDir = get_priv_dir(),
                Code = iolist_to_binary([
                    <<"import sys\n">>,
                    <<"if '">>, PrivDir, <<"' not in sys.path:\n">>,
                    <<"    sys.path.insert(0, '">>, PrivDir, <<"')\n">>
                ]),
                case py:exec(Code) of
                    ok -> ok;
                    {error, _} = Err -> Err
                end
        end
    catch
        error:Reason ->
            {error, Reason}
    end.

%% @doc Load a model and return info with default timeout.
-spec load_model(binary(), binary()) -> {ok, map()} | {error, term()}.
load_model(Provider, Model) ->
    load_model(Provider, Model, ?DEFAULT_LOAD_TIMEOUT).

%% @doc Load a model and return info with specified timeout.
%% Provider can be: sentence_transformers, fastembed, splade, colbert, clip
-spec load_model(binary(), binary(), timeout()) -> {ok, map()} | {error, term()}.
load_model(Provider, Model, Timeout) ->
    try
        case py:call(?API_MODULE, load_model, [ensure_binary(Provider), ensure_binary(Model)], #{}, Timeout) of
            {ok, Map} when is_map(Map) ->
                {ok, normalize_map(Map)};
            {ok, Other} ->
                {error, {unexpected_result, Other}};
            {error, _} = Err ->
                Err
        end
    catch
        error:{python, Class, Msg, _Trace} ->
            {error, {python_error, Class, Msg}};
        error:Reason ->
            {error, Reason}
    end.

%% @doc Generate dense embeddings for texts with default timeout.
-spec embed(binary(), binary(), [binary()]) -> {ok, [[float()]]} | {error, term()}.
embed(Provider, Model, Texts) ->
    embed(Provider, Model, Texts, ?DEFAULT_EMBED_TIMEOUT).

%% @doc Generate dense embeddings for texts with specified timeout.
-spec embed(binary(), binary(), [binary()], timeout()) -> {ok, [[float()]]} | {error, term()}.
embed(Provider, Model, Texts, Timeout) ->
    try
        TextsBin = [ensure_binary(T) || T <- Texts],
        case py:call(?API_MODULE, embed, [ensure_binary(Provider), ensure_binary(Model), TextsBin], #{}, Timeout) of
            {ok, Embeddings} when is_list(Embeddings) ->
                {ok, Embeddings};
            {ok, Other} ->
                {error, {unexpected_result, Other}};
            {error, _} = Err ->
                Err
        end
    catch
        error:{python, Class, Msg, _Trace} ->
            {error, {python_error, Class, Msg}};
        error:Reason ->
            {error, Reason}
    end.

%% @doc Generate sparse embeddings (SPLADE).
-spec embed_sparse(binary(), binary(), [binary()]) -> {ok, [map()]} | {error, term()}.
embed_sparse(Provider, Model, Texts) ->
    try
        TextsBin = [ensure_binary(T) || T <- Texts],
        case py:call(?API_MODULE, embed_sparse, [ensure_binary(Provider), ensure_binary(Model), TextsBin], #{}, ?DEFAULT_EMBED_TIMEOUT) of
            {ok, Embeddings} when is_list(Embeddings) ->
                {ok, [normalize_sparse_vec(E) || E <- Embeddings]};
            {ok, Other} ->
                {error, {unexpected_result, Other}};
            {error, _} = Err ->
                Err
        end
    catch
        error:{python, Class, Msg, _Trace} ->
            {error, {python_error, Class, Msg}};
        error:Reason ->
            {error, Reason}
    end.

%% @doc Generate multi-vector embeddings (ColBERT).
-spec embed_multi(binary(), binary(), [binary()]) -> {ok, [[[float()]]]} | {error, term()}.
embed_multi(Provider, Model, Texts) ->
    try
        TextsBin = [ensure_binary(T) || T <- Texts],
        case py:call(?API_MODULE, embed_multi, [ensure_binary(Provider), ensure_binary(Model), TextsBin], #{}, ?DEFAULT_EMBED_TIMEOUT) of
            {ok, Embeddings} when is_list(Embeddings) ->
                {ok, Embeddings};
            {ok, Other} ->
                {error, {unexpected_result, Other}};
            {error, _} = Err ->
                Err
        end
    catch
        error:{python, Class, Msg, _Trace} ->
            {error, {python_error, Class, Msg}};
        error:Reason ->
            {error, Reason}
    end.

%% @doc Generate image embeddings (CLIP).
-spec embed_image(binary(), [binary()]) -> {ok, [[float()]]} | {error, term()}.
embed_image(Model, ImagesBase64) ->
    try
        ImagesBin = [ensure_binary(I) || I <- ImagesBase64],
        case py:call(?API_MODULE, embed_image, [ensure_binary(Model), ImagesBin], #{}, ?DEFAULT_EMBED_TIMEOUT) of
            {ok, Embeddings} when is_list(Embeddings) ->
                {ok, Embeddings};
            {ok, Other} ->
                {error, {unexpected_result, Other}};
            {error, _} = Err ->
                Err
        end
    catch
        error:{python, Class, Msg, _Trace} ->
            {error, {python_error, Class, Msg}};
        error:Reason ->
            {error, Reason}
    end.

%% @doc Unload a model to free memory.
-spec unload_model(binary(), binary()) -> boolean().
unload_model(Provider, Model) ->
    try
        case py:call(?API_MODULE, unload_model, [ensure_binary(Provider), ensure_binary(Model)]) of
            {ok, Bool} when is_boolean(Bool) -> Bool;
            {ok, _} -> false;
            {error, _} -> false
        end
    catch
        _:_ -> false
    end.

%% @doc List loaded models.
-spec loaded_models() -> [{binary(), binary()}].
loaded_models() ->
    try
        case py:call(?API_MODULE, loaded_models, []) of
            {ok, Models} when is_list(Models) -> Models;
            {ok, _} -> [];
            {error, _} -> []
        end
    catch
        _:_ -> []
    end.

%%====================================================================
%% Internal Functions
%%====================================================================

get_priv_dir() ->
    case code:priv_dir(barrel_embed) of
        {error, bad_name} -> <<"priv">>;
        Dir -> unicode:characters_to_binary(Dir)
    end.

ensure_binary(B) when is_binary(B) -> B;
ensure_binary(L) when is_list(L) -> unicode:characters_to_binary(L);
ensure_binary(A) when is_atom(A) -> atom_to_binary(A, utf8).

%% Normalize map keys from binary to atom where needed
normalize_map(Map) when is_map(Map) ->
    maps:fold(fun(K, V, Acc) ->
        Key = normalize_key(K),
        Acc#{Key => V}
    end, #{}, Map).

normalize_key(<<"dimensions">>) -> dimensions;
normalize_key(<<"vocab_size">>) -> vocab_size;
normalize_key(<<"model">>) -> model;
normalize_key(<<"backend">>) -> backend;
normalize_key(<<"type">>) -> type;
normalize_key(K) when is_binary(K) -> binary_to_atom(K, utf8);
normalize_key(K) when is_atom(K) -> K.

%% Normalize sparse vector map
normalize_sparse_vec(#{<<"indices">> := Indices, <<"values">> := Values}) ->
    #{indices => Indices, values => Values};
normalize_sparse_vec(#{indices := _, values := _} = Vec) ->
    Vec;
normalize_sparse_vec(Other) ->
    Other.
