-module(openagentic_compaction_prompts).
        -export([compaction_marker_question/0, compaction_system_prompt/0, compaction_user_instruction/0, tool_output_placeholder/0]).

        compaction_system_prompt() ->
          <<
            "You are a helpful AI assistant tasked with summarizing conversations.

"
            "When asked to summarize, provide a detailed but concise summary of the conversation.
"
            "Focus on information that would be helpful for continuing the conversation, including:
"
            "- What was done
"
            "- What is currently being worked on
"
            "- Which files are being modified
"
            "- What needs to be done next
"
            "- Key user requests, constraints, or preferences that should persist
"
            "- Important technical decisions and why they were made

"
            "Your summary should be comprehensive enough to provide context but concise enough to be quickly understood.
"
          >>.

        compaction_marker_question() -> <<"What did we do so far?">>.

        compaction_user_instruction() ->
          <<
            "Provide a detailed prompt for continuing our conversation above. Focus on information that would be helpful for "
            "continuing the conversation, including what we did, what we're doing, which files we're working on, and what we're "
            "going to do next considering new session will not have access to our conversation."
          >>.

        tool_output_placeholder() -> <<"[Old tool result content cleared]">>.
