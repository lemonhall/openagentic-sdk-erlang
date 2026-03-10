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
$ErlPerm = Join-Path $RepoRoot 'apps\openagentic_sdk\src\openagentic_permissions\openagentic_permissions_policy.erl'
$ErlSchemasDir = Join-Path $RepoRoot 'apps\openagentic_sdk\src\openagentic_tool_schemas'
$ErlRuntime = Join-Path $RepoRoot 'apps\openagentic_sdk\src\openagentic_runtime\openagentic_runtime_options.erl'
$KPerm = Join-Path $KotlinRoot 'src\main\kotlin\me\lemonhall\openagentic\sdk\permissions\PermissionGate.kt'
$KSchemas = Join-Path $KotlinRoot 'src\main\kotlin\me\lemonhall\openagentic\sdk\tools\OpenAiToolSchemas.kt'

if (!(Test-Path $KotlinRoot)) { Fail "Kotlin repo not found: $KotlinRoot" }
if (!(Test-Path $ErlPrompts)) { Fail "Erlang toolprompts dir not found: $ErlPrompts" }
if (!(Test-Path $ErlPerm)) { Fail "Erlang permissions policy not found: $ErlPerm" }
if (!(Test-Path $ErlSchemasDir)) { Fail "Erlang tool schemas dir not found: $ErlSchemasDir" }
if (!(Test-Path $ErlRuntime)) { Fail "Erlang runtime options not found: $ErlRuntime" }
if (!(Test-Path $KPerm)) { Fail "Missing Kotlin PermissionGate.kt: $KPerm" }
if (!(Test-Path $KSchemas)) { Fail "Missing Kotlin OpenAiToolSchemas.kt: $KSchemas" }

$IntentionalPromptDivergence = @{
  'edit.txt' = 'workspace-scoped write semantics'
  'glob.txt' = 'rendered project/workspace context wording'
  'grep.txt' = 'rendered project/workspace context wording'
  'list.txt' = 'rendered project/workspace context wording'
  'read.txt' = 'rendered project/workspace context wording'
  'task.txt' = 'built-in subagent guidance'
  'write.txt' = 'workspace-scoped write semantics'
}

$IntentionalSafeAdds = @('List', 'WebFetch', 'WebSearch')

# 1) Toolprompt resources: exact file set; exact content except explicit, audited divergences.
$kFiles = @(Get-ChildItem -File -Force $KPrompts -Filter '*.txt' | Select-Object -ExpandProperty Name | Sort-Object)
$eFiles = @(Get-ChildItem -File -Force $ErlPrompts -Filter '*.txt' | Select-Object -ExpandProperty Name | Sort-Object)

if (!(Set-Equals $kFiles $eFiles)) {
  $onlyK = @($kFiles | Where-Object { $_ -notin $eFiles })
  $onlyE = @($eFiles | Where-Object { $_ -notin $kFiles })
  Fail ("Toolprompt file list mismatch.`nOnly Kotlin: {0}`nOnly Erlang: {1}" -f ($onlyK -join ', '), ($onlyE -join ', '))
}

$promptDivergences = @()
foreach ($f in $kFiles) {
  $a = Norm-Text (Join-Path $KPrompts $f)
  $b = Norm-Text (Join-Path $ErlPrompts $f)
  if ($a -eq $b) { continue }
  if ($IntentionalPromptDivergence.ContainsKey($f)) {
    $promptDivergences += ("{0}: {1}" -f $f, $IntentionalPromptDivergence[$f])
    continue
  }
  Fail "Toolprompt content mismatch: $f"
}

# 2) PermissionGate safe-tools set: Erlang should equal Kotlin + audited intentional additions.
$kPermText = Norm-Text $KPerm
$kSafeMatch = [regex]::Match($kPermText, 'val safe = setOf\((?<body>[\s\S]*?)\)', 'IgnoreCase')
if (!$kSafeMatch.Success) { Fail "Failed to parse Kotlin safe tool set in $KPerm" }
$kSafe = @([regex]::Matches($kSafeMatch.Groups['body'].Value, '"(?<n>[^"]+)"', 'IgnoreCase') | ForEach-Object { $_.Groups['n'].Value })
$expectedSafe = @($kSafe + $IntentionalSafeAdds | Sort-Object -Unique)

$erlPermText = Norm-Text $ErlPerm
$m = [regex]::Match($erlPermText, 'safe_tools\(\)\s*->\s*\[(?<body>[\s\S]*?)\]\.', 'IgnoreCase')
if (!$m.Success) { Fail "Failed to parse Erlang safe_tools() in $ErlPerm" }
$erlSafe = @([regex]::Matches($m.Groups['body'].Value, '<<\"(?<n>[^\"]+)\"', 'IgnoreCase') | ForEach-Object { $_.Groups['n'].Value })
if (!(Set-Equals $expectedSafe $erlSafe)) {
  $missing = @($expectedSafe | Where-Object { $_ -notin $erlSafe })
  $extra = @($erlSafe | Where-Object { $_ -notin $expectedSafe })
  Fail ("safe_tools mismatch.`nExpected: {0}`nMissing:  {1}`nExtra:    {2}" -f ($expectedSafe -join ', '), ($missing -join ', '), ($extra -join ', '))
}

# 3) Default tool set (names): compare current Erlang default_tools() to Kotlin schema registry names.
$kSchemaText = Norm-Text $KSchemas
$expectedTools = @([regex]::Matches($kSchemaText, 'schemasByName\["(?<n>[^"]+)"\]\s*=', 'IgnoreCase') | ForEach-Object { $_.Groups['n'].Value } | Sort-Object -Unique)
if ($expectedTools.Count -lt 1) { Fail "Failed to derive Kotlin tool names from $KSchemas" }

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

# 4) Tool schema top-level properties + required (Kotlin parity snapshot against current Erlang schema modules).
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

$schemaText = @(
  Get-ChildItem -File $ErlSchemasDir -Filter '*.erl' |
    Sort-Object Name |
    ForEach-Object { Norm-Text $_.FullName }
) -join "`n"

foreach ($tool in $expectedSchema.Keys) {
  $toolEsc = [regex]::Escape($tool)
  $startPattern = 'tool_params\([^\)]*,\s*<<"' + $toolEsc + '">>\)\s*->'
  $start = [regex]::Match($schemaText, $startPattern, 'IgnoreCase')
  if (!$start.Success) { Fail "Missing tool_params clause for $tool in $ErlSchemasDir" }
  $tail = $schemaText.Substring($start.Index)
  $next = [regex]::Match($tail.Substring($start.Length), '(^|\n)tool_params\([^\)]*,\s*<<"', 'IgnoreCase')
  $body = if ($next.Success) { $tail.Substring(0, $start.Length + $next.Index) } else { $tail }
  foreach ($p in $expectedSchema[$tool].props) {
    if (-not [regex]::IsMatch($body, "(?<![A-Za-z0-9_])'?$([regex]::Escape($p))'?\s*=>")) {
      Fail "Schema mismatch for ${tool}: missing property '$p'"
    }
  }
  $reqText = @(
    [regex]::Matches($body, "required\s*=>\s*\[(?<req>[^\]]*)\]", 'IgnoreCase') |
      ForEach-Object { $_.Groups['req'].Value }
  ) -join "`n"
  foreach ($r in $expectedSchema[$tool].required) {
    if (-not ($reqText -match [regex]::Escape($r))) {
      Fail "Schema mismatch for ${tool}: required missing '$r'"
    }
  }
}

if ($promptDivergences.Count -gt 0) {
  Write-Host ("Intentional toolprompt divergences: " + ($promptDivergences -join '; '))
}
Write-Host "kotlin-parity-check OK"
