-module(openagentic_tool_lsp).

-behaviour(openagentic_tool).

-export([name/0, description/0, run/2]).

name() -> <<"lsp">>.

description() ->
  <<
    "Interact with Language Server Protocol (LSP) servers to get code intelligence features.
",
    "
",
    "Supported operations:
",
    "- goToDefinition
",
    "- findReferences
",
    "- hover
",
    "- documentSymbol
",
    "- workspaceSymbol
",
    "- goToImplementation
",
    "- prepareCallHierarchy
",
    "- incomingCalls
",
    "- outgoingCalls
",
    "
",
    "All operations require:
",
    "- filePath (or file_path)
",
    "- line (1-based)
",
    "- character (1-based)
",
    "
",
    "Note: LSP servers must be configured via OpenCode-style config (opencode.json / .opencode/opencode.json).
"
  >>.

run(Input0, Ctx0) -> openagentic_tool_lsp_api:run(Input0, Ctx0).
