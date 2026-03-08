-module(openagentic_tool_notebook_edit).

-behaviour(openagentic_tool).

-export([name/0, description/0, run/2]).

name() -> <<"NotebookEdit">>.

description() -> <<"Edit a Jupyter notebook (.ipynb).">>.

run(Input, Ctx) ->
  openagentic_tool_notebook_edit_api:run(Input, Ctx).
