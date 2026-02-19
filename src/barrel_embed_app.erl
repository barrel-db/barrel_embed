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
    %% Ensure erlang_python is started (should already be via application deps)
    case application:ensure_all_started(erlang_python) of
        {ok, _} -> ok;
        {error, {already_started, _}} -> ok;
        {error, Reason} ->
            error_logger:error_msg("Failed to start erlang_python: ~p~n", [Reason])
    end,
    barrel_embed_sup:start_link().

stop(_State) ->
    ok.
