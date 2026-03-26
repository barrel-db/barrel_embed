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
    %% Setup preload BEFORE starting erlang_python so models are
    %% preloaded during interpreter initialization
    barrel_embed_preload:setup(),

    %% Ensure erlang_python is started (should already be via application deps)
    case application:ensure_all_started(erlang_python) of
        {ok, _} -> ok;
        {error, {already_started, _}} -> ok;
        {error, Reason} ->
            error_logger:error_msg("Failed to start erlang_python: ~p~n", [Reason])
    end,

    %% Ensure priv dir is in Python path (in case erlang_python was already running)
    Venv = application:get_env(barrel_embed, venv, undefined),
    barrel_embed_py:init(#{venv => Venv}),

    barrel_embed_sup:start_link().

stop(_State) ->
    ok.
