$ErrorActionPreference = 'Stop'
$codex = (Get-Command codex.exe -ErrorAction SilentlyContinue).Source
if (-not $codex) { $codex = $env:CODEX_CLI_PATH }
if ($codex -and (Test-Path -LiteralPath $codex)) {
    & $codex plugin remove token-widget-launcher@token-widget-launcher --json
    & $codex plugin marketplace remove token-widget-launcher
}
Write-Host 'Codex token widget hook removed.'
