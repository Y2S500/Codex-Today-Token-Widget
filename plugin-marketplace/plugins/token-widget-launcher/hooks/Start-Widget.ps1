$ErrorActionPreference = 'SilentlyContinue'
$candidates = New-Object System.Collections.Generic.List[string]
$pathFile = Join-Path $PSScriptRoot 'widget-path.txt'
if (Test-Path -LiteralPath $pathFile) {
    $configured = (Get-Content -Raw -LiteralPath $pathFile).Trim()
    if ($configured) { $candidates.Add($configured) }
}
$desktop = [Environment]::GetFolderPath('Desktop')
$candidates.Add((Join-Path $desktop 'Codex-Today-Token-Widget\TokenUsageWidget.ps1'))
$widget = $candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
if (-not $widget) { exit 0 }
$running = Get-CimInstance Win32_Process | Where-Object {
    $_.Name -eq 'powershell.exe' -and $_.CommandLine -match 'TokenUsageWidget\.ps1'
}
if ($running) { exit 0 }
Start-Process -FilePath 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-STA','-WindowStyle','Hidden','-File',$widget) -WindowStyle Hidden
