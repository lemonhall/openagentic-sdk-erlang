param(
  [switch]$EnableProxy,
  [int]$TimeoutSec = 360
)

$ErrorActionPreference = "Stop"

Push-Location (Split-Path -Parent $MyInvocation.MyCommand.Path)
Pop-Location

# Ensure Erlang + rebar3 env in this session.
if ($EnableProxy) {
  . "$PSScriptRoot/erlang-env.ps1" -EnableProxy -SkipRebar3Verify
} else {
  . "$PSScriptRoot/erlang-env.ps1" -SkipRebar3Verify
}

$env:OPENAGENTIC_E2E = "1"

Write-Host "Running online Web E2E (OPENAGENTIC_E2E=1)..." -ForegroundColor Cyan

rebar3 eunit

Write-Host "OK: online Web E2E passed." -ForegroundColor Green
