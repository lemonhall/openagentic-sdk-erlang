-module(openagentic_tool_grep_filters).

-include_lib("kernel/include/file.hrl").

-export([file_matches_glob/2, file_readable_small/1, is_hidden_rel/1, is_sensitive_rel/1]).

-define(MAX_FILE_BYTES, 2097152).

file_readable_small(Path) ->
  case file:read_file_info(Path) of
    {ok, Info} ->
      Info#file_info.type =:= regular andalso
        (Info#file_info.size =:= undefined orelse Info#file_info.size =< ?MAX_FILE_BYTES);
    _ ->
      false
  end.

file_matches_glob(Rel0, FileGlobRe) ->
  Rel = openagentic_tool_grep_utils:ensure_list(Rel0),
  re:run(Rel, FileGlobRe, [{capture, none}]) =:= match.

is_hidden_rel(Rel0) ->
  Rel = openagentic_tool_grep_utils:ensure_list(Rel0),
  Segments = [Segment || Segment <- string:split(Rel, "/", all), Segment =/= ""],
  lists:any(fun is_hidden_segment/1, Segments).

is_hidden_segment(Segment0) ->
  case openagentic_tool_grep_utils:ensure_list(Segment0) of
    [$. | _] -> true;
    _ -> false
  end.

is_sensitive_rel(Rel0) ->
  Rel1 = openagentic_tool_grep_utils:ensure_list(Rel0),
  Rel = lists:flatten(string:replace(Rel1, "\\", "/", all)),
  Segments = [Segment || Segment <- string:split(Rel, "/", all), Segment =/= ""],
  Base0 = case Segments of [] -> ""; _ -> lists:last(Segments) end,
  Base = string:lowercase(Base0),
  case Base of
    ".env" -> true;
    "id_rsa" -> true;
    "id_ed25519" -> true;
    _ ->
      case lists:prefix(".env.", Base) of
        true -> Base =/= ".env.example";
        false -> lists:member(string:lowercase(filename:extension(Base)), [".pem", ".key", ".p12", ".pfx"])
      end
  end.
