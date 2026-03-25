%% @doc Example demonstrating model preloading with barrel_embed
%%
%% This example shows how preloaded models are immediately available
%% without the cold-start delay of loading models on first use.
%%
%% Run with Docker:
%%   cd examples/preload
%%   docker compose up --build
%%
%% Or manually in rebar3 shell:
%%   preload_example:run().
%%
-module(preload_example).

-export([run/0, embed_texts/0]).

%% @doc Run the full example
run() ->
    io:format("~n=== Barrel Embed Preload Example ===~n~n"),

    io:format("Preload was configured at application startup.~n"),
    io:format("Models are loaded during Python interpreter init.~n~n"),

    %% Check if preload is active
    case py_preload:has_preload() of
        true ->
            io:format("Preload is ACTIVE~n"),
            Code = py_preload:get_code(),
            io:format("Preload code snippet:~n~s~n", [binary:part(Code, 0, min(200, byte_size(Code)))]);
        false ->
            io:format("Preload is NOT active~n")
    end,

    io:format("~n--- Generating Embeddings ---~n~n"),

    {Time, Result} = timer:tc(fun embed_texts/0),

    case Result of
        {ok, Embeddings} ->
            io:format("~nGenerated ~p embeddings in ~.2f seconds~n",
                      [length(Embeddings), Time / 1_000_000]),
            io:format("(Model was preloaded - no cold start delay)~n");
        {error, Reason} ->
            io:format("~nError: ~p~n", [Reason])
    end,

    io:format("~nExample completed.~n"),
    ok.

%% @doc Generate embeddings for sample texts
embed_texts() ->
    Model = <<"BAAI/bge-small-en-v1.5">>,

    %% First, ensure model is loaded (may download on first run)
    io:format("Loading model fastembed/~s (may download on first run)...~n", [Model]),
    case barrel_embed_py:load_model(<<"fastembed">>, Model, 600000) of
        {ok, Info} ->
            io:format("Model loaded: ~p dimensions~n", [maps:get(dimensions, Info)]);
        {error, LoadErr} ->
            io:format("Warning: load_model returned ~p~n", [LoadErr])
    end,

    Texts = [
        <<"The quick brown fox jumps over the lazy dog.">>,
        <<"Machine learning models can generate embeddings.">>,
        <<"Erlang is great for building concurrent systems.">>,
        <<"Docker containers provide isolated environments.">>,
        <<"Preloading models eliminates cold start latency.">>
    ],

    io:format("Embedding ~p texts...~n", [length(Texts)]),

    case barrel_embed_py:embed(<<"fastembed">>, Model, Texts) of
        {ok, Embeddings} ->
            io:format("Success! Each embedding has ~p dimensions.~n",
                      [length(hd(Embeddings))]),

            %% Show similarity between first two texts
            [E1, E2 | _] = Embeddings,
            Sim = cosine_similarity(E1, E2),
            io:format("Similarity between text 1 and 2: ~.4f~n", [Sim]),

            {ok, Embeddings};
        {error, _} = Err ->
            Err
    end.

%% @doc Calculate cosine similarity
cosine_similarity(V1, V2) ->
    Dot = lists:sum(lists:zipwith(fun(A, B) -> A * B end, V1, V2)),
    Norm1 = math:sqrt(lists:sum([X * X || X <- V1])),
    Norm2 = math:sqrt(lists:sum([X * X || X <- V2])),
    Dot / (Norm1 * Norm2).
