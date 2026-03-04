param(
  [string]$Proxy = 'http://127.0.0.1:7897',
  [switch]$EnableProxy,
  [switch]$SkipRebar3Verify
)

$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\\erlang-env.ps1" -Proxy $Proxy -EnableProxy:$EnableProxy -SkipRebar3Verify:$SkipRebar3Verify

Write-Host "Running online smoke test (requires valid .env)..."

rebar3 compile | Out-Null

# Avoid `rebar3 shell` here: on Windows it may try to start an interactive tty and crash.
$ebinRaw = rebar3 path --ebin -s ';'
$ebins = @()
foreach ($p in $ebinRaw.Split(';')) {
  $pp = $p.Trim()
  if ($pp) { $ebins += $pp }
}
if ($ebins.Count -eq 0) {
  throw "Failed to resolve ebin paths via: rebar3 path --ebin"
}

& "$env:ERLANG_HOME\\bin\\erl.exe" -noshell -pa $ebins -eval "openagentic_e2e:online_smoke(), halt()."
if ($LASTEXITCODE -ne 0) {
  throw "E2E online smoke test failed (exit=$LASTEXITCODE)"
}

Write-Host "E2E online smoke test OK"
