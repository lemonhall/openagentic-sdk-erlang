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

