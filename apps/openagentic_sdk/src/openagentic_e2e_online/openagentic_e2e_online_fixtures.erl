-module(openagentic_e2e_online_fixtures).
-export([
  expected_nonce_line/1,
  expected_skill_marker_line/1,
  expected_slash_command_marker_line/1,
  make_tmp_project/1,
  prepare_global_skill/1,
  prepare_global_slash_command/1,
  write_tmp_project_files/1
]).

prepare_global_skill(SessionRoot0) ->
  SessionRoot = openagentic_e2e_online_utils:ensure_list(SessionRoot0),
  Dir = filename:join([SessionRoot, "skills", "e2e-skill"]),
  ok = openagentic_e2e_online_utils:ensure_dir(filename:join([Dir, "x"])),
  Path = filename:join([Dir, "SKILL.md"]),
  Marker = openagentic_e2e_online_utils:rand_hex(16),
  Body =
    <<
      "---\n"
      "name: e2e-skill\n"
      "description: online e2e skill\n"
      "---\n"
      "\n"
      "# e2e-skill\n"
      "\n"
      "This is a generated skill for online E2E.\n"
      "\n"
      "MARKER=", Marker/binary, "\n"
    >>,
  ok = file:write_file(Path, Body),
  ok.

prepare_global_slash_command(SessionRoot0) ->
  SessionRoot = openagentic_e2e_online_utils:ensure_list(SessionRoot0),
  Conf = filename:join([SessionRoot, "opencode-config"]),
  ok = openagentic_e2e_online_utils:ensure_dir(filename:join([Conf, "x"])),
  true = os:putenv("OPENCODE_CONFIG_DIR", Conf),
  CmdDir = filename:join([Conf, "commands"]),
  ok = openagentic_e2e_online_utils:ensure_dir(filename:join([CmdDir, "x"])),
  Path = filename:join([CmdDir, "e2e.md"]),
  Marker = openagentic_e2e_online_utils:rand_hex(16),
  Body =
    <<
      "# e2e\n"
      "\n"
      "MARKER=", Marker/binary, "\n"
      "args=${args}\n"
      "path=${path}\n"
    >>,
  ok = file:write_file(Path, Body),
  ok.

make_tmp_project(RepoRoot0) ->
  RepoRoot = openagentic_e2e_online_utils:ensure_list(RepoRoot0),
  Base = filename:join([RepoRoot, ".tmp", "e2e-online-project"]),
  Id = lists:flatten(io_lib:format("~p_~p", [erlang:system_time(millisecond), erlang:unique_integer([positive, monotonic])])),
  Dir = filename:join([Base, Id]),
  ok = openagentic_e2e_online_utils:ensure_dir(filename:join([Dir, "x"])),
  Dir.

write_tmp_project_files(Dir0) ->
  Dir = openagentic_e2e_online_utils:ensure_list(Dir0),
  Nonce = openagentic_e2e_online_utils:rand_hex(16),
  ok = file:write_file(filename:join([Dir, "hello.txt"]), <<"hello world\nneedle here\n">>),
  ok = file:write_file(filename:join([Dir, "notes.txt"]), <<"some notes\n">>),
  ok = file:write_file(filename:join([Dir, "nonce.txt"]), <<"NONCE=", Nonce/binary, "\n">>),
  SrcDir = filename:join([Dir, "src"]),
  ok = openagentic_e2e_online_utils:ensure_dir(filename:join([SrcDir, "x"])),
  ok = file:write_file(filename:join([SrcDir, "a.txt"]), <<"alpha\n">>),
  ok.

expected_nonce_line(TmpProject0) ->
  TmpProject = openagentic_e2e_online_utils:ensure_list(TmpProject0),
  Path = filename:join([TmpProject, "nonce.txt"]),
  case file:read_file(Path) of
    {ok, Bin} ->
      Line = string:trim(openagentic_e2e_online_utils:to_bin(Bin)),
      case byte_size(Line) > 0 of true -> Line; false -> <<"MISSING_NONCE">> end;
    _ ->
      <<"MISSING_NONCE">>
  end.

expected_skill_marker_line(Cfg0) ->
  Cfg = openagentic_e2e_online_utils:ensure_map(Cfg0),
  SessionRoot = openagentic_e2e_online_utils:ensure_list(maps:get(session_root, Cfg)),
  Path = filename:join([SessionRoot, "skills", "e2e-skill", "SKILL.md"]),
  case file:read_file(Path) of
    {ok, Bin} ->
      case extract_line_with_prefix(Bin, <<"MARKER=">>) of
        {ok, Line} -> Line;
        _ -> <<"MISSING_MARKER_SKILL">>
      end;
    _ ->
      <<"MISSING_MARKER_SKILL">>
  end.

expected_slash_command_marker_line(Cfg0) ->
  Cfg = openagentic_e2e_online_utils:ensure_map(Cfg0),
  SessionRoot = openagentic_e2e_online_utils:ensure_list(maps:get(session_root, Cfg)),
  Path = filename:join([SessionRoot, "opencode-config", "commands", "e2e.md"]),
  case file:read_file(Path) of
    {ok, Bin} ->
      case extract_line_with_prefix(Bin, <<"MARKER=">>) of
        {ok, Line} -> Line;
        _ -> <<"MISSING_MARKER_CMD">>
      end;
    _ ->
      <<"MISSING_MARKER_CMD">>
  end.

extract_line_with_prefix(Text0, Prefix0) ->
  Text = openagentic_e2e_online_utils:to_bin(Text0),
  Prefix = openagentic_e2e_online_utils:to_bin(Prefix0),
  Lines = binary:split(Text, <<"\n">>, [global]),
  case [string:trim(L, trailing, "\r") || L <- Lines, starts_with(L, Prefix)] of
    [Line | _] -> {ok, openagentic_e2e_online_utils:to_bin(Line)};
    [] -> {error, not_found}
  end.

starts_with(Bin0, Prefix0) ->
  Bin = openagentic_e2e_online_utils:to_bin(Bin0),
  Prefix = openagentic_e2e_online_utils:to_bin(Prefix0),
  Bs = byte_size(Bin),
  Ps = byte_size(Prefix),
  Bs >= Ps andalso binary:part(Bin, 0, Ps) =:= Prefix.
