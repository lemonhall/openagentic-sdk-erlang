param(
  [string]$OutputRoot,
  [int]$CaseCount = 100,
  [int]$TasksPerCase = 5,
  [int]$ActiveTasksPerCase = $TasksPerCase,
  [int]$ScheduledTasksPerCase = 0,
  [int]$MailPerCase = 10,
  [int]$UnreadPerCase = 5,
  [string]$ProviderMod,
  [string]$JsonOut
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'erlang-env.ps1') -SkipRebar3Verify

if ($OutputRoot) {
  if (!(Test-Path -LiteralPath $OutputRoot)) {
    New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
  }
  $env:OPENAGENTIC_PERF_OUTPUT_ROOT = [System.IO.Path]::GetFullPath($OutputRoot)
} else {
  Remove-Item Env:OPENAGENTIC_PERF_OUTPUT_ROOT -ErrorAction SilentlyContinue
}

if ($JsonOut) {
  $targetJson = [System.IO.Path]::GetFullPath($JsonOut)
  $parent = Split-Path -Parent $targetJson
  if ($parent -and !(Test-Path -LiteralPath $parent)) {
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
  }
} else {
  $tmpDir = Join-Path (Get-Location) '.tmp\perf'
  if (!(Test-Path -LiteralPath $tmpDir)) {
    New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
  }
  $targetJson = Join-Path $tmpDir ('perf-baseline-' + [Guid]::NewGuid().ToString('N') + '.json')
}
$env:OPENAGENTIC_PERF_JSON_OUT = $targetJson

$env:OPENAGENTIC_PERF_PROBE = '1'
$env:OPENAGENTIC_PERF_CASE_COUNT = [string]$CaseCount
$env:OPENAGENTIC_PERF_TASKS_PER_CASE = [string]$TasksPerCase
$env:OPENAGENTIC_PERF_ACTIVE_TASKS_PER_CASE = [string]$ActiveTasksPerCase
$env:OPENAGENTIC_PERF_SCHEDULED_TASKS_PER_CASE = [string]$ScheduledTasksPerCase
$env:OPENAGENTIC_PERF_MAIL_PER_CASE = [string]$MailPerCase
$env:OPENAGENTIC_PERF_UNREAD_PER_CASE = [string]$UnreadPerCase
if ($ProviderMod) {
  $env:OPENAGENTIC_PERF_PROVIDER_MOD = $ProviderMod
} else {
  Remove-Item Env:OPENAGENTIC_PERF_PROVIDER_MOD -ErrorAction SilentlyContinue
}

rebar3 eunit --module=openagentic_case_store_perf_probe_test | Out-Host

if (!(Test-Path -LiteralPath $targetJson)) {
  throw 'No JSON artifact from perf probe run.'
}

$json = Get-Content -Raw -Encoding UTF8 $targetJson
if ([string]::IsNullOrWhiteSpace($json)) {
  throw 'Perf probe JSON artifact is empty.'
}

$json.Trim()