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
    barrel_embed_sup:start_link().

stop(_State) ->
    ok.
