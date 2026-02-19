%%%-------------------------------------------------------------------
%%% @doc Benchmark module for erlang_python NIF backend performance
%%%
%%% == Usage ==
%%% ```
%%% %% Run with defaults (100 texts, fastembed)
%%% barrel_embed_benchmark:run(#{venv => "/path/to/.venv"}).
%%%
%%% %% Run with custom options
%%% barrel_embed_benchmark:run(#{
%%%     count => 500,
%%%     model => <<"BAAI/bge-base-en-v1.5">>,
%%%     venv => "/path/to/.venv",
%%%     provider => fastembed
%%% }).
%%% '''
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(barrel_embed_benchmark).

-export([
    run/0,
    run/1,
    benchmark/3
]).

-define(DEFAULT_COUNT, 100).
-define(DEFAULT_MODEL, <<"BAAI/bge-small-en-v1.5">>).
-define(DEFAULT_PROVIDER, fastembed).
-define(SINGLE_TEXT_SAMPLES, 50).

%%====================================================================
%% API
%%====================================================================

%% @doc Run benchmark with default options.
-spec run() -> ok.
run() ->
    io:format("~nError: venv option is required~n"),
    io:format("Usage: barrel_embed_benchmark:run(#{venv => \"/path/to/.venv\"}).~n"),
    ok.

%% @doc Run benchmark with options.
-spec run(map()) -> ok.
run(Opts) ->
    case maps:get(venv, Opts, undefined) of
        undefined ->
            io:format("~nError: venv option is required~n"),
            io:format("Usage: barrel_embed_benchmark:run(#{venv => \"/path/to/.venv\"}).~n"),
            ok;
        Venv ->
            Count = maps:get(count, Opts, ?DEFAULT_COUNT),
            Model = maps:get(model, Opts, ?DEFAULT_MODEL),
            Provider = maps:get(provider, Opts, ?DEFAULT_PROVIDER),

            io:format("~n========================================~n"),
            io:format("  Benchmark: erlang_python NIF Backend~n"),
            io:format("========================================~n"),
            io:format("~nProvider: ~p~n", [Provider]),
            io:format("Model: ~s~n", [Model]),
            io:format("Text count: ~p~n", [Count]),
            io:format("Venv: ~s~n", [Venv]),

            Texts = generate_texts(Count),

            io:format("~n--- Results ---~n"),
            Results = benchmark(Texts, Model, Venv),
            print_results(Results),

            ok
    end.

%% @doc Benchmark NIF backend.
-spec benchmark([binary()], binary(), string() | binary()) -> map().
benchmark(Texts, Model, Venv) ->
    Provider = <<"fastembed">>,

    %% Cold start (initialize Python + load model)
    io:format("Measuring cold start...~n"),
    {ColdTime, InitResult} = timer:tc(fun() ->
        case barrel_embed_py:init(#{venv => Venv}) of
            ok ->
                barrel_embed_py:load_model(Provider, Model);
            Error ->
                Error
        end
    end),

    case InitResult of
        {ok, _Info} ->
            %% Warm single-text latency
            io:format("Measuring single-text latency (~p samples)...~n", [?SINGLE_TEXT_SAMPLES]),
            SingleTimes = measure_single_latency(Provider, Model, Texts, ?SINGLE_TEXT_SAMPLES),

            %% Batch throughput
            io:format("Measuring batch throughput...~n"),
            {BatchTime, BatchResult} = timer:tc(fun() ->
                barrel_embed_py:embed(Provider, Model, Texts)
            end),

            BatchOk = case BatchResult of
                {ok, _} -> true;
                _ -> false
            end,

            #{
                cold_start_ms => ColdTime / 1000,
                warm_p50_ms => percentile(SingleTimes, 50) / 1000,
                warm_p95_ms => percentile(SingleTimes, 95) / 1000,
                warm_p99_ms => percentile(SingleTimes, 99) / 1000,
                warm_mean_ms => lists:sum(SingleTimes) / length(SingleTimes) / 1000,
                batch_time_ms => BatchTime / 1000,
                batch_throughput => length(Texts) * 1000000 / BatchTime,
                batch_success => BatchOk
            };
        {error, Reason} ->
            io:format("Error initializing: ~p~n", [Reason]),
            #{error => Reason}
    end.

%%====================================================================
%% Internal Functions
%%====================================================================

generate_texts(Count) ->
    Sentences = [
        <<"The quick brown fox jumps over the lazy dog.">>,
        <<"Machine learning is transforming the way we process information.">>,
        <<"Erlang is a functional programming language designed for concurrent systems.">>,
        <<"Vector databases enable efficient similarity search at scale.">>,
        <<"Natural language processing helps computers understand human language.">>,
        <<"The weather today is sunny with a chance of afternoon showers.">>,
        <<"Python is widely used for data science and machine learning applications.">>,
        <<"Embeddings convert text into dense vector representations.">>,
        <<"The cat sat on the mat and watched the birds outside.">>,
        <<"Distributed systems require careful handling of network partitions.">>
    ],
    NumSentences = length(Sentences),
    [lists:nth((I rem NumSentences) + 1, Sentences) || I <- lists:seq(1, Count)].

measure_single_latency(Provider, Model, Texts, Samples) ->
    SampleTexts = lists:sublist(Texts, min(Samples, length(Texts))),
    [begin
        {T, _} = timer:tc(fun() ->
            barrel_embed_py:embed(Provider, Model, [Text])
        end),
        T
    end || Text <- SampleTexts].

percentile(List, P) when length(List) > 0 ->
    Sorted = lists:sort(List),
    N = length(Sorted),
    Rank = (P / 100) * (N - 1) + 1,
    K = trunc(Rank),
    D = Rank - K,
    case K >= N of
        true -> lists:nth(N, Sorted);
        false ->
            V1 = lists:nth(K, Sorted),
            V2 = lists:nth(K + 1, Sorted),
            V1 + D * (V2 - V1)
    end;
percentile(_, _) ->
    0.

print_results(#{error := Reason}) ->
    io:format("Error: ~p~n", [Reason]);
print_results(Results) ->
    io:format("~n  Cold start:       ~.1f ms~n", [maps:get(cold_start_ms, Results)]),
    io:format("  Warm latency:~n"),
    io:format("    p50:            ~.2f ms~n", [maps:get(warm_p50_ms, Results)]),
    io:format("    p95:            ~.2f ms~n", [maps:get(warm_p95_ms, Results)]),
    io:format("    p99:            ~.2f ms~n", [maps:get(warm_p99_ms, Results)]),
    io:format("    mean:           ~.2f ms~n", [maps:get(warm_mean_ms, Results)]),
    io:format("  Batch (~p texts):~n", [100]),
    io:format("    Total time:     ~.1f ms~n", [maps:get(batch_time_ms, Results)]),
    io:format("    Throughput:     ~.1f texts/sec~n", [maps:get(batch_throughput, Results)]).
