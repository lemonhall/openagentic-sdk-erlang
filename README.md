# openagentic-sdk-erlang

`openagentic-sdk-erlang` 是 `openagentic-sdk-kotlin` 的 Erlang/OTP 平行移植版（优先实现 OpenAI Responses + SSE streaming）。

## 本机（Windows PowerShell）快速使用

先把 Erlang + 缓存目录指到 **E 盘**（可选开启代理）：

```powershell
. .\scripts\erlang-env.ps1 -EnableProxy -SkipRebar3Verify
```

然后在新终端里执行（避免环境变量未刷新）：

```powershell
rebar3 eunit
```

## CLI（本地验证）

当前仓库的 CLI 入口是 `openagentic_cli:main/1`（会读取项目目录下的 `.env`）。

```powershell
rebar3 shell
```

在 Erlang shell 里：

```erlang
openagentic_cli:main(["chat"]).
%% 或：openagentic_cli:main(["run", "你好"]).
```

常用 `.env` 键：
- `OPENAI_API_KEY`（必填）
- `OPENAI_MODEL` 或 `MODEL`（必填）
- `OPENAI_BASE_URL`（可选；默认 `https://api.openai.com/v1`）
- `OPENAI_API_KEY_HEADER`（可选；默认 `authorization`，一些网关可能需要 `x-api-key` 等）
