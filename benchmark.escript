#!/usr/bin/env escript
%%! -pa _build/default/lib/*/ebin

-mode(compile).

main([]) ->
    io:format("Usage: ./benchmark.escript <venv_path>~n"),
    halt(1);
main([VenvPath]) ->
    application:ensure_all_started(erlang_python),

    Venv = list_to_binary(VenvPath),
    Provider = <<"sentence_transformers">>,
    Model = <<"BAAI/bge-small-en-v1.5">>,

    %% Generate test texts
    Texts = generate_texts(100),
    SingleTexts = lists:sublist(Texts, 50),

    io:format("~n"),
    io:format("╔════════════════════════════════════════════════════════════╗~n"),
    io:format("║          BARREL_EMBED BACKEND BENCHMARK                    ║~n"),
    io:format("╠════════════════════════════════════════════════════════════╣~n"),
    io:format("║ Model: ~s~n", [Model]),
    io:format("║ Texts: ~p (batch), ~p (single latency samples)~n", [length(Texts), length(SingleTexts)]),
    io:format("╚════════════════════════════════════════════════════════════╝~n~n"),

    %% Benchmark NIF backend
    io:format("━━━ NIF Backend (erlang_python) ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━~n"),
    NifResults = benchmark_nif(Venv, Provider, Model, Texts, SingleTexts),

    io:format("~n━━━ Port Backend (stdio JSON) ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━~n"),
    PortResults = benchmark_port(VenvPath, Model, Texts, SingleTexts),

    %% Print comparison
    io:format("~n"),
    io:format("╔════════════════════════════════════════════════════════════╗~n"),
    io:format("║                      COMPARISON                            ║~n"),
    io:format("╠════════════════════════════════════════════════════════════╣~n"),
    print_comparison(NifResults, PortResults),
    io:format("╚════════════════════════════════════════════════════════════╝~n"),

    ok.

benchmark_nif(Venv, Provider, Model, Texts, SingleTexts) ->
    %% Cold start
    io:format("  Cold start (init + load model)...~n"),
    {ColdTime, _} = timer:tc(fun() ->
        barrel_embed_py:init(#{venv => Venv}),
        barrel_embed_py:load_model(Provider, Model)
    end),
    io:format("    Cold start: ~.1f ms~n", [ColdTime/1000]),

    %% Single text latency
    io:format("  Single text latency (~p samples)...~n", [length(SingleTexts)]),
    SingleTimes = [begin
        {T, _} = timer:tc(fun() ->
            barrel_embed_py:embed(Provider, Model, [Text])
        end),
        T
    end || Text <- SingleTexts],

    P50 = percentile(SingleTimes, 50) / 1000,
    P95 = percentile(SingleTimes, 95) / 1000,
    P99 = percentile(SingleTimes, 99) / 1000,
    Mean = lists:sum(SingleTimes) / length(SingleTimes) / 1000,

    io:format("    p50: ~.2f ms, p95: ~.2f ms, p99: ~.2f ms, mean: ~.2f ms~n", [P50, P95, P99, Mean]),

    %% Batch throughput
    io:format("  Batch throughput (~p texts)...~n", [length(Texts)]),
    {BatchTime, _} = timer:tc(fun() ->
        barrel_embed_py:embed(Provider, Model, Texts)
    end),
    Throughput = length(Texts) * 1000000 / BatchTime,
    io:format("    Batch time: ~.1f ms, throughput: ~.1f texts/sec~n", [BatchTime/1000, Throughput]),

    #{cold_start => ColdTime/1000, p50 => P50, p95 => P95, mean => Mean,
      batch_time => BatchTime/1000, throughput => Throughput}.

benchmark_port(VenvPath, Model, Texts, SingleTexts) ->
    Python = "python3",
    Args = ["-m", "barrel_embed", "--provider", "sentence_transformers",
            "--model", binary_to_list(Model)],
    PrivDir = get_priv_dir(),
    Opts = [{timeout, 300000}, {priv_dir, PrivDir}, {venv, VenvPath}],

    %% Cold start
    io:format("  Cold start (spawn port + load model)...~n"),
    {ColdTime, {ok, Server}} = timer:tc(fun() ->
        {ok, S} = barrel_embed_port_server:start_link(Python, Args, Opts),
        {ok, _} = barrel_embed_port_server:info(S, 300000),
        {ok, S}
    end),
    io:format("    Cold start: ~.1f ms~n", [ColdTime/1000]),

    %% Single text latency
    io:format("  Single text latency (~p samples)...~n", [length(SingleTexts)]),
    SingleTimes = [begin
        {T, _} = timer:tc(fun() ->
            barrel_embed_port_server:embed_batch(Server, [Text], 60000)
        end),
        T
    end || Text <- SingleTexts],

    P50 = percentile(SingleTimes, 50) / 1000,
    P95 = percentile(SingleTimes, 95) / 1000,
    P99 = percentile(SingleTimes, 99) / 1000,
    Mean = lists:sum(SingleTimes) / length(SingleTimes) / 1000,

    io:format("    p50: ~.2f ms, p95: ~.2f ms, p99: ~.2f ms, mean: ~.2f ms~n", [P50, P95, P99, Mean]),

    %% Batch throughput
    io:format("  Batch throughput (~p texts)...~n", [length(Texts)]),
    {BatchTime, _} = timer:tc(fun() ->
        barrel_embed_port_server:embed_batch(Server, Texts, 120000)
    end),
    Throughput = length(Texts) * 1000000 / BatchTime,
    io:format("    Batch time: ~.1f ms, throughput: ~.1f texts/sec~n", [BatchTime/1000, Throughput]),

    %% Cleanup
    barrel_embed_port_server:stop(Server),

    #{cold_start => ColdTime/1000, p50 => P50, p95 => P95, mean => Mean,
      batch_time => BatchTime/1000, throughput => Throughput}.

print_comparison(Nif, Port) ->
    ColdImprove = improvement(maps:get(cold_start, Port), maps:get(cold_start, Nif)),
    P50Improve = improvement(maps:get(p50, Port), maps:get(p50, Nif)),
    ThroughputRatio = maps:get(throughput, Nif) / maps:get(throughput, Port),

    io:format("║  Metric          │    NIF    │   Port    │  Improvement  ║~n"),
    io:format("║──────────────────┼───────────┼───────────┼───────────────║~n"),
    io:format("║  Cold start      │ ~7.0f ms │ ~7.0f ms │    ~+6.1f%     ║~n",
              [maps:get(cold_start, Nif), maps:get(cold_start, Port), ColdImprove]),
    io:format("║  Latency (p50)   │ ~7.2f ms │ ~7.2f ms │    ~+6.1f%     ║~n",
              [maps:get(p50, Nif), maps:get(p50, Port), P50Improve]),
    io:format("║  Latency (p95)   │ ~7.2f ms │ ~7.2f ms │               ║~n",
              [maps:get(p95, Nif), maps:get(p95, Port)]),
    io:format("║  Throughput      │ ~6.1f/s  │ ~6.1f/s  │      ~.2fx      ║~n",
              [maps:get(throughput, Nif), maps:get(throughput, Port), ThroughputRatio]).

improvement(Old, New) ->
    (Old - New) / Old * 100.

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
    end.

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

get_priv_dir() ->
    case code:priv_dir(barrel_embed) of
        {error, bad_name} -> "priv";
        Dir -> Dir
    end.
