-module(openagentic_tool_lsp_actions).

-export([do_lsp/6]).

-define(DEFAULT_TIMEOUT_MS, 60000).

do_lsp(Op, FullPath, Line, Character, ProjectDir, Servers0) ->
  Servers = openagentic_tool_lsp_config:matching_servers(FullPath, Servers0),
  case Servers of
    [] ->
      {error, {runtime_error, <<"No LSP server available for this file type.">>}};
    [S | _] ->
      try
        Result =
          openagentic_tool_lsp_client:with_client(
            S,
            ProjectDir,
            fun (Port) ->
              Buf0 = <<>>,
              State0 = #{next_id => 1},
              {Buf1, _InitRes, State1} = openagentic_tool_lsp_protocol:rpc_request(Port, Buf0, State0, <<"initialize">>, openagentic_tool_lsp_client:init_params(ProjectDir, S), ?DEFAULT_TIMEOUT_MS),
              ok = openagentic_tool_lsp_protocol:rpc_notify(Port, <<"initialized">>, #{}),
              ok = openagentic_tool_lsp_client:did_open(Port, FullPath),
              {Buf2, Result0, State2} = do_operation(Op, Port, Buf1, State1, FullPath, Line, Character),
              _ = openagentic_tool_lsp_client:shutdown_best_effort(Port, Buf2, State2),
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
  Uri = openagentic_tool_lsp_client:file_uri(FullPath),
  Line0 = Line - 1,
  Char0 = Character - 1,
  case Op of
    <<"goToDefinition">> ->
      openagentic_tool_lsp_protocol:rpc_request(Port, Buf0, State0, <<"textDocument/definition">>, openagentic_tool_lsp_client:pos_params(Uri, Line0, Char0), ?DEFAULT_TIMEOUT_MS);
    <<"findReferences">> ->
      Params = #{
        <<"textDocument">> => #{<<"uri">> => Uri},
        <<"position">> => #{<<"line">> => Line0, <<"character">> => Char0},
        <<"context">> => #{<<"includeDeclaration">> => true}
      },
      openagentic_tool_lsp_protocol:rpc_request(Port, Buf0, State0, <<"textDocument/references">>, Params, ?DEFAULT_TIMEOUT_MS);
    <<"hover">> ->
      openagentic_tool_lsp_protocol:rpc_request(Port, Buf0, State0, <<"textDocument/hover">>, openagentic_tool_lsp_client:pos_params(Uri, Line0, Char0), ?DEFAULT_TIMEOUT_MS);
    <<"documentSymbol">> ->
      openagentic_tool_lsp_protocol:rpc_request(Port, Buf0, State0, <<"textDocument/documentSymbol">>, #{<<"textDocument">> => #{<<"uri">> => Uri}}, ?DEFAULT_TIMEOUT_MS);
    <<"workspaceSymbol">> ->
      openagentic_tool_lsp_protocol:rpc_request(Port, Buf0, State0, <<"workspace/symbol">>, #{<<"query">> => <<>>}, ?DEFAULT_TIMEOUT_MS);
    <<"goToImplementation">> ->
      openagentic_tool_lsp_protocol:rpc_request(Port, Buf0, State0, <<"textDocument/implementation">>, openagentic_tool_lsp_client:pos_params(Uri, Line0, Char0), ?DEFAULT_TIMEOUT_MS);
    <<"prepareCallHierarchy">> ->
      openagentic_tool_lsp_protocol:rpc_request(Port, Buf0, State0, <<"textDocument/prepareCallHierarchy">>, openagentic_tool_lsp_client:pos_params(Uri, Line0, Char0), ?DEFAULT_TIMEOUT_MS);
    <<"incomingCalls">> ->
      {Buf1, Items, State1} = openagentic_tool_lsp_protocol:rpc_request(Port, Buf0, State0, <<"textDocument/prepareCallHierarchy">>, openagentic_tool_lsp_client:pos_params(Uri, Line0, Char0), ?DEFAULT_TIMEOUT_MS),
      Item0 = first_object(Items),
      case Item0 of
        undefined -> {Buf1, [], State1};
        _ -> openagentic_tool_lsp_protocol:rpc_request(Port, Buf1, State1, <<"callHierarchy/incomingCalls">>, #{<<"item">> => Item0}, ?DEFAULT_TIMEOUT_MS)
      end;
    <<"outgoingCalls">> ->
      {Buf1, Items, State1} = openagentic_tool_lsp_protocol:rpc_request(Port, Buf0, State0, <<"textDocument/prepareCallHierarchy">>, openagentic_tool_lsp_client:pos_params(Uri, Line0, Char0), ?DEFAULT_TIMEOUT_MS),
      Item0 = first_object(Items),
      case Item0 of
        undefined -> {Buf1, [], State1};
        _ -> openagentic_tool_lsp_protocol:rpc_request(Port, Buf1, State1, <<"callHierarchy/outgoingCalls">>, #{<<"item">> => Item0}, ?DEFAULT_TIMEOUT_MS)
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
