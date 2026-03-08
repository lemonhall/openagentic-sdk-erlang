-module(openagentic_case_scheduler_store).
-export([first_number/1, id_of/1, read_json/1, read_objects_in_dir/1, sort_by_created_at/1]).

sort_by_created_at(Objs0) ->
  lists:sort(
    fun (A0, B0) ->
      A = openagentic_case_scheduler_utils:ensure_map(A0),
      B = openagentic_case_scheduler_utils:ensure_map(B0),
      openagentic_case_scheduler_utils:get_in_map(A, [header, created_at], 0) =< openagentic_case_scheduler_utils:get_in_map(B, [header, created_at], 0)
    end,
    Objs0
  ).

read_objects_in_dir(Dir) ->
  [read_json(Path) || Path <- json_files(Dir)].

json_files(Dir) ->
  case file:list_dir(Dir) of
    {ok, Names} -> [filename:join([Dir, Name]) || Name <- Names, filename:extension(Name) =:= ".json"];
    _ -> []
  end.

read_json(Path) ->
  case file:read_file(Path) of
    {ok, Bin} -> normalize_keys(openagentic_json:decode(Bin));
    _ -> #{}
  end.

normalize_keys(Map) when is_map(Map) -> maps:from_list([{normalize_key(K), normalize_keys(V)} || {K, V} <- maps:to_list(Map)]);
normalize_keys(List) when is_list(List) -> [normalize_keys(Item) || Item <- List];
normalize_keys(Other) -> Other.

normalize_key(K) when is_binary(K) -> binary_to_atom(K, utf8);
normalize_key(K) -> K.

id_of(Obj0) -> openagentic_case_scheduler_utils:get_in_map(openagentic_case_scheduler_utils:ensure_map(Obj0), [header, id], undefined).

first_number([]) -> undefined;
first_number([Value | _Rest]) when is_integer(Value); is_float(Value) -> Value;
first_number([_ | Rest]) -> first_number(Rest).
