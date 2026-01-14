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
    %% Initialize the Python execution queue
    barrel_embed_python_queue:init(),
    %% Return a dummy supervisor (no processes to supervise)
    barrel_embed_sup:start_link().

stop(_State) ->
    ok.
