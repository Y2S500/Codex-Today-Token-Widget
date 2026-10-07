$ErrorActionPreference = 'Continue'
$packageRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$results = New-Object System.Collections.Generic.List[object]

function Add-Check {
    param([string]$Name, [bool]$Ok, [string]$Detail)
    $results.Add([pscustomobject]@{ Check = $Name; Ok = $Ok; Detail = $Detail }) | Out-Null
}

Add-Check 'Windows' ($env:OS -eq 'Windows_NT') ($env:OS)
Add-Check 'PowerShell' ($PSVersionTable.PSVersion.Major -ge 5) ($PSVersionTable.PSVersion.ToString())
$wpfOk = $false
 try { Add-Type -AssemblyName PresentationFramework -ErrorAction Stop; $wpfOk = $true } catch { $wpfOk = $false }
Add-Check 'WPF assemblies' $wpfOk 'PresentationFramework'

$codex = (Get-Command codex.exe -ErrorAction SilentlyContinue).Source
if (-not $codex) { $codex = $env:CODEX_CLI_PATH }
Add-Check 'Codex CLI' ([bool]($codex -and (Test-Path -LiteralPath $codex))) $(if($codex){$codex}else{'codex.exe not found'})

$tracker = (Get-Command codex-usage-tracker.exe -ErrorAction SilentlyContinue).Source
if (-not $tracker) { $tracker = Join-Path $env:APPDATA 'npm\codex-usage-tracker.exe' }
Add-Check 'Codex Usage Tracker runtime' ([bool](Test-Path -LiteralPath $tracker)) $(if($tracker){$tracker}else{'codex-usage-tracker.exe not found'})

Add-Check 'pricing.json' (Test-Path -LiteralPath (Join-Path $packageRoot 'pricing.json')) 'bundled official price table'
Add-Check 'holidays.json' (Test-Path -LiteralPath (Join-Path $packageRoot 'holidays.json')) 'bundled 2026 Chinese holiday table'

$results | Format-Table -AutoSize
if ($results.Where({ -not $_.Ok }).Count -gt 0) {
    Write-Host ''
    Write-Host 'Missing prerequisites. Install Codex Usage Tracker and ensure codex-usage-tracker.exe is on PATH.'
    Write-Host 'Tracker source: https://github.com/douglasmonsky/codex-usage-tracker'
    exit 1
}
Write-Host ''
Write-Host 'All prerequisites are present.'
