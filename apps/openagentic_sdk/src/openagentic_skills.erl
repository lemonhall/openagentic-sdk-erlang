-module(openagentic_skills).

-export([index/1, get/2]).

index(ProjectDir0) -> openagentic_skills_api:index(ProjectDir0).
get(ProjectDir0, Name0) -> openagentic_skills_api:get(ProjectDir0, Name0).
