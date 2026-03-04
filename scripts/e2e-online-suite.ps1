param(
  [string]$Proxy = 'http://127.0.0.1:7897',
  [switch]$EnableProxy,
  [switch]$SkipRebar3Verify,
  [switch]$E2E
)

$ErrorActionPreference = 'Stop'

if ($E2E) { $env:OPENAGENTIC_E2E = '1' }
if (-not $env:OPENAGENTIC_E2E) { $env:OPENAGENTIC_E2E = '0' }

. "$PSScriptRoot\\erlang-env.ps1" -Proxy $Proxy -EnableProxy:$EnableProxy -SkipRebar3Verify:$SkipRebar3Verify

Write-Host "Running ONLINE E2E suite (OPENAGENTIC_E2E=$env:OPENAGENTIC_E2E)..."

rebar3 compile | Out-Null

$ebinRaw = rebar3 path --ebin -s ';'
$ebins = @()
foreach ($p in $ebinRaw.Split(';')) {
  $pp = $p.Trim()
  if ($pp) { $ebins += $pp }
}
if ($ebins.Count -eq 0) {
  throw "Failed to resolve ebin paths via: rebar3 path --ebin"
}

& "$env:ERLANG_HOME\\bin\\erl.exe" -noshell -pa $ebins -eval "openagentic_e2e_online:suite(), halt()."
if ($LASTEXITCODE -ne 0) {
  throw "ONLINE E2E suite failed (exit=$LASTEXITCODE)"
}

Write-Host "ONLINE E2E suite OK"

