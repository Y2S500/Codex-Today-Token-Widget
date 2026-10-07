$ErrorActionPreference = 'Stop'
$packageRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$marketplace = Join-Path $packageRoot 'plugin-marketplace'
$codex = (Get-Command codex.exe -ErrorAction SilentlyContinue).Source
if (-not $codex) { $codex = $env:CODEX_CLI_PATH }
if (-not $codex -or -not (Test-Path -LiteralPath $codex)) { throw 'codex.exe was not found.' }

$marketplaceList = & $codex plugin marketplace list 2>&1 | Out-String
if ($marketplaceList -notmatch '(?m)^token-widget-launcher\s') {
    & $codex plugin marketplace add $marketplace --json
}

& $codex plugin add token-widget-launcher@token-widget-launcher --json

$configPath = Join-Path $env:USERPROFILE '.codex\config.toml'
if (-not (Test-Path -LiteralPath $configPath)) { throw "Codex config not found: $configPath" }
$config = Get-Content -Raw -LiteralPath $configPath
if ($config -match '(?m)^\[features\]\s*$') {
    if ($config -notmatch '(?m)^hooks\s*=\s*true\s*$') {
        $config = [regex]::Replace($config, '(?m)^\[features\]\s*$', "[features]`nhooks = true", 1)
        Set-Content -LiteralPath $configPath -Value $config -Encoding UTF8
    }
}
else {
    Add-Content -LiteralPath $configPath -Value "`n[features]`nhooks = true`n" -Encoding UTF8
}

$widgetPath = Join-Path $packageRoot 'TokenUsageWidget.ps1'
$cacheHooks = Join-Path $env:USERPROFILE '.codex\plugins\cache\token-widget-launcher\token-widget-launcher\1.0.0\hooks'
New-Item -ItemType Directory -Force -Path $cacheHooks | Out-Null
$portableStart = Join-Path $marketplace 'plugins\token-widget-launcher\hooks\Start-Widget.ps1'
Copy-Item -LiteralPath $portableStart -Destination (Join-Path $cacheHooks 'Start-Widget.ps1') -Force
Set-Content -LiteralPath (Join-Path $cacheHooks 'widget-path.txt') -Value $widgetPath -Encoding UTF8

Write-Host ''
Write-Host 'Codex hook installed.'
Write-Host 'When Codex shows Hooks need review, approve the token-widget-launcher SessionStart hook once.'
