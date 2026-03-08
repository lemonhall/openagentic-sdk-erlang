-module(openagentic_workflow_dsl).
-export([load/3, load_and_validate/3, validate/3]).

load(ProjectDir, RelPath, Opts) ->
  openagentic_workflow_dsl_api:load(ProjectDir, RelPath, Opts).

load_and_validate(ProjectDir, RelPath, Opts) ->
  openagentic_workflow_dsl_api:load_and_validate(ProjectDir, RelPath, Opts).

validate(ProjectDir, Workflow, Opts) ->
  openagentic_workflow_dsl_api:validate(ProjectDir, Workflow, Opts).
