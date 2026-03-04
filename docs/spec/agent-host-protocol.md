# OpenAgentic Agent Host Protocol (HTTP + SSE)

> Canonical spec (English). For a Chinese version, see `docs/spec/agent-host-protocol.zh_ch.md`.

## 1. Motivation

`openagentic-sdk-*` already treats a **session** as durable state (`meta.json` + `events.jsonl`). A running agent process is therefore a *cursor/executor* over that session, not the source of truth.

This protocol extends that idea across machines and languages:

- A **Controller** (the caller) can spawn a **Subagent** on a remote **Host**.
- The Host streams events back to the Controller via **Server-Sent Events (SSE)**.
- The Controller treats the remote subagent like a local `Subagent` tool call: same semantics, different transport.

Target use cases:

- Resume-after-crash: Host can restart the agent process and resume from session.
- Offload: run subagents on a different machine (compute/data locality).
- Cross-language: Erlang ↔ Kotlin (or any language) as long as they speak this protocol.
- Multi-hop: a Host may itself act as a Controller and spawn further subagents.

Non-goals (v1):

- Dynamic discovery (mDNS/registry gossip). We use static configuration first.
- Strong identity / PKI / mTLS. We start with pre-shared tokens.
- Full remote OTP supervision semantics across nodes/languages.

## 2. Design choices (and why)

### 2.1 Transport: HTTP + SSE (not WebSocket)

Pros:
- Works well through reverse proxies (Caddy/NGINX/Cloudflare).
- Matches existing “streaming events” mental model and storage (`events.jsonl`).
- Simple operationally: standard HTTP, easy to debug with curl.

Cons:
- SSE is server → client only; client → server requires extra HTTP endpoints (`/signal`, `/answer`).

### 2.2 Discovery: static host list (not automatic)

Pros:
- Deterministic, easy to audit, easy to lock down in enterprise networks.
- Avoids building/operating a registry service early.

Cons:
- Less convenient than auto discovery; but can be layered later.

### 2.3 Auth: pre-shared token (not mTLS yet)

Pros:
- Easiest cross-language, cross-platform.
- Quick to deploy behind a reverse proxy.

Cons:
- Token rotation and leakage risks; requires discipline and least-privilege controls.

## 3. Terminology

- **Controller**: the runtime that initiates a remote subagent.
- **Host**: an HTTP service that can spawn and run agents.
- **Agent**: a long-running unit of work; typically has a `session_id`.
- **Subagent**: an agent spawned by another agent/tool call.
- **Session**: durable event log (`events.jsonl`) + metadata.
- **Event**: JSON object with `type` plus `seq` and `ts`.

## 4. Versioning & compatibility

- Protocol version string: `protocol_version = "1.0"`.
- Backward compatible additions: new fields are allowed; clients must ignore unknown fields.
- Breaking changes: require `/openagentic/v2/...` or `protocol_version` bump.

## 5. Authentication

All requests MUST include:

- `Authorization: Bearer <token>`

Recommended:

- `X-Request-Id: <uuid-or-random-hex>` (tracing)
- `User-Agent: openagentic-sdk-erlang/<ver>` (or kotlin)

Host behavior:

- `401` if missing/invalid token.
- `403` if token lacks permission for a requested action (e.g., spawn disabled).

## 6. Static configuration (Controller side)

The controller keeps a static list of known hosts. Suggested env var:

- `OPENAGENTIC_REMOTE_HOSTS` = JSON array of host entries

Example:

```json
[
  {
    "host_id": "workstation-1",
    "base_url": "http://192.168.50.10:8080",
    "token_env": "OPENAGENTIC_HOST_WORKSTATION_1_TOKEN",
    "tags": ["lan", "kotlin"]
  }
]
```

Notes:
- Tokens should come from separate env vars (`token_env`) to avoid putting secrets in JSON.
- The controller MAY implement host selection by `tags` and `capabilities` from `/hello`.

## 7. Endpoints

Base path: `/openagentic/v1`

### 7.1 `GET /hello`

Purpose: capability handshake.

Response `200 application/json`:

```json
{
  "protocol_version": "1.0",
  "host_id": "workstation-1",
  "impl": { "name": "openagentic-sdk-kotlin", "version": "0.0.0" },
  "time": { "unix_ms": 0 },
  "capabilities": {
    "sse_resume": true,
    "max_concurrency": 4,
    "supports_repo_clone": true,
    "supports_user_answer": true,
    "tools_policy": { "interactive": false }
  }
}
```

### 7.2 `POST /agents/spawn`

Purpose: spawn a new agent instance (most commonly a remote subagent).

Request `application/json`:

```json
{
  "agent_kind": "subagent",
  "controller": {
    "controller_id": "erlang-main",
    "parent_session_id": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    "parent_tool_use_id": "tool_123",
    "trace_id": "t_abc"
  },
  "init": {
    "prompt": "Explore this repo and summarize...",
    "model": "gpt-4.1-mini",
    "max_steps": 50,
    "metadata": { "purpose": "explore" }
  },
  "workspace": {
    "repo": {
      "clone_url": "https://github.com/org/repo.git",
      "ref": "main",
      "commit": "0123456789abcdef"
    },
    "workdir_hint": "repo-root",
    "constraints": {
      "allow_network": true,
      "allow_write": false
    }
  }
}
```

Response `201 application/json`:

```json
{
  "agent_id": "agent_5f6d...",
  "session_id": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
  "events_url": "/openagentic/v1/agents/agent_5f6d.../events",
  "status_url": "/openagentic/v1/agents/agent_5f6d.../status",
  "signal_url": "/openagentic/v1/agents/agent_5f6d.../signal",
  "answer_url": "/openagentic/v1/agents/agent_5f6d.../answer"
}
```

Notes:
- `commit` is optional but recommended for reproducibility.
- `constraints` are advisory unless the host enforces them.

### 7.3 `GET /agents/{agent_id}/events` (SSE)

Purpose: stream agent events.

Response: `200 text/event-stream; charset=utf-8`

Rules:
- Each event is one JSON object compatible with the local `events.jsonl` format.
- Each event MUST include `seq` (integer) and `ts` (float seconds).
- SSE `id:` SHOULD be `seq` so clients can resume via `Last-Event-ID`.
- SSE `event:` SHOULD be the event’s `type` (e.g., `tool.use`).

Example wire format:

```
id: 12
event: tool.use
data: {"type":"tool.use","tool_use_id":"tool_123","name":"Read","input":{"path":"README.md"},"seq":12,"ts":1730000000.123}

```

Resume:
- Client reconnects with `Last-Event-ID: 12`.
- Host SHOULD replay events with `seq > 12` if retained.
- Host SHOULD emit periodic keep-alives, e.g. `: ping\n\n`.

### 7.4 `GET /agents/{agent_id}/status`

Purpose: pollable status (useful if SSE is blocked).

Response `200 application/json`:

```json
{
  "agent_id": "agent_5f6d...",
  "session_id": "bbbb...",
  "state": "running",
  "last_seq": 12,
  "started_at": 1730000000.0,
  "updated_at": 1730000001.0,
  "error": null
}
```

States (suggested): `starting | running | completed | failed | canceled`.

### 7.5 `POST /agents/{agent_id}/signal`

Purpose: controller → agent control messages.

Request:

```json
{ "signal": "cancel", "reason": "timeout" }
```

Response:

```json
{ "ok": true }
```

### 7.6 `POST /agents/{agent_id}/answer` (optional)

Purpose: provide an answer to a `user.question` event.

Request:

```json
{ "question_id": "q_123", "answer": "yes" }
```

Response:

```json
{ "ok": true }
```

Guidance:
- Remote subagents SHOULD be configured to avoid interactive prompts by default.
- If interaction is required, the controller can proxy user input through this endpoint.

### 7.7 Artifacts (optional, recommended)

If the host produces large outputs, it should emit small event payloads and reference artifacts.

Suggested endpoint:
- `GET /artifacts/{artifact_id}` → `application/octet-stream` or `application/json`

## 8. Event schema (compatibility layer)

This protocol intentionally reuses OpenAgentic’s event objects (the same shape we persist to `events.jsonl`).

Common fields:
- `type` (string)
- `seq` (int) – monotonic per session
- `ts` (float seconds)

Common event types:
- `system.init`
- `user.message`, `user.compaction`, `user.question`
- `assistant.delta`, `assistant.message`
- `tool.use`, `tool.result`, `tool.output_compacted`
- `hook.event`
- `provider.event`
- `runtime.error`
- `result`

Guideline:
- When returning a final answer, the host SHOULD emit a `result` event with `final_text`.

## 9. Supervision & resume semantics

### 9.1 BEAM ↔ BEAM

If both sides are BEAM nodes, they MAY use native node connectivity and process monitoring for faster failure detection.
However, this protocol remains useful even in that case because it is language-neutral and proxy-friendly.

### 9.2 Cross-language (Erlang ↔ Kotlin)

Supervision becomes “logical supervision”:
- Heartbeats/keep-alives on SSE
- Status polling via `/status`
- Lease/timeout semantics
- Session-based resume on the host side

The host SHOULD support restarting a crashed agent process and continuing the same `session_id`.

## 9.3 Multi-hop / hierarchical collaboration (multi-level interconnect)

This protocol is intentionally composable:

- Any implementation may act as a **Host** (serve endpoints) and also as a **Controller** (call other hosts).
- A remote subagent spawned on Host A may itself spawn subagents on Host B/C using the same protocol.

Guidelines:
- Controllers SHOULD generate a `trace_id` and propagate it to downstream spawns.
- The `controller` object MAY include an optional `chain` array for auditability:

```json
{
  "chain": [
    { "controller_id": "erlang-main", "host_id": "local" },
    { "controller_id": "kotlin-host-a", "host_id": "workstation-1" }
  ]
}
```

The chain is informational; it must not be required for correctness.

## 10. Security considerations (v1)

- Token storage: keep tokens in env vars or secret stores; never log them.
- Token scope: prefer per-host tokens; optionally per-action scopes (spawn/status/events).
- Network boundaries: host should bind to LAN interface only; put behind reverse proxy if needed.
- Repo cloning/execution: treat untrusted repos as dangerous; default to `allow_write=false` and restrict shell tools unless explicitly allowed.
- Rate limits: hosts should cap concurrency and request sizes.

## 11. Implementation notes (Erlang-first, Kotlin-compatible)

Suggested rollout:

1) Host service (Erlang): implement `/hello`, `/spawn`, `/events` streaming from the session event emitter.
2) Controller client (Erlang): a “remote subagent tool” that calls `/spawn` then consumes SSE until `result`.
3) Add `/signal` cancel and `/status` polling fallback.
4) Add artifact references for large outputs.
5) Multi-hop: allow a host to act as controller too (no protocol changes).
