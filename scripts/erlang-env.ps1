param(
  [string]$Proxy = 'http://127.0.0.1:7897',
  [switch]$EnableProxy,
  [switch]$SkipRebar3Verify
)

$ErrorActionPreference = 'Stop'

$env:ERLANG_HOME = 'E:\lang\erlang'
$env:REBAR_BASE_DIR = 'E:\erlang\rebar3'
$env:REBAR_CACHE_DIR = 'E:\erlang\rebar3\cache'
$env:HEX_HOME = 'E:\erlang\hex'
$env:OPENAGENTIC_HTTPC_DATA_DIR = 'E:\erlang\httpc'
$env:OPENAGENTIC_SDK_HOME = 'E:\openagentic-sdk'

$env:PATH = "$env:ERLANG_HOME\bin;E:\lang\bin;$env:PATH"

New-Item -ItemType Directory -Force -Path $env:OPENAGENTIC_HTTPC_DATA_DIR | Out-Null
New-Item -ItemType Directory -Force -Path $env:OPENAGENTIC_SDK_HOME | Out-Null

if ($EnableProxy) {
  $env:HTTP_PROXY = $Proxy
  $env:HTTPS_PROXY = $Proxy
}

if (-not (Test-Path -LiteralPath "$env:ERLANG_HOME\bin\erl.exe")) {
  throw "erl.exe not found at $env:ERLANG_HOME\bin\erl.exe"
}
if (-not (Get-Command rebar3 -ErrorAction SilentlyContinue)) {
  throw "rebar3 not found on PATH (expected at E:\lang\bin\rebar3.cmd)"
}

Write-Host "ERLANG_HOME=$env:ERLANG_HOME"
Write-Host "REBAR_BASE_DIR=$env:REBAR_BASE_DIR"
Write-Host "REBAR_CACHE_DIR=$env:REBAR_CACHE_DIR"
Write-Host "HEX_HOME=$env:HEX_HOME"
if ($EnableProxy) { Write-Host "HTTP(S)_PROXY=$Proxy" }

erl -noshell -eval 'io:format("otp_release=~s~n", [erlang:system_info(otp_release)]), halt().'

if (-not $SkipRebar3Verify) {
  rebar3 --version
} else {
  Write-Host "Skip rebar3 verify (use: rebar3 --version)"
}
