-module(openagentic_sse).

-export([new/0, feed/2]).

%% Minimal SSE decoder:
%% - Accepts binary chunks.
%% - Emits events when a blank line terminator is observed.
%% - Supports:
%%   - "event: <name>"
%%   - "data: <payload>" (can repeat, joined with "\n")
%% - Ignores:
%%   - comments ": ..."
%%   - unknown fields

-type state() :: #{
  buf := binary(),
  cur_event := binary() | undefined,
  cur_data := [binary()]
}.

-spec new() -> state().
new() ->
  #{buf => <<>>, cur_event => undefined, cur_data => []}.

-spec feed(state(), binary()) -> {state(), [map()]}.
feed(State0, Chunk) when is_map(State0), is_binary(Chunk) ->
  State1 = State0#{buf := <<(maps:get(buf, State0, <<>>))/binary, Chunk/binary>>},
  consume_lines(State1, []).

consume_lines(State0, AccEvents) ->
  Buf = maps:get(buf, State0, <<>>),
  case binary:match(Buf, <<"\n">>) of
    nomatch ->
      {State0, lists:reverse(AccEvents)};
    {Pos, 1} ->
      <<Line0:Pos/binary, _NL:1/binary, Rest/binary>> = Buf,
      Line = strip_cr(Line0),
      State1 = State0#{buf := Rest},
      {State2, NewEvents} = handle_line(State1, Line),
      consume_lines(State2, NewEvents ++ AccEvents)
  end.

strip_cr(<<>>) -> <<>>;
strip_cr(Bin) ->
  Sz = byte_size(Bin),
  case Sz of
    0 ->
      <<>>;
    _ ->
      RestSz = Sz - 1,
      case Bin of
        <<Rest:RestSz/binary, $\r>> -> Rest;
        _ -> Bin
      end
  end.

handle_line(State0, <<>>) ->
  finalize_event(State0);
handle_line(State0, <<":", _/binary>>) ->
  {State0, []};
handle_line(State0, Line) ->
  case split_field(Line) of
    {<<"event">>, V} ->
      {State0#{cur_event := V}, []};
    {<<"data">>, V} ->
      Data0 = maps:get(cur_data, State0, []),
      {State0#{cur_data := [V | Data0]}, []};
    _ ->
      {State0, []}
  end.

split_field(Line) ->
  case binary:match(Line, <<":">>) of
    nomatch ->
      error;
    {Pos, 1} ->
      <<K:Pos/binary, _Colon:1/binary, V0/binary>> = Line,
      V = strip_one_space(V0),
      {trim(K), trim(V)}
  end.

strip_one_space(<<" ", Rest/binary>>) -> Rest;
strip_one_space(B) -> B.

trim(Bin) ->
  trim_left(trim_right(Bin)).

trim_left(<<" ", Rest/binary>>) -> trim_left(Rest);
trim_left(<<"\t", Rest/binary>>) -> trim_left(Rest);
trim_left(B) -> B.

trim_right(Bin) ->
  Sz = byte_size(Bin),
  case Sz of
    0 -> <<>>;
    _ ->
      case binary:at(Bin, Sz - 1) of
        $\s -> trim_right(binary:part(Bin, 0, Sz - 1));
        $\t -> trim_right(binary:part(Bin, 0, Sz - 1));
        _ -> Bin
      end
  end.

finalize_event(State0) ->
  DataLinesRev = maps:get(cur_data, State0, []),
  EvName = maps:get(cur_event, State0, undefined),
  case {EvName, DataLinesRev} of
    {undefined, []} ->
      {State0, []};
    _ ->
      DataLines = lists:reverse(DataLinesRev),
      Data = join_lines(DataLines),
      Ev = #{event => EvName, data => Data},
      State1 = State0#{cur_event := undefined, cur_data := []},
      {State1, [Ev]}
  end.

join_lines([]) -> <<>>;
join_lines([One]) -> One;
join_lines([H | T]) ->
  lists:foldl(fun (Line, Acc) -> <<Acc/binary, "\n", Line/binary>> end, H, T).
