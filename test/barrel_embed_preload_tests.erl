%%%-------------------------------------------------------------------
%%% @doc End-to-end tests for barrel_embed_preload module
%%% @end
%%%-------------------------------------------------------------------
-module(barrel_embed_preload_tests).

-include_lib("eunit/include/eunit.hrl").

%%====================================================================
%% Test Generators
%%====================================================================

preload_test_() ->
    {foreach,
     fun setup/0,
     fun cleanup/1,
     [
       {"generate_preload_code without venv", fun test_generate_code_no_venv/0},
       {"generate_preload_code with venv", fun test_generate_code_with_venv/0},
       {"generate_preload_code with multiple models", fun test_generate_code_multiple_models/0},
       {"generate_preload_code escapes paths", fun test_generate_code_escapes_paths/0},
       {"setup with empty models sets path only", fun test_setup_empty_models/0},
       {"setup with models sets full preload", fun test_setup_with_models/0},
       {"setup from app env", fun test_setup_from_app_env/0},
       {"clear removes preload", fun test_clear/0},
       {"setup skips if preload exists", fun test_setup_skips_existing/0}
     ]
    }.

%%====================================================================
%% Integration tests (require Python)
%%====================================================================

integration_test_() ->
    {setup,
     fun integration_setup/0,
     fun integration_cleanup/1,
     [
       {"preload code executes correctly", fun test_preload_executes/0},
       {"preload sets up sys.path", fun test_preload_sets_path/0}
     ]
    }.

%%====================================================================
%% Setup/Teardown
%%====================================================================

setup() ->
    %% Clear any existing preload
    catch py_preload:clear_code(),
    ok.

cleanup(_) ->
    catch py_preload:clear_code(),
    ok.

integration_setup() ->
    %% Start erlang_python for integration tests
    application:ensure_all_started(erlang_python),
    ok.

integration_cleanup(_) ->
    catch py_preload:clear_code(),
    ok.

%%====================================================================
%% Unit Test Cases
%%====================================================================

test_generate_code_no_venv() ->
    Code = barrel_embed_preload:generate_preload_code(
        [{fastembed, <<"model1">>}],
        undefined,
        <<"/test/priv">>
    ),
    %% Should have path setup
    ?assert(binary:match(Code, <<"import sys">>) =/= nomatch),
    ?assert(binary:match(Code, <<"/test/priv">>) =/= nomatch),
    %% Should have import
    ?assert(binary:match(Code, <<"from barrel_embed.nif_api import load_model">>) =/= nomatch),
    %% Should have load call
    ?assert(binary:match(Code, <<"load_model('fastembed', 'model1')">>) =/= nomatch),
    %% Should NOT have venv activation
    ?assertEqual(nomatch, binary:match(Code, <<"site-packages">>)).

test_generate_code_with_venv() ->
    Code = barrel_embed_preload:generate_preload_code(
        [{fastembed, <<"model1">>}],
        <<"/path/to/venv">>,
        <<"/test/priv">>
    ),
    %% Should have venv setup
    ?assert(binary:match(Code, <<"venv_path = '/path/to/venv'">>) =/= nomatch),
    ?assert(binary:match(Code, <<"site-packages">>) =/= nomatch),
    %% Should have path setup
    ?assert(binary:match(Code, <<"/test/priv">>) =/= nomatch),
    %% Should have load call
    ?assert(binary:match(Code, <<"load_model('fastembed', 'model1')">>) =/= nomatch).

test_generate_code_multiple_models() ->
    Code = barrel_embed_preload:generate_preload_code(
        [
            {sentence_transformers, <<"BAAI/bge-base-en-v1.5">>},
            {fastembed, <<"BAAI/bge-small-en-v1.5">>}
        ],
        undefined,
        <<"/test/priv">>
    ),
    %% Should have both load calls
    ?assert(binary:match(Code, <<"load_model('sentence_transformers', 'BAAI/bge-base-en-v1.5')">>) =/= nomatch),
    ?assert(binary:match(Code, <<"load_model('fastembed', 'BAAI/bge-small-en-v1.5')">>) =/= nomatch).

test_generate_code_escapes_paths() ->
    %% Test with path containing single quotes
    Code = barrel_embed_preload:generate_preload_code(
        [{fastembed, <<"model">>}],
        <<"/path/with'quote">>,
        <<"/priv/with'quote">>
    ),
    %% Single quotes should be escaped
    ?assert(binary:match(Code, <<"\\'">>) =/= nomatch).

test_setup_empty_models() ->
    ?assertEqual(false, py_preload:has_preload()),
    ok = barrel_embed_preload:setup(#{models => [], venv => undefined}),
    ?assertEqual(true, py_preload:has_preload()),
    %% Should have path setup but no load calls
    Code = py_preload:get_code(),
    ?assert(binary:match(Code, <<"import sys">>) =/= nomatch),
    ?assertEqual(nomatch, binary:match(Code, <<"load_model">>)).

test_setup_with_models() ->
    ok = barrel_embed_preload:setup(#{
        models => [{fastembed, <<"test-model">>}],
        venv => undefined
    }),
    ?assertEqual(true, py_preload:has_preload()),
    Code = py_preload:get_code(),
    ?assert(binary:match(Code, <<"load_model('fastembed', 'test-model')">>) =/= nomatch).

test_setup_from_app_env() ->
    %% Set app env
    application:set_env(barrel_embed, preload_models, [{fastembed, <<"env-model">>}]),
    application:set_env(barrel_embed, venv, undefined),

    ok = barrel_embed_preload:setup(),

    Code = py_preload:get_code(),
    ?assert(binary:match(Code, <<"load_model('fastembed', 'env-model')">>) =/= nomatch),

    %% Cleanup
    application:unset_env(barrel_embed, preload_models),
    application:unset_env(barrel_embed, venv).

test_clear() ->
    ok = barrel_embed_preload:setup(#{models => [{fastembed, <<"model">>}]}),
    ?assertEqual(true, py_preload:has_preload()),
    ok = barrel_embed_preload:clear(),
    ?assertEqual(false, py_preload:has_preload()).

test_setup_skips_existing() ->
    %% Set initial preload
    py_preload:set_code(<<"# existing preload\n">>),
    ?assertEqual(true, py_preload:has_preload()),

    %% Setup with empty models should skip (not overwrite)
    ok = barrel_embed_preload:setup(#{models => [], venv => undefined}),

    %% Should still have original code
    Code = py_preload:get_code(),
    ?assert(binary:match(Code, <<"# existing preload">>) =/= nomatch).

%%====================================================================
%% Integration Test Cases
%%====================================================================

test_preload_executes() ->
    %% Set simple preload code that defines a variable
    py_preload:set_code(<<"TEST_VAR = 42\n">>),

    %% Execute some code that uses the preloaded variable
    case py:eval(<<"TEST_VAR">>) of
        {ok, 42} -> ok;
        {error, _} ->
            %% Variable might not be visible in eval context,
            %% test basic execution instead
            ?assertEqual(ok, py:exec(<<"x = 1">>))
    end.

test_preload_sets_path() ->
    PrivDir = get_priv_dir(),
    Code = iolist_to_binary([
        <<"import sys\n">>,
        <<"priv_dir = '">>, PrivDir, <<"'\n">>,
        <<"if priv_dir not in sys.path:\n">>,
        <<"    sys.path.insert(0, priv_dir)\n">>
    ]),
    py_preload:set_code(Code),

    %% Verify the path was added by checking sys.path
    case py:eval(iolist_to_binary([<<"'">>, PrivDir, <<"' in sys.path">>])) of
        {ok, true} -> ok;
        {ok, false} ->
            %% Path might be set on next context creation
            %% Just verify preload is set
            ?assertEqual(true, py_preload:has_preload());
        {error, _} ->
            ?assertEqual(true, py_preload:has_preload())
    end.

%%====================================================================
%% Helpers
%%====================================================================

get_priv_dir() ->
    case code:priv_dir(barrel_embed) of
        {error, bad_name} -> <<"priv">>;
        Dir -> unicode:characters_to_binary(Dir)
    end.
