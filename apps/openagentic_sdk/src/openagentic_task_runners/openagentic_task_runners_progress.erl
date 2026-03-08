-module(openagentic_task_runners_progress).

-export([maybe_emit/2, sub_event_sink/2]).

sub_event_sink(Label0, Emit) ->
  fun (Event0) ->
    case Emit of
      F when is_function(F, 1) ->
        Event = openagentic_task_runners_utils:ensure_map(Event0),
        Label = openagentic_task_runners_utils:to_bin(Label0),
        Type = openagentic_task_runners_utils:to_bin(maps:get(type, Event, maps:get(<<"type">>, Event, <<>>))),
        handle_event(Type, Event, Label, F);
      _ -> ok
    end
  end.

handle_event(<<"tool.use">>, Event, Label, Emit) ->
  Name = openagentic_task_runners_utils:to_bin(maps:get(name, Event, maps:get(<<"name">>, Event, <<>>))),
  Input = openagentic_task_runners_utils:ensure_map(maps:get(input, Event, maps:get(<<"input">>, Event, #{}))),
  Emit(iolist_to_binary([<<"子任务(">>, Label, <<")：">>, humanize_tool_use(Name, Input)]));
handle_event(<<"tool.result">>, Event, Label, Emit) ->
  case maps:get(is_error, Event, maps:get(<<"is_error">>, Event, false)) of
    true ->
      ErrorType = openagentic_task_runners_utils:to_bin(maps:get(error_type, Event, maps:get(<<"error_type">>, Event, <<"error">>))),
      Emit(iolist_to_binary([<<"子任务(">>, Label, <<")：工具失败 ">>, ErrorType]));
    false -> ok
  end;
handle_event(<<"runtime.error">>, Event, Label, Emit) ->
  ErrorType = openagentic_task_runners_utils:to_bin(maps:get(error_type, Event, maps:get(<<"error_type">>, Event, <<"RuntimeError">>))),
  Emit(iolist_to_binary([<<"子任务(">>, Label, <<")：运行错误 ">>, ErrorType]));
handle_event(_Type, _Event, _Label, _Emit) ->
  ok.

humanize_tool_use(<<"Read">>, Input) -> tool_message(<<"读取文件：">>, tail(first_non_empty(Input, [<<"file_path">>, <<"filePath">>, file_path, filePath]), 60), <<"读取文件">>);
humanize_tool_use(<<"List">>, Input) -> tool_message(<<"列目录：">>, tail(first_non_empty(Input, [<<"path">>, path, <<"dir">>, dir, <<"directory">>, directory]), 60), <<"列目录">>);
humanize_tool_use(<<"Glob">>, Input) -> tool_message(<<"匹配文件：">>, head(first_non_empty(Input, [<<"pattern">>, pattern]), 60), <<"匹配文件">>);
humanize_tool_use(<<"Grep">>, Input) -> tool_message(<<"搜索文本：">>, head(first_non_empty(Input, [<<"pattern">>, pattern, <<"query">>, query]), 40), <<"搜索文本">>);
humanize_tool_use(<<"WebSearch">>, Input) -> tool_message(<<"网页搜索：">>, head(first_non_empty(Input, [<<"query">>, query]), 40), <<"网页搜索">>);
humanize_tool_use(<<"WebFetch">>, Input) -> tool_message(<<"抓取网页：">>, head(first_non_empty(Input, [<<"url">>, url]), 60), <<"抓取网页">>);
humanize_tool_use(Name0, _Input) ->
  Name = string:trim(openagentic_task_runners_utils:to_bin(Name0)),
  case byte_size(Name) > 0 of true -> Name; false -> <<"工具调用">> end.

tool_message(Prefix, Value, Default) ->
  case byte_size(Value) > 0 of true -> iolist_to_binary([Prefix, Value]); false -> Default end.

maybe_emit(F, Msg) when is_function(F, 1) ->
  try F(Msg) catch _:_ -> ok end;
maybe_emit(_, _) ->
  ok.

head(undefined, _N) -> <<>>;
head(null, _N) -> <<>>;
head(B0, N0) ->
  B = string:trim(openagentic_task_runners_utils:to_bin(B0)),
  N = erlang:max(0, N0),
  case byte_size(B) =< N of true -> B; false -> binary:part(B, 0, N) end.

tail(undefined, _N) -> <<>>;
tail(null, _N) -> <<>>;
tail(B0, N0) ->
  B = string:trim(openagentic_task_runners_utils:to_bin(B0)),
  N = erlang:max(0, N0),
  Sz = byte_size(B),
  case Sz =< N of true -> B; false -> binary:part(B, Sz - N, N) end.

first_non_empty(_Map, []) -> undefined;
first_non_empty(Map, [Key | Rest]) ->
  case maps:get(Key, Map, undefined) of
    undefined -> first_non_empty(Map, Rest);
    Value ->
      Bin = openagentic_task_runners_utils:to_bin(Value),
      case byte_size(string:trim(Bin)) > 0 of true -> Bin; false -> first_non_empty(Map, Rest) end
  end.
