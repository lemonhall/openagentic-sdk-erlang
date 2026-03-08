-module(openagentic_compaction).
-export([would_overflow/2, select_tool_outputs_to_prune/2, build_compaction_transcript/4, tool_output_placeholder/0, compaction_system_prompt/0, compaction_user_instruction/0, compaction_marker_question/0]).

would_overflow(Compaction, Usage) -> openagentic_compaction_overflow:would_overflow(Compaction, Usage).
select_tool_outputs_to_prune(Events, Compaction) -> openagentic_compaction_prune:select_tool_outputs_to_prune(Events, Compaction).
build_compaction_transcript(Events, ResumeMaxEvents, ResumeMaxBytes, ToolOutputPlaceholder) -> openagentic_compaction_transcript:build_compaction_transcript(Events, ResumeMaxEvents, ResumeMaxBytes, ToolOutputPlaceholder).
tool_output_placeholder() -> openagentic_compaction_prompts:tool_output_placeholder().
compaction_system_prompt() -> openagentic_compaction_prompts:compaction_system_prompt().
compaction_user_instruction() -> openagentic_compaction_prompts:compaction_user_instruction().
compaction_marker_question() -> openagentic_compaction_prompts:compaction_marker_question().
