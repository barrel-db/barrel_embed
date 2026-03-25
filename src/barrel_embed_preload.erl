%%%-------------------------------------------------------------------
%%% @doc Model preloading for barrel_embed
%%%
%%% Uses py_preload from erlang_python 2.2+ to preload embedding models
%%% during Python interpreter initialization, eliminating first-request latency.
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(barrel_embed_preload).

-export([
    setup/0,
    setup/1,
    generate_preload_code/2,
    generate_preload_code/3,
    clear/0
]).

%%====================================================================
%% API
%%====================================================================

%% @doc Setup preload from application environment.
%% Reads preload_models and venv from barrel_embed app env.
-spec setup() -> ok | {error, term()}.
setup() ->
    Models = application:get_env(barrel_embed, preload_models, []),
    Venv = application:get_env(barrel_embed, venv, undefined),
    setup(#{models => Models, venv => Venv}).

%% @doc Setup preload with explicit configuration.
%% Config keys:
%%   - models: [{Provider, ModelName}] list of models to preload
%%   - venv: optional venv path (binary or string)
-spec setup(map()) -> ok | {error, term()}.
setup(Config) ->
    Models = maps:get(models, Config, []),
    Venv = maps:get(venv, Config, undefined),
    case Models of
        [] ->
            %% No models to preload, but still setup path if no preload exists
            case py_preload:has_preload() of
                false ->
                    Code = generate_path_setup_code(Venv),
                    py_preload:set_code(Code);
                true ->
                    ok
            end;
        _ ->
            Code = generate_preload_code(Models, Venv),
            py_preload:set_code(Code)
    end.

%% @doc Generate Python preload code for the given models.
-spec generate_preload_code([{atom() | binary(), binary()}], binary() | string() | undefined) -> binary().
generate_preload_code(Models, Venv) ->
    generate_preload_code(Models, Venv, get_priv_dir()).

%% @doc Generate Python preload code with explicit priv dir.
-spec generate_preload_code([{atom() | binary(), binary()}], binary() | string() | undefined, binary()) -> binary().
generate_preload_code(Models, Venv, PrivDir) ->
    VenvCode = generate_venv_code(Venv),
    PathCode = generate_path_code(PrivDir),
    ImportCode = <<"from barrel_embed.nif_api import load_model\n">>,
    LoadCode = generate_load_calls(Models),
    iolist_to_binary([VenvCode, PathCode, ImportCode, LoadCode]).

%% @doc Clear any preload code.
-spec clear() -> ok.
clear() ->
    py_preload:clear_code().

%%====================================================================
%% Internal Functions
%%====================================================================

generate_path_setup_code(Venv) ->
    VenvCode = generate_venv_code(Venv),
    PathCode = generate_path_code(get_priv_dir()),
    iolist_to_binary([VenvCode, PathCode]).

generate_venv_code(undefined) ->
    <<>>;
generate_venv_code(Venv) when is_list(Venv) ->
    generate_venv_code(unicode:characters_to_binary(Venv));
generate_venv_code(Venv) when is_binary(Venv) ->
    iolist_to_binary([
        <<"import os, sys\n">>,
        <<"venv_path = '">>, escape_path(Venv), <<"'\n">>,
        <<"if sys.platform == 'win32':\n">>,
        <<"    site_packages = os.path.join(venv_path, 'Lib', 'site-packages')\n">>,
        <<"else:\n">>,
        <<"    py_version = f'python{sys.version_info.major}.{sys.version_info.minor}'\n">>,
        <<"    site_packages = os.path.join(venv_path, 'lib', py_version, 'site-packages')\n">>,
        <<"if site_packages not in sys.path:\n">>,
        <<"    sys.path.insert(0, site_packages)\n">>
    ]).

generate_path_code(PrivDir) ->
    iolist_to_binary([
        <<"import sys\n">>,
        <<"priv_dir = '">>, escape_path(PrivDir), <<"'\n">>,
        <<"if priv_dir not in sys.path:\n">>,
        <<"    sys.path.insert(0, priv_dir)\n">>
    ]).

generate_load_calls([]) ->
    <<>>;
generate_load_calls(Models) ->
    Lines = [generate_load_call(Provider, Model) || {Provider, Model} <- Models],
    iolist_to_binary(Lines).

generate_load_call(Provider, Model) ->
    ProviderBin = ensure_binary(Provider),
    ModelBin = ensure_binary(Model),
    iolist_to_binary([
        <<"load_model('">>, ProviderBin, <<"', '">>, ModelBin, <<"')\n">>
    ]).

get_priv_dir() ->
    case code:priv_dir(barrel_embed) of
        {error, bad_name} -> <<"priv">>;
        Dir -> unicode:characters_to_binary(Dir)
    end.

ensure_binary(B) when is_binary(B) -> B;
ensure_binary(L) when is_list(L) -> unicode:characters_to_binary(L);
ensure_binary(A) when is_atom(A) -> atom_to_binary(A, utf8).

escape_path(Path) ->
    %% Escape backslashes and single quotes for Python string
    binary:replace(
        binary:replace(Path, <<"\\">>, <<"\\\\">>, [global]),
        <<"'">>, <<"\\'">>, [global]
    ).
