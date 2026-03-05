-module(openagentic_web_static).

-behaviour(cowboy_handler).

-export([init/2]).

init(Req0, State0) ->
  State = ensure_map(State0),
  WebDir = ensure_list(maps:get(web_dir, State, ".")),
  Path0 = cowboy_req:path(Req0),
  Rel =
    case Path0 of
      <<"/">> -> "index.html";
      _ ->
        %% Strip leading "/"
        case Path0 of
          <<"/", Rest/binary>> -> ensure_list(Rest);
          _ -> ensure_list(Path0)
        end
    end,
  case openagentic_fs:is_safe_rel_path(Rel) of
    false ->
      Req1 = cowboy_req:reply(404, #{<<"content-type">> => <<"text/plain; charset=utf-8">>}, <<"not found">>, Req0),
      {ok, Req1, State};
    true ->
      Full = filename:join([WebDir, Rel]),
      case file:read_file(Full) of
        {ok, Bin} ->
          CT = content_type(Rel),
          Headers = #{<<"content-type">> => CT, <<"cache-control">> => <<"no-store">>},
          Req1 = cowboy_req:reply(200, Headers, Bin, Req0),
          {ok, Req1, State};
        _ ->
          Req1 = cowboy_req:reply(404, #{<<"content-type">> => <<"text/plain; charset=utf-8">>}, <<"not found">>, Req0),
          {ok, Req1, State}
      end
  end.

content_type(Rel0) ->
  Rel = ensure_list(Rel0),
  case filename:extension(Rel) of
    ".html" -> <<"text/html; charset=utf-8">>;
    ".css" -> <<"text/css; charset=utf-8">>;
    ".js" -> <<"application/javascript; charset=utf-8">>;
    ".svg" -> <<"image/svg+xml">>;
    ".png" -> <<"image/png">>;
    ".ico" -> <<"image/x-icon">>;
    _ -> <<"application/octet-stream">>
  end.

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) -> maps:from_list(L);
ensure_map(_) -> #{}.

ensure_list(B) when is_binary(B) -> binary_to_list(B);
ensure_list(L) when is_list(L) -> L;
ensure_list(A) when is_atom(A) -> atom_to_list(A);
ensure_list(Other) -> lists:flatten(io_lib:format("~p", [Other])).

