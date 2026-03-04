param(
  [string]$KotlinRoot = 'E:\development\openagentic-sdk-kotlin'
)

$ErrorActionPreference = 'Stop'

function Norm-Text([string]$path) {
  if (!(Test-Path $path)) { throw "Missing file: $path" }
  $raw = Get-Content -Raw -Encoding UTF8 $path
  return ($raw -replace "`r`n", "`n" -replace "`r", "`n")
}

function Fail([string]$msg) {
  Write-Error $msg
  exit 1
}

function Set-Equals($a, $b) {
  $aa = @($a | Sort-Object -Unique)
  $bb = @($b | Sort-Object -Unique)
  if ($aa.Count -ne $bb.Count) { return $false }
  for ($i = 0; $i -lt $aa.Count; $i++) {
    if ($aa[$i] -ne $bb[$i]) { return $false }
  }
  return $true
}

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$ErlPrompts = Join-Path $RepoRoot 'apps\openagentic_sdk\priv\toolprompts'
$KPrompts = Join-Path $KotlinRoot 'src\main\resources\me\lemonhall\openagentic\sdk\toolprompts'
$ErlPerm = Join-Path $RepoRoot 'apps\openagentic_sdk\src\openagentic_permissions.erl'
$ErlSchemas = Join-Path $RepoRoot 'apps\openagentic_sdk\src\openagentic_tool_schemas.erl'
$ErlRuntime = Join-Path $RepoRoot 'apps\openagentic_sdk\src\openagentic_runtime.erl'
$KPerm = Join-Path $KotlinRoot 'src\main\kotlin\me\lemonhall\openagentic\sdk\permissions\PermissionGate.kt'
$KSchemas = Join-Path $KotlinRoot 'src\main\kotlin\me\lemonhall\openagentic\sdk\tools\OpenAiToolSchemas.kt'

if (!(Test-Path $KotlinRoot)) { Fail "Kotlin repo not found: $KotlinRoot" }
if (!(Test-Path $ErlPrompts)) { Fail "Erlang toolprompts dir not found: $ErlPrompts" }

# 1) Toolprompt resources: exact file set + exact content (normalized newlines)
$kFiles = @(Get-ChildItem -File -Force $KPrompts -Filter '*.txt' | Select-Object -ExpandProperty Name | Sort-Object)
$eFiles = @(Get-ChildItem -File -Force $ErlPrompts -Filter '*.txt' | Select-Object -ExpandProperty Name | Sort-Object)

if (!(Set-Equals $kFiles $eFiles)) {
  $onlyK = @($kFiles | Where-Object { $_ -notin $eFiles })
  $onlyE = @($eFiles | Where-Object { $_ -notin $kFiles })
  Fail ("Toolprompt file list mismatch.`nOnly Kotlin: {0}`nOnly Erlang: {1}" -f ($onlyK -join ', '), ($onlyE -join ', '))
}

foreach ($f in $kFiles) {
  $a = Norm-Text (Join-Path $KPrompts $f)
  $b = Norm-Text (Join-Path $ErlPrompts $f)
  if ($a -ne $b) { Fail "Toolprompt content mismatch: $f" }
}

# 2) PermissionGate safe-tools set
$expectedSafe = @('Read', 'Glob', 'Grep', 'Skill', 'SlashCommand', 'AskUserQuestion')
$erlPermText = Norm-Text $ErlPerm
$m = [regex]::Match($erlPermText, 'safe_tools\(\)\s*->\s*\[(?<body>[\s\S]*?)\]\.', 'IgnoreCase')
if (!$m.Success) { Fail "Failed to parse Erlang safe_tools() in $ErlPerm" }
$erlSafe = @([regex]::Matches($m.Groups['body'].Value, '<<\"(?<n>[^\"]+)\"', 'IgnoreCase') | ForEach-Object { $_.Groups['n'].Value })
if (!(Set-Equals $expectedSafe $erlSafe)) {
  Fail ("safe_tools mismatch.`nExpected: {0}`nErlang:   {1}" -f ($expectedSafe -join ', '), ($erlSafe -join ', '))
}

# 3) Default tool set (names)
$expectedTools =
  @(
    'AskUserQuestion', 'Task',
    'Read', 'List', 'Write', 'Edit',
    'Glob', 'Grep',
    'Bash',
    'WebFetch', 'WebSearch',
    'NotebookEdit', 'lsp',
    'Skill', 'SlashCommand',
    'TodoWrite'
  )

$runtimeText = Norm-Text $ErlRuntime
$toolModsMatch = [regex]::Match($runtimeText, 'default_tools\(\)\s*->\s*\[(?<body>[\s\S]*?)\]\.', 'IgnoreCase')
if (!$toolModsMatch.Success) { Fail "Failed to parse default_tools() in $ErlRuntime" }
$mods = @([regex]::Matches($toolModsMatch.Groups['body'].Value, 'openagentic_tool_[a-z0-9_]+', 'IgnoreCase') | ForEach-Object { $_.Value } | Sort-Object -Unique)
if ($mods.Count -lt 1) { Fail "No tool modules found in default_tools() in $ErlRuntime" }

$srcDir = Join-Path $RepoRoot 'apps\openagentic_sdk\src'
$toolNames = @()
foreach ($mod in $mods) {
  $p = Join-Path $srcDir ($mod + '.erl')
  $t = Norm-Text $p
  $nm = [regex]::Match($t, 'name\(\)\s*->\s*<<\"(?<n>[^\"]+)\"', 'IgnoreCase')
  if (!$nm.Success) { Fail "Failed to parse name() in $p" }
  $toolNames += $nm.Groups['n'].Value
}

if (!(Set-Equals $expectedTools $toolNames)) {
  $onlyExp = @($expectedTools | Where-Object { $_ -notin $toolNames })
  $onlyGot = @($toolNames | Where-Object { $_ -notin $expectedTools })
  Fail ("Default tool name set mismatch.`nMissing: {0}`nExtra:   {1}" -f ($onlyExp -join ', '), ($onlyGot -join ', '))
}

# 4) Tool schema top-level properties + required (Kotlin snapshot)
$expectedSchema = @{
  'AskUserQuestion' = @{ props = @('questions', 'question', 'options', 'choices', 'answers'); required = @() }
  'Read' = @{ props = @('file_path', 'filePath', 'offset', 'limit'); required = @() }
  'List' = @{ props = @('path', 'dir', 'directory'); required = @() }
  'Write' = @{ props = @('file_path', 'filePath', 'content', 'overwrite'); required = @() }
  'Edit' = @{ props = @('file_path', 'filePath', 'old', 'new', 'old_string', 'new_string', 'oldString', 'newString', 'count', 'replace_all', 'replaceAll', 'before', 'after'); required = @() }
  'Glob' = @{ props = @('pattern', 'root'); required = @('pattern') }
  'Grep' = @{ props = @('query', 'file_glob', 'root', 'case_sensitive'); required = @('query') }
  'Bash' = @{ props = @('command', 'workdir', 'timeout', 'timeout_s'); required = @('command') }
  'WebSearch' = @{ props = @('query', 'max_results', 'allowed_domains', 'blocked_domains'); required = @('query') }
  'WebFetch' = @{ props = @('url', 'headers', 'mode', 'max_chars', 'prompt'); required = @('url') }
  'SlashCommand' = @{ props = @('name', 'args', 'arguments', 'project_dir'); required = @('name') }
  'Skill' = @{ props = @('name'); required = @('name') }
  'NotebookEdit' = @{ props = @('notebook_path', 'cell_id', 'new_source', 'cell_type', 'edit_mode'); required = @('notebook_path') }
  'lsp' = @{ props = @('operation', 'filePath', 'file_path', 'line', 'character'); required = @('operation', 'filePath', 'line', 'character') }
  'Task' = @{ props = @('agent', 'prompt'); required = @('agent', 'prompt') }
  'TodoWrite' = @{ props = @('todos'); required = @('todos') }
}

$schemaText = Norm-Text $ErlSchemas
foreach ($tool in $expectedSchema.Keys) {
  $toolEsc = [regex]::Escape($tool)
  $pattern = 'tool_params\([^\)]*,\s*<<"' + $toolEsc + '">>\)\s*->\s*#\{(?<body>[\s\S]*?)\};'
  $block = [regex]::Match($schemaText, $pattern, 'IgnoreCase')
  if (!$block.Success) { Fail "Missing tool_params clause for $tool in $ErlSchemas" }
  $body = $block.Groups['body'].Value
  foreach ($p in $expectedSchema[$tool].props) {
    if (-not [regex]::IsMatch($body, "(?m)^\s*'?$([regex]::Escape($p))'?\s*=>")) {
      Fail "Schema mismatch for ${tool}: missing property '$p'"
    }
  }
  $reqMatch = [regex]::Match($body, "(?m)^\s{4}required\s*=>\s*\[(?<req>[^\]]*)\]", 'IgnoreCase')
  $reqText = if ($reqMatch.Success) { $reqMatch.Groups['req'].Value } else { '' }
  foreach ($r in $expectedSchema[$tool].required) {
    if (-not ($reqText -match [regex]::Escape($r))) {
      Fail "Schema mismatch for ${tool}: required missing '$r'"
    }
  }
}

# 5) Sanity: Kotlin files exist (guards against stale paths)
if (!(Test-Path $KPerm)) { Fail "Missing Kotlin PermissionGate.kt: $KPerm" }
if (!(Test-Path $KSchemas)) { Fail "Missing Kotlin OpenAiToolSchemas.kt: $KSchemas" }

Write-Host "kotlin-parity-check OK"
