-module(openagentic_tool_lsp_client).

-export([with_client/3, shutdown_best_effort/3, did_open/2, init_params/2, pos_params/3]).

with_client(Server, ProjectDir, Fun) ->
  Cmd = maps:get(command, Server, []),
  [Exe0 | Args0] = [openagentic_tool_lsp_utils:ensure_list(X) || X <- Cmd],
  case os:find_executable(Exe0) of
    false ->
      throw({runtime_error, iolist_to_binary([<<"lsp: executable not found: ">>, openagentic_tool_lsp_utils:to_bin(Exe0)])});
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
    {Buf1, _Res, State1} = openagentic_tool_lsp_protocol:rpc_request(Port, Buf0, State0, <<"shutdown">>, #{}, 5000),
    _ = openagentic_tool_lsp_protocol:rpc_notify(Port, <<"exit">>, null),
    {Buf1, State1}
  catch
    _:_ -> {Buf0, State0}
  end.

did_open(Port, FullPath) ->
  Uri = file_uri(FullPath),
  Text = case file:read_file(FullPath) of {ok, B} -> openagentic_tool_lsp_utils:to_bin(B); _ -> <<>> end,
  Lang = guess_language_id(filename:basename(FullPath)),
  Params = #{
    <<"textDocument">> => #{
      <<"uri">> => Uri,
      <<"languageId">> => Lang,
      <<"version">> => 1,
      <<"text">> => openagentic_tool_lsp_utils:bin_to_utf8(Text)
    }
  },
  openagentic_tool_lsp_protocol:rpc_notify(Port, <<"textDocument/didOpen">>, Params).

guess_language_id(Name0) ->
  Name = string:lowercase(openagentic_tool_lsp_utils:to_bin(Name0)),
  case openagentic_tool_lsp_utils:ends_with(Name, <<".kt">>) orelse openagentic_tool_lsp_utils:ends_with(Name, <<".kts">>) of
    true -> <<"kotlin">>;
    false ->
      case openagentic_tool_lsp_utils:ends_with(Name, <<".java">>) of
        true -> <<"java">>;
        false ->
          case openagentic_tool_lsp_utils:ends_with(Name, <<".py">>) of
            true -> <<"python">>;
            false ->
              case openagentic_tool_lsp_utils:ends_with(Name, <<".ts">>) of
                true -> <<"typescript">>;
                false ->
                  case openagentic_tool_lsp_utils:ends_with(Name, <<".js">>) of
                    true -> <<"javascript">>;
                    false ->
                      case openagentic_tool_lsp_utils:ends_with(Name, <<".rs">>) of
                        true -> <<"rust">>;
                        false ->
                          case openagentic_tool_lsp_utils:ends_with(Name, <<".go">>) of
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
