# openagentic-sdk-erlang

中文说明见：[`README.zh_ch.md`](README.zh_ch.md)

`openagentic-sdk-erlang` is an Erlang/OTP sibling project of `openagentic-sdk-kotlin`.
It focuses on a practical Agent runtime for BEAM:

- OpenAI Responses API provider (SSE streaming)
- Tool-loop (function calling) with a permission gate (HITL)
- Sessions persisted on disk (`meta.json` + `events.jsonl`)
- Built-in tools (Read/List/Glob/Grep/WebSearch/WebFetch/Skill/SlashCommand/…)
- A small CLI you can run locally to validate end-to-end behavior

This repository is optimized for Windows 11 + PowerShell (including proxy environments).

## Status

This project is under active development. Expect some rough edges, but the repo contains:

- Deterministic unit tests (offline): `rebar3 eunit`
- Optional online E2E suite (real network + real API keys): `.\scripts\e2e-online-suite.ps1 -E2E`

## Specs

- Local control plane + workflow DSL (三省六部): `docs/spec/workflow-engine.md`
- 中文说明：`docs/spec/workflow-engine.zh_ch.md`
- Remote subagents (HTTP + SSE): `docs/spec/agent-host-protocol.md`
- 中文说明：`docs/spec/agent-host-protocol.zh_ch.md`

## Requirements

- Erlang/OTP 28 (tested)
- `rebar3`
- Windows PowerShell 7.x recommended (PowerShell syntax in docs uses `;` not `&&`)

## Quick start (Windows PowerShell)

1) Set Erlang + caches to your E: drive (proxy optional):

```powershell
# With proxy (mainland network setups):
. .\scripts\erlang-env.ps1 -EnableProxy -SkipRebar3Verify

# Without proxy:
# . .\scripts\erlang-env.ps1 -SkipRebar3Verify
```

Notes:
- Default proxy is `http://127.0.0.1:7897` (override with `-Proxy`).
- The script also ensures rebar3 cache/hex/httpc data live on E: to avoid filling C:.

2) Run unit tests (recommended in a new terminal so env vars are refreshed):

```powershell
rebar3 eunit
```

3) Start the interactive CLI (via Erlang shell):

```powershell
rebar3 shell
```

Then in the Erlang shell:

```erlang
openagentic_cli:main(["chat"]).
%% Or:
openagentic_cli:main(["run", "Hello from Erlang!"]).
%% Workflow (hard flow, DSL-driven):
openagentic_cli:main(["workflow", "--dsl", "workflows/three-provinces-six-ministries.v1.json", "Plan and implement X"]).
%% Web UI (left: 三省六部 diagram, right: chat):
openagentic_cli:main(["web"]).
```

After starting the Web UI, open the printed URL in your browser (default: `http://127.0.0.1:8088/`).

## Configuration (.env)

The CLI loads `.env` from the project directory.
Never commit real keys: `.env` is gitignored in this repo.

Minimal `.env` example (do not paste real keys into issues/logs):

```dotenv
OPENAI_API_KEY=your_key_here
MODEL=gpt-4.1-mini
```

Common keys:

- `OPENAI_API_KEY` (required)
- `OPENAI_MODEL` or `MODEL` (required)
- `OPENAI_BASE_URL` (optional; default: `https://api.openai.com/v1`)
- `OPENAI_API_KEY_HEADER` (optional; default: `authorization`; some gateways require `x-api-key`, etc.)
- `OPENAI_STORE` (optional; default: enabled for Responses API)

Web search (optional; required if you want “real web search” instead of fallback parsing):

- `TAVILY_API_KEY` (recommended)
- `TAVILY_URL` (optional; default: `https://api.tavily.com` and auto-normalized to `/search`)

## CLI flags (high value)

The CLI entry is `openagentic_cli:main/1`. Useful flags:

- `--max-steps <1..200>`: max model “steps” per query (default: `50`)
- `--stream` / `--no-stream`: streaming on/off (default: on)
- `--permission <bypass|deny|prompt|default>`: permission gate mode (default: `default`)
- `--color` / `--no-color`: ANSI colors in terminal output (default: auto)
- `--render-markdown` / `--no-render-markdown`: improve readability of long markdown (non-stream output only)

Color can also be disabled via environment variables:

- `NO_COLOR=1` (standard)
- `OPENAGENTIC_NO_COLOR=1` (project-specific)

## Permissions (HITL)

This runtime includes a permission gate (human-in-the-loop) for tool calls.

- In `default` mode, **safe read-only tools are auto-approved** (no repetitive `yes/no` prompts).
- Potentially dangerous tools (write/edit/shell/task runners) require explicit approval.

When a tool is denied, the denial reason is sent back to the model as a tool error output.
This prevents “infinite retry” loops where the model keeps requesting a blocked tool.

## Tools (overview)

The runtime registers a set of tools used by the model:

- Filesystem: `List`, `Read`, `Glob`, `Grep`, `Write`, `Edit`
- Web: `WebSearch` (Tavily backend), `WebFetch`
- Agent building blocks: `Skill`, `SlashCommand`, `Task`, `AskUserQuestion`, …

The CLI prints tool calls with a short human summary (including the target file/path/query),
and prints a compact “tool result” summary. Secrets are best-effort redacted.

## Skills

Skills are markdown files named `SKILL.md` discovered from multiple roots.
Precedence is “more local wins”, and later roots override earlier ones:

1) `OPENAGENTIC_AGENTS_HOME` (default: `%USERPROFILE%\.agents`)
2) `OPENAGENTIC_SDK_HOME` (default: `%USERPROFILE%\.openagentic-sdk`)
3) Project directory
4) `./.claude`

This repository includes example skills under `./skills/`.

## Sessions (what gets written to disk)

Each run produces a session directory under:

- `OPENAGENTIC_SDK_HOME\sessions\<session_id>\`

Files:

- `meta.json`
- `events.jsonl` (append-only JSONL event log)

This structure is meant to be human-debuggable with standard tools.

## Online E2E suite (real network)

When you want to validate “real” behavior against live services:

```powershell
.\scripts\e2e-online-suite.ps1 -EnableProxy -SkipRebar3Verify -E2E
```

Notes:
- Requires a valid `.env` (OpenAI key/model, and optionally Tavily).
- Uses your configured proxy when `-EnableProxy` is enabled.

## Troubleshooting

### `401` / “Missing API key”

- Ensure `.env` exists in the project directory and contains `OPENAI_API_KEY`.
- If you are using a gateway, you may need `OPENAI_API_KEY_HEADER=x-api-key` (or similar).

### `rebar3` not found / `escript.exe` not found

Run the environment script in the same terminal before running `rebar3`:

```powershell
. .\scripts\erlang-env.ps1 -SkipRebar3Verify
```

### Output is too dense / hard to read

- Use `--no-stream` for long answers (better formatting, optional markdown rendering).
- Disable color with `--no-color` or `NO_COLOR=1` if your terminal doesn’t support ANSI.

## License

See repository files for licensing details (if present).
