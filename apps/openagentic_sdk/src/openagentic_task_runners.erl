-module(openagentic_task_runners).

-export([built_in_explore/1, built_in_research/1, compose/1]).

compose(Runners0) -> openagentic_task_runners_compose:compose(Runners0).
built_in_explore(BaseOpts0) -> openagentic_task_runners_builtin:built_in_explore(BaseOpts0).
built_in_research(BaseOpts0) -> openagentic_task_runners_builtin:built_in_research(BaseOpts0).
