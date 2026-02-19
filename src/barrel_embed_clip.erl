%%%-------------------------------------------------------------------
%%% @doc CLIP image/text embedding provider
%%%
%%% Uses erlang_python with CLIP (Contrastive Language-Image Pre-training)
%%% models for cross-modal embeddings. Both images and text are encoded into
%%% the same vector space, enabling image-text similarity search.
%%%
%%% == Requirements ==
%%% ```
%%% pip install transformers torch pillow
%%% '''
%%%
%%% == Configuration ==
%%% ```
%%% Config = #{
%%%     venv => "/path/to/.venv",                  %% Virtualenv path (recommended)
%%%     model => "openai/clip-vit-base-patch32",   %% Model name (default)
%%%     timeout => 120000                          %% Timeout in ms (default)
%%% }.
%%% '''
%%%
%%% When `venv' is specified, the provider uses the venv's Python executable
%%% and properly activates the venv environment.
%%%
%%% == Cross-Modal Search ==
%%% CLIP enables searching images with text queries and vice versa:
%%% ```
%%% %% Embed an image
%%% {ok, ImgVec} = embed_image(ImageBase64, Config),
%%%
%%% %% Embed a text query (in same space!)
%%% {ok, TextVec} = embed(<<"a photo of a cat">>, Config),
%%%
%%% %% Now you can compare ImgVec and TextVec with cosine similarity
%%% '''
%%%
%%% == Supported Models ==
%%% - `"openai/clip-vit-base-patch32"' - Default, 512 dimensions, fast
%%% - `"openai/clip-vit-base-patch16"' - 512 dimensions, higher quality
%%% - `"openai/clip-vit-large-patch14"' - 768 dimensions, best quality
%%% - `"laion/CLIP-ViT-B-32-laion2B-s34B-b79K"' - 512 dims, LAION trained
%%%
%%% == Use Cases ==
%%% - Image search with text queries
%%% - Finding similar images
%%% - Multi-modal content retrieval
%%% - Zero-shot image classification
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(barrel_embed_clip).
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

%% Image embedding API
-export([
    embed_image/2,
    embed_image_batch/2
]).

-define(DEFAULT_MODEL, "openai/clip-vit-base-patch32").
-define(DEFAULT_TIMEOUT, 120000).
-define(DEFAULT_DIMENSION, 512).
-define(PROVIDER, <<"clip">>).

%%====================================================================
%% Behaviour Callbacks
%%====================================================================

%% @doc Provider name.
-spec name() -> atom().
name() -> clip.

%% @doc Get dimension for this provider.
-spec dimension(map()) -> pos_integer().
dimension(Config) ->
    maps:get(dimension, Config, ?DEFAULT_DIMENSION).

%% @doc Initialize the provider.
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
                {ok, _} ->
                    %% No dimensions in response, use default
                    {ok, Config#{
                        dimension => ?DEFAULT_DIMENSION,
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

%% @doc Generate text embedding (for cross-modal search).
%% Text embeddings are in the same space as image embeddings.
-spec embed(binary(), map()) -> {ok, [float()]} | {error, term()}.
embed(Text, Config) ->
    case embed_batch([Text], Config) of
        {ok, [Embedding]} -> {ok, Embedding};
        {error, _} = Error -> Error
    end.

%% @doc Generate text embeddings for batch.
-spec embed_batch([binary()], map()) -> {ok, [[float()]]} | {error, term()}.
embed_batch(Texts, #{model := Model, provider := Provider, initialized := true}) ->
    TextsBin = [ensure_binary(T) || T <- Texts],
    barrel_embed_py:embed(Provider, Model, TextsBin);
embed_batch(_Texts, _Config) ->
    {error, not_initialized}.

%%====================================================================
%% Image Embedding API
%%====================================================================

%% @doc Generate embedding for a single image.
%% Image should be base64-encoded.
-spec embed_image(binary(), map()) -> {ok, [float()]} | {error, term()}.
embed_image(ImageBase64, Config) ->
    case embed_image_batch([ImageBase64], Config) of
        {ok, [Embedding]} -> {ok, Embedding};
        {error, _} = Error -> Error
    end.

%% @doc Generate embeddings for multiple images.
%% Images should be base64-encoded.
-spec embed_image_batch([binary()], map()) -> {ok, [[float()]]} | {error, term()}.
embed_image_batch(Images, #{model := Model, initialized := true}) ->
    ImagesBin = [ensure_binary(I) || I <- Images],
    barrel_embed_py:embed_image(Model, ImagesBin);
embed_image_batch(_Images, _Config) ->
    {error, not_initialized}.

%%====================================================================
%% Internal Functions
%%====================================================================

ensure_binary(B) when is_binary(B) -> B;
ensure_binary(L) when is_list(L) -> unicode:characters_to_binary(L).

%% @private
validate_model(Model) ->
    ModelBin = ensure_binary(Model),
    case is_known_model(ModelBin) of
        true -> ok;
        false ->
            error_logger:warning_msg(
                "Model ~s is not in the known list. "
                "It may still work if it's a valid CLIP model.~n",
                [ModelBin]
            )
    end.

%% @private
is_known_model(<<"openai/clip-vit-base-patch32">>) -> true;
is_known_model(<<"openai/clip-vit-base-patch16">>) -> true;
is_known_model(<<"openai/clip-vit-large-patch14">>) -> true;
is_known_model(<<"laion/CLIP-ViT-B-32-laion2B-s34B-b79K">>) -> true;
is_known_model(_) -> false.
