-module(openagentic_tool_lsp_config).

-export([load_opencode_config/1, parse_lsp_enabled/1, parse_lsp_servers/1, matching_servers/2]).

load_opencode_config(ProjectDir) ->
  A = filename:join([ProjectDir, "opencode.json"]),
  B = filename:join([ProjectDir, ".opencode", "opencode.json"]),
  Base = read_json_object_or_empty(A),
  Overlay = read_json_object_or_empty(B),
  {ok, deep_merge(Base, Overlay)}.

read_json_object_or_empty(Path) ->
  case file:read_file(Path) of
    {ok, Bin} ->
      try
        Obj0 = openagentic_json:decode(Bin),
        openagentic_tool_lsp_utils:ensure_map(Obj0)
      catch
        _:_ -> #{}
      end;
    _ ->
      #{}
  end.

deep_merge(A, B) ->
  case {is_map(A), is_map(B)} of
    {true, true} ->
      maps:fold(
        fun (K, V2, Acc) ->
          V1 = maps:get(K, Acc, undefined),
          Acc#{K => deep_merge(V1, V2)}
        end,
        A,
        B
      );
    _ ->
      case B of
        undefined -> A;
        _ -> B
      end
  end.

parse_lsp_enabled(Cfg) ->
  case maps:get(<<"lsp">>, Cfg, undefined) of
    false -> false;
    <<"false">> -> false;
    <<"0">> -> false;
    <<"no">> -> false;
    _ -> true
  end.

parse_lsp_servers(Cfg) ->
  Raw = maps:get(<<"lsp">>, Cfg, undefined),
  case Raw of
    M when is_map(M) ->
      maps:fold(fun parse_one_server/3, [], M);
    _ ->
      []
  end.

parse_one_server(Sid0, Spec0, Acc) ->
  Sid = string:trim(openagentic_tool_lsp_utils:to_bin(Sid0)),
  Spec = openagentic_tool_lsp_utils:ensure_map(Spec0),
  Disabled = maps:get(<<"disabled">>, Spec, false) =:= true,
  Cmd = maps:get(<<"command">>, Spec, undefined),
  CmdList = openagentic_tool_lsp_utils:string_list_non_empty(Cmd),
  ExtsPresent = maps:is_key(<<"extensions">>, Spec),
  Exts = case ExtsPresent of true -> openagentic_tool_lsp_utils:string_list_allow_empty(maps:get(<<"extensions">>, Spec, undefined)); false -> undefined end,
  case {Disabled, CmdList} of
    {true, undefined} ->
      Acc;
    {_, undefined} ->
      throw({invalid_input, iolist_to_binary([<<"lsp: server '">>, Sid, <<"' missing valid command">>])});
    _ ->
      case (not is_builtin_sid(Sid)) andalso (Disabled =:= false) andalso (Exts =:= undefined) of
        true -> throw({invalid_input, iolist_to_binary([<<"lsp: custom server '">>, Sid, <<"' requires 'extensions'">>])});
        false -> ok
      end,
      Env = openagentic_tool_lsp_utils:string_map(maps:get(<<"env">>, Spec, undefined)),
      Init = case maps:get(<<"initialization">>, Spec, undefined) of M when is_map(M) -> M; _ -> undefined end,
      Exts2 = case Exts of undefined -> []; L -> [openagentic_tool_lsp_utils:to_bin(X) || X <- L] end,
      [#{server_id => Sid, command => CmdList, extensions => Exts2, env => Env, initialization => Init} | Acc]
  end.

matching_servers(FullPath, Servers) ->
  Name = openagentic_tool_lsp_utils:to_bin(filename:basename(FullPath)),
  Key = openagentic_tool_lsp_utils:to_bin(filename:extension(FullPath)),
  [S || S <- Servers, match_server(S, Key, Name)].

match_server(S, Key, Name) ->
  Exts = maps:get(extensions, S, []),
  case Exts of
    [] -> true;
    _ -> lists:member(Key, Exts) orelse lists:member(Name, Exts)
  end.

is_builtin_sid(Sid0) ->
  Sid = openagentic_tool_lsp_utils:ensure_list(openagentic_tool_lsp_utils:to_bin(Sid0)),
  lists:member(Sid, builtin_sids()).

builtin_sids() ->
  [
    "deno","typescript","vue","eslint","oxlint","biome","gopls","ruby-lsp","ty","pyright","elixir-ls","zls",
    "csharp","fsharp","sourcekit-lsp","rust","clangd","svelte","astro","jdtls","kotlin-ls","yaml-ls","lua-ls",
    "php intelephense","prisma","dart","ocaml-lsp","bash","terraform","texlab","dockerfile","gleam","clojure-lsp",
    "nixd","tinymist","haskell-language-server"
  ].
