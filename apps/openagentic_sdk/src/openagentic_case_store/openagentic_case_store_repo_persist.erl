-module(openagentic_case_store_repo_persist).
-export([write_json/2, persist_case_object/3, touch_object_type_registry/3, build_history_entry/2, object_history_path/2, append_history_line/2, read_json/1, decode_json/1, normalize_keys/1, normalize_key/1, update_object/3]).

write_json(Path, Obj0) ->
  Obj = openagentic_case_store_common_core:ensure_map(Obj0),
  ok = filelib:ensure_dir(filename:join([filename:dirname(Path), "x"])),
  Tmp = Path ++ ".tmp." ++ openagentic_case_store_common_core:ensure_list(openagentic_case_store_common_meta:new_id(<<"tmp">>)),
  Body = openagentic_json:encode_safe(Obj),
  ok = file:write_file(Tmp, <<Body/binary, "\n">>),
  case file:rename(Tmp, Path) of
    ok -> ok;
    _ ->
      _ = file:delete(Path),
      ok = file:rename(Tmp, Path),
      ok
  end.

persist_case_object(CaseDir, Path, Obj0) ->
  Obj = openagentic_case_store_common_core:ensure_map(Obj0),
  ok = write_json(Path, Obj),
  case openagentic_case_store_common_lookup:get_bin(Obj, [header, type], undefined) of
    undefined -> ok;
    <<>> -> ok;
    _ ->
      ok = touch_object_type_registry(CaseDir, Obj, Path),
      ok = append_history_line(openagentic_case_store_repo_paths:case_history_file(CaseDir), build_history_entry(Obj, Path)),
      case object_history_path(CaseDir, Obj) of
        undefined -> ok;
        ObjectHistoryPath -> append_history_line(ObjectHistoryPath, build_history_entry(Obj, Path))
      end
  end.

touch_object_type_registry(CaseDir, Obj, Path) ->
  RegistryPath = openagentic_case_store_repo_paths:object_type_registry_file(CaseDir),
  Registry0 =
    case filelib:is_file(RegistryPath) of
      true -> read_json(RegistryPath);
      false -> #{}
    end,
  Objects0 = openagentic_case_store_common_core:ensure_map(maps:get(objects, Registry0, #{})),
  ObjectId = openagentic_case_store_common_meta:id_of(Obj),
  Type = openagentic_case_store_common_lookup:get_in_map(Obj, [header, type], <<"unknown">>),
  Entry =
    openagentic_case_store_common_meta:compact_map(
      #{
        type => Type,
        revision => openagentic_case_store_common_lookup:get_in_map(Obj, [header, revision], undefined),
        updated_at => openagentic_case_store_common_lookup:get_in_map(Obj, [header, updated_at], undefined),
        path => openagentic_case_store_common_core:to_bin(Path)
      }
    ),
  Objects1 = Objects0#{ObjectId => Entry},
  TypeCounts =
    maps:fold(
      fun (_Id, Meta0, Acc0) ->
        Meta = openagentic_case_store_common_core:ensure_map(Meta0),
        MetaType = openagentic_case_store_common_lookup:get_bin(Meta, [type], <<"unknown">>),
        Acc0#{MetaType => maps:get(MetaType, Acc0, 0) + 1}
      end,
      #{},
      Objects1
    ),
  Registry1 =
    maps:merge(
      Registry0,
      #{
        schema_version => <<"case-governance-object-registry/v1">>,
        updated_at => openagentic_case_store_common_meta:now_ts(),
        objects => Objects1,
        type_counts => TypeCounts
      }
    ),
  write_json(RegistryPath, Registry1).

build_history_entry(Obj, Path) ->
  openagentic_case_store_common_meta:compact_map(
    #{
      at => openagentic_case_store_common_lookup:get_in_map(Obj, [header, updated_at], undefined),
      object_id => openagentic_case_store_common_meta:id_of(Obj),
      object_type => openagentic_case_store_common_lookup:get_in_map(Obj, [header, type], undefined),
      revision => openagentic_case_store_common_lookup:get_in_map(Obj, [header, revision], undefined),
      status => openagentic_case_store_common_lookup:get_in_map(Obj, [state, status], undefined),
      path => openagentic_case_store_common_core:to_bin(Path)
    }
  ).

object_history_path(CaseDir, Obj) ->
  case openagentic_case_store_common_lookup:get_in_map(Obj, [header, type], <<>>) of
    <<"monitoring_task">> -> openagentic_case_store_repo_paths:task_history_file(CaseDir, openagentic_case_store_common_meta:id_of(Obj));
    <<"task_version">> -> openagentic_case_store_repo_paths:task_history_file(CaseDir, openagentic_case_store_common_lookup:get_in_map(Obj, [links, task_id], undefined));
    <<"credential_binding">> -> openagentic_case_store_repo_paths:task_history_file(CaseDir, openagentic_case_store_common_lookup:get_in_map(Obj, [links, task_id], undefined));
    <<"monitoring_run">> -> openagentic_case_store_repo_paths:task_history_file(CaseDir, openagentic_case_store_common_lookup:get_in_map(Obj, [links, task_id], undefined));
    <<"run_attempt">> -> openagentic_case_store_repo_paths:task_history_file(CaseDir, openagentic_case_store_common_lookup:get_in_map(Obj, [links, task_id], undefined));
    <<"fact_report">> -> openagentic_case_store_repo_paths:task_history_file(CaseDir, openagentic_case_store_common_lookup:get_in_map(Obj, [links, task_id], undefined));
    <<"briefing">> -> openagentic_case_store_repo_paths:task_history_file(CaseDir, openagentic_case_store_common_lookup:get_in_map(Obj, [links, task_id], undefined));
    <<"task_template">> -> openagentic_case_store_repo_paths:template_history_file(CaseDir, openagentic_case_store_common_meta:id_of(Obj));
    _ -> undefined
  end.

append_history_line(Path, Entry0) ->
  Entry = openagentic_case_store_common_core:ensure_map(Entry0),
  ok = filelib:ensure_dir(filename:join([filename:dirname(Path), "x"])),
  Body = openagentic_json:encode_safe(Entry),
  file:write_file(Path, <<Body/binary, "\n">>, [append]).

read_json(Path) ->
  {ok, Bin} = file:read_file(Path),
  decode_json(Bin).

decode_json(Bin) ->
  normalize_keys(openagentic_json:decode(openagentic_case_store_common_core:trim_bin(Bin))).

normalize_keys(Map) when is_map(Map) ->
  maps:from_list([{normalize_key(K), normalize_keys(V)} || {K, V} <- maps:to_list(Map)]);
normalize_keys(List) when is_list(List) ->
  [normalize_keys(Item) || Item <- List];
normalize_keys(Other) -> Other.

normalize_key(K) when is_binary(K) -> binary_to_atom(K, utf8);
normalize_key(K) -> K.

update_object(Obj0, Now, Fun) ->
  Obj1 = openagentic_case_store_common_core:ensure_map(Fun(Obj0)),
  Header0 = maps:get(header, Obj1, #{}),
  Revision0 = openagentic_case_store_common_lookup:get_int(Header0, [revision], 0),
  Obj1#{header => Header0#{updated_at => Now, revision => Revision0 + 1}}.
