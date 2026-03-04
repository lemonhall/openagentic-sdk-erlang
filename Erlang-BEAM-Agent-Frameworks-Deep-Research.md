## Executive Summary

The Erlang/BEAM ecosystem does not (yet) have a single dominant, Erlang-native “LLM agent framework” on the scale of LangChain (Python/JS) or AutoGen (.NET/Python). Instead, the most practical “agentic” options in the community cluster into (1) Elixir-first agentic-RAG / tool-chain libraries intended to be embedded into Phoenix apps, (2) early-stage Elixir ports of popular agent frameworks, (3) BEAM-native multi-agent/actor frameworks that focus on supervision, lifecycle, and messaging rather than LLM orchestration, and (4) MCP (Model Context Protocol) servers/clients that let external AI assistants safely reach into BEAM systems for introspection and controlled actions.

The strongest near-term pattern for production Erlang teams is typically “OTP for concurrency + an LLM/tool layer in Elixir (or external service)”, while using MCP or distribution-based tooling for observability and controlled remote operations.

## Key Findings

- **Agentic RAG is currently the most mature ‘agent-like’ capability on BEAM** via Elixir libraries that combine retrieval + multi-step pipelines (rewrite/select/expand/search/rerank/answer) with telemetry and production backends. Arcana is a representative example with an explicit Agent pipeline and pluggable steps. [1]
- **Ports of popular agent frameworks exist but are explicitly experimental.** The `autogen` Elixir package frames itself as a work-in-progress port of Microsoft AutoGen and is not production-ready. [2]
- **BEAM-native “multi-agent frameworks” often mean supervised actors, not LLM agents.** Mabeam positions itself as a multi-agent framework for BEAM focused on lifecycle, message passing, and discovery—aligning with OTP strengths rather than LLM tool orchestration. [3]
- **MCP is emerging as a practical integration surface for ‘agentic’ workflows around Erlang systems.** Projects like `erl_dist_mcp` expose tools (process inspection, supervision tree visualization, tracing, optional eval) over MCP so AI assistants can help debug/operate BEAM nodes with guardrails. [4]
- **Security posture is a primary differentiator.** Anything that enables remote evaluation (distribution RPC/eval, MCP “allow-eval”) needs strict controls; the better projects document those risks and provide safer defaults. [4]

## Detailed Analysis

### 1) What “Agent” Means in Erlang/BEAM Practice

In BEAM communities, “agent” is overloaded:

- **Actor/agent (classic sense):** autonomous processes with local state, message passing, discovery, and supervision (OTP-aligned).
- **LLM agent (current AI sense):** an LLM-driven loop that plans, calls tools, retrieves context (RAG), and iterates.

Erlang/OTP already provides a high-quality substrate for the first meaning; most gaps are in the second meaning: standardized tool schemas, prompt/loop abstractions, evaluation harnesses, and robust integrations with LLM providers.

### 2) Agentic RAG on BEAM: Arcana

Arcana is an Elixir/Phoenix-oriented library that explicitly supports both “simple RAG” and “agentic RAG.” It offers:

- An **Agent pipeline** where steps like `gate`, `select`, `expand`, `search`, `reason`, `rerank`, and `answer` can be composed.
- **Pluggable components** (behaviours) for each step so teams can swap implementations.
- Multiple backends (e.g., pgvector, in-memory HNSW), optional GraphRAG, file ingestion, and telemetry.

This is notable because it maps “agentic” behavior to explicit, testable steps rather than an opaque loop, and it is designed to embed into a Phoenix app with Ecto/Postgres. [1]

Implication: if your Erlang organization can accept an Elixir library (common in BEAM shops), agentic-RAG is currently the closest thing to a production-leaning “agent framework.”

### 3) Elixir AutoGen Port: autogen

The `autogen` package is a direct attempt to bring Microsoft AutoGen concepts to Elixir. It is candidly labeled “highly experimental” and “not ready for production.” Its README includes examples of:

- Conversable agents
- Two-agent back-and-forth dialogs
- A “code writer” and “code executor” collaboration pattern

It also states a longer-term goal to “turn agents into Erlang processes,” which hints at a future direction where agent orchestration is implemented using OTP semantics rather than purely as library data structures. [2]

Implication: useful for learning and experimentation; not a stable foundation yet.

### 4) BEAM “Multi-Agent Systems” Framework: Mabeam

Mabeam describes itself as a framework for building multi-agent systems on BEAM, emphasizing:

- Agent lifecycle management
- Asynchronous message passing
- Agent discovery
- Extensibility

This is much closer to “actors with conventions” than to an LLM agent framework. It aligns with OTP and may be relevant if your definition of “agent” is distributed autonomous components coordinated through message passing (with or without AI). [3]

Implication: it may serve as scaffolding for non-LLM agents, or for wrapping LLM workers as supervised processes, but you’ll still need to design your own LLM/tool loop.

### 5) MCP as an Agent Integration Surface for Erlang

MCP (Model Context Protocol) has become a common way for AI assistants to call tools. Two relevant BEAM-adjacent directions show up in the community:

- **Implement MCP servers in Elixir** (example project) to expose application tools over SSE/HTTP. This is a starting point for “LLM agent tool servers” written in BEAM languages. [5]
- **Connect AI assistants to BEAM nodes for introspection and controlled actions** via `erl_dist_mcp`, which connects through Erlang distribution and provides tools to list processes, inspect GenServer state, visualize supervision trees, trace functions, etc. It also highlights security considerations and gates dangerous capabilities behind `--allow-eval`. [4]

Implication: MCP is a promising standard boundary: instead of trying to re-build the entire agent ecosystem in Erlang, BEAM systems can expose safe, well-scoped tools to any MCP-capable agent runtime.

## Areas of Consensus

- OTP supervision + message passing remains the core advantage of BEAM for “agent-like” systems (fault-tolerant concurrent components).
- “LLM agent frameworks” are still emerging in BEAM; most production-grade usage today is integration-centric: RAG/tooling embedded into web apps, or external agent runtimes interacting with BEAM services.
- Tool safety, observability, and operational guardrails matter more than fancy planning loops when connecting agents to real systems.

## Areas of Debate

- **Where the ‘agent loop’ should live:** in BEAM (as supervised processes) vs. outside (Python/JS) with BEAM as a tool server.
- **How much autonomy is acceptable:** especially around code execution, RPC, and production tracing.
- **Framework vs. composition:** whether to standardize an “agent framework” in BEAM or to compose existing OTP patterns + LLM call libraries + MCP.

## Sources

[1] Arcana README (Hex Preview): https://preview.hex.pm/preview/arcana/show/README.md (Primary project documentation; high relevance for agentic-RAG on BEAM)

[2] Autogen README (Hex Preview): https://preview.hex.pm/preview/autogen/show/README.md (Primary project documentation; explicitly experimental)

[3] Mabeam GitHub README: https://github.com/nshkrdotcom/mabeam (Primary project documentation; multi-agent/actor framework positioning)

[4] Erlang Distribution MCP Server (erl_dist_mcp) README: https://github.com/jimsynz/erl_dist_mcp (Primary project documentation; detailed tool list + security posture)

[5] Elixir MCP Server example README: https://github.com/epinault/elixir_mcp_server (Primary example implementation; shows MCP server pattern in Elixir)

## Gaps and Further Research

- A broader scan of Hex/GitHub for additional BEAM-native “agent loop” libraries (beyond these exemplars) and an activity/maintenance comparison (commits, releases, users).
- Patterns for “LLM worker as OTP process”: supervision strategies, backpressure, circuit breakers, rate limiting, and telemetry conventions.
- Security hardening guidance for MCP + Erlang distribution in production (cookie handling, network segmentation, allowlists, audit logging).
- Reference architecture that combines: Phoenix/Ecto RAG pipeline + MCP tool boundary + external agent runtime, with clear responsibilities and failure modes.
