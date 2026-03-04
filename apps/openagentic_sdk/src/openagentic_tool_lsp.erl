-module(openagentic_tool_lsp).

-behaviour(openagentic_tool).

-export([name/0, description/0, run/2]).

-define(DEFAULT_TIMEOUT_MS, 60000).

name() -> <<"lsp">>.

description() ->
  <<
    "Interact with Language Server Protocol (LSP) servers to get code intelligence features.\n",
    "\n",
    "Supported operations:\n",
    "- goToDefinition\n",
    "- findReferences\n",
    "- hover\n",
    "- documentSymbol\n",
    "- workspaceSymbol\n",
    "- goToImplementation\n",
    "- prepareCallHierarchy\n",
    "- incomingCalls\n",
    "- outgoingCalls\n",
    "\n",
    "All operations require:\n",
    "- filePath (or file_path)\n",
    "- line (1-based)\n",
    "- character (1-based)\n",
    "\n",
    "Note: LSP servers must be configured via OpenCode-style config (opencode.json / .opencode/opencode.json).\n"
  >>.

run(Input0, Ctx0) ->
  Input = ensure_map(Input0),
  Ctx = ensure_map(Ctx0),
  ProjectDir = ensure_list(maps:get(project_dir, Ctx, maps:get(projectDir, Ctx, "."))),

  Op0 = maps:get(<<"operation">>, Input, maps:get(operation, Input, undefined)),
  Op = string:trim(to_bin(Op0)),
  File0 =
    first_non_empty(Input, [
      <<"filePath">>, filePath,
      <<"file_path">>, file_path
    ]),
  Line = int_opt(Input, [<<"line">>, line], 0),
  Character = int_opt(Input, [<<"character">>, character], 0),

  case byte_size(Op) > 0 of
    false -> {error, {invalid_input, <<"lsp: 'operation' must be a non-empty string">>}};
    true ->
      case File0 of
        undefined -> {error, {invalid_input, <<"lsp: 'filePath' must be a non-empty string">>}};
        _ ->
          File = to_bin(File0),
          case {Line >= 1, Character >= 1} of
            {false, _} -> {error, {invalid_input, <<"lsp: 'line' must be an integer >= 1">>}};
            {_, false} -> {error, {invalid_input, <<"lsp: 'character' must be an integer >= 1">>}};
            _ ->
              case openagentic_fs:resolve_tool_path(ProjectDir, File) of
                {error, Reason} -> {error, Reason};
                {ok, FullPath0} ->
                  FullPath = ensure_list(FullPath0),
                  case filelib:is_regular(FullPath) of
                    false -> {error, {invalid_input, iolist_to_binary([<<"File not found: ">>, openagentic_fs:norm_abs_bin(FullPath)])}};
                    true ->
                      case load_opencode_config(ProjectDir) of
                        {ok, Cfg} ->
                          case parse_lsp_enabled(Cfg) of
                            false -> {error, {runtime_error, <<"lsp: disabled by config">>}};
                            true ->
                              Servers = parse_lsp_servers(Cfg),
                              do_lsp(Op, FullPath, Line, Character, ProjectDir, Servers)
                          end;
                        {error, Reason2} ->
                          {error, Reason2}
                      end
                  end
              end
          end
      end
  end.

do_lsp(Op, FullPath, Line, Character, ProjectDir, Servers0) ->
  Servers = matching_servers(FullPath, Servers0),
  case Servers of
    [] ->
      {error, {runtime_error, <<"No LSP server available for this file type.">>}};
    [S | _] ->
      try
        Result =
          with_client(
            S,
            ProjectDir,
            fun (Port) ->
              Buf0 = <<>>,
              State0 = #{next_id => 1},
              {Buf1, _InitRes, State1} = rpc_request(Port, Buf0, State0, <<"initialize">>, init_params(ProjectDir, S), ?DEFAULT_TIMEOUT_MS),
              ok = rpc_notify(Port, <<"initialized">>, #{}),
              ok = did_open(Port, FullPath),
              {Buf2, Result0, State2} = do_operation(Op, Port, Buf1, State1, FullPath, Line, Character),
              _ = shutdown_best_effort(Port, Buf2, State2),
              Result0
            end
          ),
        Title = iolist_to_binary([Op, <<" ">>, openagentic_fs:norm_abs_bin(FullPath), <<":">>, integer_to_binary(Line), <<":">>, integer_to_binary(Character)]),
        Empty = (Result =:= null) orelse (is_list(Result) andalso Result =:= []),
        Output =
          case Empty of
            true -> iolist_to_binary([<<"No results found for ">>, Op]);
            false -> openagentic_json:encode(Result)
          end,
        {ok, #{
          title => Title,
          metadata => #{result => Result},
          output => Output
        }}
      catch
        throw:Reason -> {error, Reason};
        C:R -> {error, {C, R}}
      end
  end.

do_operation(Op, Port, Buf0, State0, FullPath, Line, Character) ->
  Uri = file_uri(FullPath),
  Line0 = Line - 1,
  Char0 = Character - 1,
  case Op of
    <<"goToDefinition">> ->
      rpc_request(Port, Buf0, State0, <<"textDocument/definition">>, pos_params(Uri, Line0, Char0), ?DEFAULT_TIMEOUT_MS);
    <<"findReferences">> ->
      Params = #{
        <<"textDocument">> => #{<<"uri">> => Uri},
        <<"position">> => #{<<"line">> => Line0, <<"character">> => Char0},
        <<"context">> => #{<<"includeDeclaration">> => true}
      },
      rpc_request(Port, Buf0, State0, <<"textDocument/references">>, Params, ?DEFAULT_TIMEOUT_MS);
    <<"hover">> ->
      rpc_request(Port, Buf0, State0, <<"textDocument/hover">>, pos_params(Uri, Line0, Char0), ?DEFAULT_TIMEOUT_MS);
    <<"documentSymbol">> ->
      rpc_request(Port, Buf0, State0, <<"textDocument/documentSymbol">>, #{<<"textDocument">> => #{<<"uri">> => Uri}}, ?DEFAULT_TIMEOUT_MS);
    <<"workspaceSymbol">> ->
      rpc_request(Port, Buf0, State0, <<"workspace/symbol">>, #{<<"query">> => <<>>}, ?DEFAULT_TIMEOUT_MS);
    <<"goToImplementation">> ->
      rpc_request(Port, Buf0, State0, <<"textDocument/implementation">>, pos_params(Uri, Line0, Char0), ?DEFAULT_TIMEOUT_MS);
    <<"prepareCallHierarchy">> ->
      rpc_request(Port, Buf0, State0, <<"textDocument/prepareCallHierarchy">>, pos_params(Uri, Line0, Char0), ?DEFAULT_TIMEOUT_MS);
    <<"incomingCalls">> ->
      {Buf1, Items, State1} = rpc_request(Port, Buf0, State0, <<"textDocument/prepareCallHierarchy">>, pos_params(Uri, Line0, Char0), ?DEFAULT_TIMEOUT_MS),
      Item0 = first_object(Items),
      case Item0 of
        undefined -> {Buf1, [], State1};
        _ -> rpc_request(Port, Buf1, State1, <<"callHierarchy/incomingCalls">>, #{<<"item">> => Item0}, ?DEFAULT_TIMEOUT_MS)
      end;
    <<"outgoingCalls">> ->
      {Buf1, Items, State1} = rpc_request(Port, Buf0, State0, <<"textDocument/prepareCallHierarchy">>, pos_params(Uri, Line0, Char0), ?DEFAULT_TIMEOUT_MS),
      Item0 = first_object(Items),
      case Item0 of
        undefined -> {Buf1, [], State1};
        _ -> rpc_request(Port, Buf1, State1, <<"callHierarchy/outgoingCalls">>, #{<<"item">> => Item0}, ?DEFAULT_TIMEOUT_MS)
      end;
    _ ->
      throw({invalid_input, <<"lsp: unknown operation">>})
  end.

first_object(L) when is_list(L) ->
  case [X || X <- L, is_map(X)] of
    [H | _] -> H;
    [] -> undefined
  end;
first_object(_) ->
  undefined.

with_client(Server, ProjectDir, Fun) ->
  Cmd = maps:get(command, Server, []),
  [Exe0 | Args0] = [ensure_list(X) || X <- Cmd],
  case os:find_executable(Exe0) of
    false ->
      throw({runtime_error, iolist_to_binary([<<"lsp: executable not found: ">>, to_bin(Exe0)])});
    Exe ->
      Port = open_port({spawn_executable, Exe}, [binary, exit_status, use_stdio, {args, Args0}, {cd, ProjectDir}]),
      try
        Fun(Port)
      after
        _ = catch erlang:port_close(Port)
      end
  end.

shutdown_best_effort(Port, Buf0, State0) ->
  try
    {Buf1, _Res, State1} = rpc_request(Port, Buf0, State0, <<"shutdown">>, #{}, 5000),
    _ = rpc_notify(Port, <<"exit">>, null),
    {Buf1, State1}
  catch
    _:_ -> {Buf0, State0}
  end.

did_open(Port, FullPath) ->
  Uri = file_uri(FullPath),
  Text = case file:read_file(FullPath) of {ok, B} -> to_bin(B); _ -> <<>> end,
  Lang = guess_language_id(filename:basename(FullPath)),
  Params = #{
    <<"textDocument">> => #{
      <<"uri">> => Uri,
      <<"languageId">> => Lang,
      <<"version">> => 1,
      <<"text">> => bin_to_utf8(Text)
    }
  },
  rpc_notify(Port, <<"textDocument/didOpen">>, Params).

guess_language_id(Name0) ->
  Name = string:lowercase(to_bin(Name0)),
  case ends_with(Name, <<".kt">>) orelse ends_with(Name, <<".kts">>) of
    true -> <<"kotlin">>;
    false ->
      case ends_with(Name, <<".java">>) of
        true -> <<"java">>;
        false ->
          case ends_with(Name, <<".py">>) of
            true -> <<"python">>;
            false ->
              case ends_with(Name, <<".ts">>) of
                true -> <<"typescript">>;
                false ->
                  case ends_with(Name, <<".js">>) of
                    true -> <<"javascript">>;
                    false ->
                      case ends_with(Name, <<".rs">>) of
                        true -> <<"rust">>;
                        false ->
                          case ends_with(Name, <<".go">>) of
                            true -> <<"go">>;
                            false -> <<"plaintext">>
                          end
                      end
                  end
              end
          end
      end
  end.

file_uri(Path0) ->
  Norm = openagentic_fs:norm_abs_bin(Path0),
  Prefix = case binary:at(Norm, 0) of $/ -> <<"file://">>; _ -> <<"file:///">> end,
  <<Prefix/binary, Norm/binary>>.

init_params(ProjectDir, Server) ->
  RootUri = file_uri(ProjectDir),
  Base = #{
    <<"processId">> => null,
    <<"rootUri">> => RootUri,
    <<"capabilities">> => #{},
    <<"clientInfo">> => #{<<"name">> => <<"openagentic-sdk-erlang">>, <<"version">> => <<"0.1">>}
  },
  case maps:get(initialization, Server, undefined) of
    undefined -> Base;
    Init -> Base#{<<"initializationOptions">> => Init}
  end.

pos_params(Uri, Line0, Char0) ->
  #{
    <<"textDocument">> => #{<<"uri">> => Uri},
    <<"position">> => #{<<"line">> => Line0, <<"character">> => Char0}
  }.

rpc_notify(Port, Method, Params) ->
  Msg = #{
    <<"jsonrpc">> => <<"2.0">>,
    <<"method">> => Method,
    <<"params">> => Params
  },
  send_jsonrpc(Port, Msg).

rpc_request(Port, Buf0, State0, Method, Params, TimeoutMs) ->
  Id = maps:get(next_id, State0, 1),
  State1 = State0#{next_id := Id + 1},
  Req = #{
    <<"jsonrpc">> => <<"2.0">>,
    <<"id">> => Id,
    <<"method">> => Method,
    <<"params">> => Params
  },
  ok = send_jsonrpc(Port, Req),
  {Buf1, Resp} = recv_response_id(Port, Buf0, Id, TimeoutMs),
  Result = maps:get(<<"result">>, Resp, null),
  {Buf1, Result, State1}.

recv_response_id(Port, Buf0, Id, TimeoutMs) ->
  Deadline = erlang:monotonic_time(millisecond) + TimeoutMs,
  recv_loop(Port, Buf0, Id, Deadline).

recv_loop(Port, Buf0, Id, Deadline) ->
  Now = erlang:monotonic_time(millisecond),
  Remaining = erlang:max(0, Deadline - Now),
  case parse_one(Buf0) of
    {ok, Msg, Rest} ->
      case maps:get(<<"id">>, Msg, undefined) of
        Id ->
          {Rest, Msg};
        _ ->
          recv_loop(Port, Rest, Id, Deadline)
      end;
    more ->
      receive
        {Port, {data, Bin}} when is_binary(Bin) ->
          recv_loop(Port, <<Buf0/binary, Bin/binary>>, Id, Deadline);
        {Port, {exit_status, Code}} ->
          throw({runtime_error, iolist_to_binary([<<"lsp: server exited: ">>, integer_to_binary(Code)])})
      after Remaining ->
        throw({runtime_error, <<"lsp: timeout waiting for response">>})
      end
  end.

send_jsonrpc(Port, Obj) ->
  Body = openagentic_json:encode(Obj),
  Header = iolist_to_binary([<<"Content-Length: ">>, integer_to_binary(byte_size(Body)), <<"\r\n\r\n">>]),
  port_command(Port, <<Header/binary, Body/binary>>),
  ok.

parse_one(Buf) ->
  case binary:match(Buf, <<"\r\n\r\n">>) of
    nomatch ->
      more;
    {HdrEnd, _} ->
      HeaderBin = binary:part(Buf, 0, HdrEnd),
      Rest0 = binary:part(Buf, HdrEnd + 4, byte_size(Buf) - (HdrEnd + 4)),
      case parse_content_length(HeaderBin) of
        {ok, Len} ->
          case byte_size(Rest0) >= Len of
            true ->
              Body = binary:part(Rest0, 0, Len),
              Rest = binary:part(Rest0, Len, byte_size(Rest0) - Len),
              {ok, ensure_map(openagentic_json:decode(Body)), Rest};
            false ->
              more
          end;
        _ ->
          more
      end
  end.

parse_content_length(HeaderBin) ->
  Lines = binary:split(HeaderBin, <<"\r\n">>, [global]),
  parse_len_lines(Lines).

parse_len_lines([]) -> {error, no_length};
parse_len_lines([L | T]) ->
  case string:lowercase(L) of
    <<"content-length:", Rest/binary>> ->
      Val = string:trim(Rest),
      case (catch binary_to_integer(Val)) of
        I when is_integer(I) -> {ok, I};
        _ -> {error, bad_length}
      end;
    _ ->
      parse_len_lines(T)
  end.

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
        ensure_map(Obj0)
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
  Sid = string:trim(to_bin(Sid0)),
  Spec = ensure_map(Spec0),
  Disabled = maps:get(<<"disabled">>, Spec, false) =:= true,
  Cmd = maps:get(<<"command">>, Spec, undefined),
  CmdList = string_list_non_empty(Cmd),
  ExtsPresent = maps:is_key(<<"extensions">>, Spec),
  Exts = case ExtsPresent of true -> string_list_allow_empty(maps:get(<<"extensions">>, Spec, undefined)); false -> undefined end,
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
      Env = string_map(maps:get(<<"env">>, Spec, undefined)),
      Init = case maps:get(<<"initialization">>, Spec, undefined) of M when is_map(M) -> M; _ -> undefined end,
      Exts2 = case Exts of undefined -> []; L -> [to_bin(X) || X <- L] end,
      [#{server_id => Sid, command => CmdList, extensions => Exts2, env => Env, initialization => Init} | Acc]
  end.

matching_servers(FullPath, Servers) ->
  Name = to_bin(filename:basename(FullPath)),
  Key = to_bin(filename:extension(FullPath)),
  [S || S <- Servers, match_server(S, Key, Name)].

match_server(S, Key, Name) ->
  Exts = maps:get(extensions, S, []),
  case Exts of
    [] -> true;
    _ -> lists:member(Key, Exts) orelse lists:member(Name, Exts)
  end.

is_builtin_sid(Sid0) ->
  Sid = ensure_list(to_bin(Sid0)),
  lists:member(Sid, builtin_sids()).

builtin_sids() ->
  [
    "deno","typescript","vue","eslint","oxlint","biome","gopls","ruby-lsp","ty","pyright","elixir-ls","zls",
    "csharp","fsharp","sourcekit-lsp","rust","clangd","svelte","astro","jdtls","kotlin-ls","yaml-ls","lua-ls",
    "php intelephense","prisma","dart","ocaml-lsp","bash","terraform","texlab","dockerfile","gleam","clojure-lsp",
    "nixd","tinymist","haskell-language-server"
  ].

string_list_non_empty(Val) ->
  case Val of
    L when is_list(L), L =/= [] ->
      List = [to_bin(X) || X <- L, byte_size(string:trim(to_bin(X))) > 0],
      case length(List) =:= length(L) of
        true -> List;
        false -> undefined
      end;
    _ ->
      undefined
  end.

string_list_allow_empty(Val) ->
  case Val of
    L when is_list(L) ->
      List = [to_bin(X) || X <- L],
      case lists:any(fun (B) -> byte_size(string:trim(to_bin(B))) =:= 0 end, List) of
        true -> undefined;
        false -> List
      end;
    _ ->
      undefined
  end.

string_map(undefined) -> undefined;
string_map(Obj) when is_map(Obj) ->
  maps:from_list(
    [{to_bin(K), to_bin(V)} || {K, V} <- maps:to_list(Obj)]
  );
string_map(_) -> undefined.

first_non_empty(_Map, []) -> undefined;
first_non_empty(Map, [K | Rest]) ->
  case maps:get(K, Map, undefined) of
    undefined -> first_non_empty(Map, Rest);
    V ->
      Bin = to_bin(V),
      case byte_size(string:trim(Bin)) > 0 of
        true -> Bin;
        false -> first_non_empty(Map, Rest)
      end
  end.

int_opt(Map, Keys, Default) ->
  Val =
    lists:foldl(
      fun (K, Acc) ->
        case Acc of
          undefined -> maps:get(K, Map, undefined);
          _ -> Acc
        end
      end,
      undefined,
      Keys
    ),
  case Val of
    undefined -> Default;
    I when is_integer(I) -> I;
    B when is_binary(B) ->
      case (catch binary_to_integer(string:trim(B))) of X when is_integer(X) -> X; _ -> Default end;
    L when is_list(L) ->
      case (catch list_to_integer(string:trim(L))) of X when is_integer(X) -> X; _ -> Default end;
    _ -> Default
  end.

ends_with(Bin, Suffix) ->
  Sz = byte_size(Bin),
  Sz2 = byte_size(Suffix),
  Sz >= Sz2 andalso binary:part(Bin, Sz - Sz2, Sz2) =:= Suffix.

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) -> maps:from_list(L);
ensure_map(_) -> #{}.

ensure_list(B) when is_binary(B) -> binary_to_list(B);
ensure_list(L) when is_list(L) -> L;
ensure_list(A) when is_atom(A) -> atom_to_list(A);
ensure_list(I) when is_integer(I) -> integer_to_list(I);
ensure_list(Other) -> lists:flatten(io_lib:format("~p", [Other])).

to_bin(undefined) -> <<>>;
to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> unicode:characters_to_binary(L, utf8);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(I) when is_integer(I) -> iolist_to_binary(integer_to_list(I));
to_bin(Other) -> unicode:characters_to_binary(io_lib:format("~p", [Other]), utf8).

bin_to_utf8(Bin) when is_binary(Bin) ->
  try unicode:characters_to_binary(Bin, utf8)
  catch
    _:_ -> Bin
  end.
