param(
    [string]$TrackerExe = ''
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Xaml
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$script:WidgetDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:IsCompact = $false
$script:Exiting = $false
$script:HasShownTrayTip = $false
$script:HwndSource = $null
$script:WndProcHook = $null
$script:Today = Get-Date -Format 'yyyy-MM-dd'
$script:Pricing = $null
$script:HolidaySet = @{}
$script:QueryJson = ''

function Resolve-Tracker {
    param([string]$Explicit)
    if ($Explicit -and (Test-Path -LiteralPath $Explicit)) { return (Resolve-Path -LiteralPath $Explicit).Path }
    $command = Get-Command codex-usage-tracker.exe -ErrorAction SilentlyContinue
    if ($command -and $command.Source) { return $command.Source }
    $candidates = @(
        (Join-Path $env:APPDATA 'npm\codex-usage-tracker.exe'),
    )
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) { return (Resolve-Path -LiteralPath $candidate).Path }
    }
    return $null
}

$script:Tracker = Resolve-Tracker -Explicit $TrackerExe
if (-not $script:Tracker) {
    [System.Windows.MessageBox]::Show('找不到 codex-usage-tracker.exe。请先确认 Codex Usage Tracker 插件已安装。', 'Codex Token Usage') | Out-Null
    exit 1
}

$xamlPath = Join-Path $script:WidgetDir 'TokenUsageWidget.xaml'
[xml]$xaml = Get-Content -Raw -LiteralPath $xamlPath
$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

$totalValue = $window.FindName('TotalValue')
$inputValue = $window.FindName('InputValue')
$cachedValue = $window.FindName('CachedValue')
$uncachedValue = $window.FindName('UncachedValue')
$outputValue = $window.FindName('OutputValue')
$reasoningValue = $window.FindName('ReasoningValue')
$callsValue = $window.FindName('CallsValue')
$statusText = $window.FindName('StatusText')
$updatedText = $window.FindName('UpdatedText')
$detailsGrid = $window.FindName('DetailsGrid')
$rootBorder = $window.FindName('RootBorder')
$compactButton = $window.FindName('CompactButton')
$closeButton = $window.FindName('CloseButton')
$refreshButton = $window.FindName('RefreshButton')
$topmostCheck = $window.FindName('TopmostCheck')
$modelValue = $window.FindName('ModelValue')
$costValue = $window.FindName('CostValue')
$pricingSourceText = $window.FindName('PricingSourceText')

function Format-Number {
    param($Value)
    if ($null -eq $Value) { return '—' }
    return ('{0:N0}' -f [int64]$Value)
}

function Invoke-TrackerProcess {
    param([string]$Arguments)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $script:Tracker
    $psi.Arguments = $Arguments
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $process = [System.Diagnostics.Process]::Start($psi)
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    if ($process.ExitCode -ne 0 -or -not [string]::IsNullOrWhiteSpace($stderr)) {
        throw (($stderr + $stdout).Trim())
    }
    return $stdout
}

function Set-ZeroRow {
    $totalValue.Text = '0'
    $inputValue.Text = '0'
    $cachedValue.Text = '0'
    $uncachedValue.Text = '0'
    $outputValue.Text = '0'
    $reasoningValue.Text = '0'
    $callsValue.Text = '0'
}

function Get-TodayQueryJson {
    $today = Get-Date -Format 'yyyy-MM-dd'
    return '{"requests":[{"dataset":"calls","operation":"aggregate","dimensions":["time_day"],"measures":["calls","input_tokens","cached_input_tokens","uncached_input_tokens","output_tokens","reasoning_tokens","total_tokens"],"filters":[{"field":"time_day","operator":"eq","value":"' + $today + '"}],"limit":1}]}'
}

function Invoke-TrackerQuery {
    param($Payload)
    $json = $Payload | ConvertTo-Json -Compress -Depth 20
    $queryArgs = "query --request `"$($json -replace '"','\"')`""
    $raw = Invoke-TrackerProcess -Arguments $queryArgs
    return ($raw | ConvertFrom-Json)
}

function Load-PricingData {
    $script:Pricing = $null
    $script:HolidaySet = @{}
    $pricingPath = Join-Path $script:WidgetDir 'pricing.json'
    $holidayPath = Join-Path $script:WidgetDir 'holidays.json'
    if (Test-Path -LiteralPath $pricingPath) {
        $script:Pricing = Get-Content -Raw -LiteralPath $pricingPath | ConvertFrom-Json
    }
    if (Test-Path -LiteralPath $holidayPath) {
        $holidays = Get-Content -Raw -LiteralPath $holidayPath | ConvertFrom-Json
        foreach ($yearProperty in $holidays.holidays.PSObject.Properties) {
            foreach ($item in $yearProperty.Value) {
                $start = [datetime]::ParseExact([string]$item.start, 'yyyy-MM-dd', $null)
                $end = [datetime]::ParseExact([string]$item.end, 'yyyy-MM-dd', $null)
                for ($day = $start; $day -le $end; $day = $day.AddDays(1)) {
                    $script:HolidaySet[$day.ToString('yyyy-MM-dd')] = $true
                }
            }
        }
    }
}

function Get-ConfiguredModel {
    $configPath = Join-Path $env:USERPROFILE '.codex\config.toml'
    if (Test-Path -LiteralPath $configPath) {
        $match = [regex]::Match((Get-Content -Raw -LiteralPath $configPath), '(?m)^model\s*=\s*"([^"]+)"')
        if ($match.Success) { return $match.Groups[1].Value }
    }
    return $null
}

function Get-TodaySummary {
    param([string]$Today)
    $request = [ordered]@{
        dataset = 'calls'
        operation = 'aggregate'
        dimensions = @()
        measures = @('calls','input_tokens','cached_input_tokens','uncached_input_tokens','output_tokens','reasoning_tokens','total_tokens')
        filters = @([ordered]@{ field = 'time_day'; operator = 'eq'; value = $Today })
        limit = 1
    }
    $payload = [ordered]@{ requests = @($request) }
    return (Invoke-TrackerQuery $payload).results[0]
}

function Get-TodayRows {
    param([string]$Today)
    $rows = New-Object System.Collections.Generic.List[object]
    $cursor = $null
    while ($true) {
        $request = [ordered]@{
            dataset = 'calls'
            operation = 'rows'
            dimensions = @('event_at','model')
            measures = @('cached_input_tokens','uncached_input_tokens','output_tokens')
            filters = @([ordered]@{ field = 'time_day'; operator = 'eq'; value = $Today })
            order_by = 'event_at'
            descending = $false
            limit = 500
        }
        if ($cursor) { $request.cursor = $cursor }
        $payload = [ordered]@{ requests = @($request) }
        $result = (Invoke-TrackerQuery $payload).results[0]
        if ($result.rows) { foreach ($row in $result.rows) { $rows.Add($row) | Out-Null } }
        if (-not $result.next_cursor) { break }
        $cursor = $result.next_cursor
    }
    return $rows
}

function Test-PeakRate {
    param([string]$EventAt)
    if (-not $script:Pricing) { return $false }
    $utc = [DateTimeOffset]::Parse($EventAt).UtcDateTime
    $date = $utc.ToString('yyyy-MM-dd')
    if ($script:HolidaySet.ContainsKey($date)) { return $false }
    if ($utc.DayOfWeek -eq [DayOfWeek]::Saturday -or $utc.DayOfWeek -eq [DayOfWeek]::Sunday) { return $false }
    $minutes = $utc.Hour * 60 + $utc.Minute
    return (($minutes -ge 60 -and $minutes -lt 240) -or ($minutes -ge 360 -and $minutes -lt 600))
}

function Calculate-TodayCost {
    param($Rows)
    $cost = [double]0
    $missing = $false
    $models = New-Object System.Collections.Generic.HashSet[string]
    if (-not $script:Pricing) {
        return [ordered]@{ cost = 0; missing = $true; models = @() }
    }
    foreach ($row in $Rows) {
        if ($row.model) { [void]$models.Add([string]$row.model) }
        $modelPricing = $null
        if ($row.model) {
            $property = $script:Pricing.models.PSObject.Properties[[string]$row.model]
            if ($property) { $modelPricing = $property.Value }
        }
        if (-not $modelPricing) {
            $missing = $true
            continue
        }
        $tier = if (Test-PeakRate ([string]$row.event_at)) { $modelPricing.peak } else { $modelPricing.off_peak }
        $cost += ([double]$row.cached_input_tokens / 1000000.0) * [double]$tier.cache_hit
        $cost += ([double]$row.uncached_input_tokens / 1000000.0) * [double]$tier.cache_miss
        $cost += ([double]$row.output_tokens / 1000000.0) * [double]$tier.output
    }
    return [ordered]@{ cost = $cost; missing = $missing; models = @($models) }
}

function Update-PricingFile {
    $updateScript = Join-Path $script:WidgetDir 'Update-Pricing.ps1'
    if (-not (Test-Path -LiteralPath $updateScript)) { return }
    Start-Process -FilePath 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$updateScript) -WindowStyle Hidden -Wait
    Load-PricingData
}

function Update-Usage {
    try {
        $script:Today = Get-Date -Format 'yyyy-MM-dd'
        Load-PricingData
        $summary = Get-TodaySummary -Today $script:Today
        if (-not $summary) { throw '没有可用结果' }
        if (@($summary.rows).Count -eq 0) {
            Set-ZeroRow
        }
        else {
            $row = $summary.rows[0]
            $totalValue.Text = Format-Number $row.total_tokens
            $inputValue.Text = Format-Number $row.input_tokens
            $cachedValue.Text = Format-Number $row.cached_input_tokens
            $uncachedValue.Text = Format-Number $row.uncached_input_tokens
            $outputValue.Text = Format-Number $row.output_tokens
            $reasoningValue.Text = Format-Number $row.reasoning_tokens
            $callsValue.Text = Format-Number $row.calls
        }

        $callRows = Get-TodayRows -Today $script:Today
        $costInfo = Calculate-TodayCost -Rows $callRows
        $modelNames = @($costInfo.models)
        if ($modelNames.Count -eq 0) {
            $configuredModel = Get-ConfiguredModel
            if ($configuredModel) { $modelNames = @($configuredModel) }
        }

        $displayModels = @()
        foreach ($modelName in $modelNames) {
            $modelProperty = $null
            if ($script:Pricing) {
                $modelProperty = $script:Pricing.models.PSObject.Properties[[string]$modelName]
            }
            if ($modelProperty -and $modelProperty.Value.display_name) {
                $displayModels += "$($modelProperty.Value.display_name) ($modelName)"
            }
            else {
                $displayModels += [string]$modelName
            }
        }
        if ($displayModels.Count -gt 0) {
            $modelValue.Text = ($displayModels -join ', ')
        }
        else {
            $modelValue.Text = '未知模型'
        }

        if ($script:Pricing) {
            $fetched = [DateTimeOffset]::Parse([string]$script:Pricing.fetched_at).ToLocalTime().ToString('MM-dd HH:mm')
            $pricingSourceText.Text = "DeepSeek 官网价 · $fetched"
        }
        else {
            $pricingSourceText.Text = '未找到官网价格'
        }

        if ($script:Pricing -and -not $costInfo.missing) {
            $costValue.Text = '$' + ([double]$costInfo.cost).ToString('0.0000')
        }
        elseif ($script:Pricing -and $costInfo.missing) {
            $costValue.Text = '≈ $' + ([double]$costInfo.cost).ToString('0.0000') + '*'
        }
        else {
            $costValue.Text = '—'
        }

        $statusText.Text = "今日 $script:Today · generation $($summary.generation) · $($summary.grade)"
        $updatedText.Text = "更新于 $(Get-Date -Format 'HH:mm:ss')"
        $rootBorder.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#304ADE80')
        if ($script:NotifyIcon) {
            $tooltip = "Codex 今日 Token: $($totalValue.Text)"
            if ($costValue.Text -ne '—') { $tooltip += " · $($costValue.Text)" }
            $script:NotifyIcon.Text = $tooltip
        }
    }
    catch {
        $statusText.Text = '读取失败'
        $updatedText.Text = $_.Exception.Message
        $rootBorder.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#30F87171')
    }
}

function Start-TrackerRefresh {
    try {
        $null = Invoke-TrackerProcess -Arguments 'refresh --wait 0'
    }
    catch {
        # The next query will surface a useful status if refresh is unavailable.
    }
}

function Toggle-Window {
    if ($window.IsVisible) {
        $window.Hide()
    }
    else {
        $window.Show()
        $window.Activate()
    }
}

function Hide-ToTray {
    $window.Hide()
    if ($script:NotifyIcon -and -not $script:HasShownTrayTip) {
        $script:NotifyIcon.ShowBalloonTip(2500, 'Codex Token Usage', '小部件已隐藏到右下角托盘，点击 ^ 可找到。', [System.Windows.Forms.ToolTipIcon]::Info)
        $script:HasShownTrayTip = $true
    }
}

function Exit-Widget {
    $script:Exiting = $true
    if ($script:NotifyIcon) {
        $script:NotifyIcon.Visible = $false
        $script:NotifyIcon.Dispose()
        $script:NotifyIcon = $null
    }
    $window.Close()
    [System.Windows.Threading.Dispatcher]::CurrentDispatcher.InvokeShutdown()
}

$script:NotifyIcon = $null
$trayIconPath = Join-Path $script:WidgetDir 'TokenUsageWidget.ico'
if (Test-Path -LiteralPath $trayIconPath) {
    $script:NotifyIcon = New-Object System.Windows.Forms.NotifyIcon
    $script:NotifyIcon.Icon = New-Object System.Drawing.Icon -ArgumentList $trayIconPath
    $script:NotifyIcon.Text = 'Codex 今日 Token'
    $script:NotifyIcon.Visible = $true

    $trayMenu = New-Object System.Windows.Forms.ContextMenuStrip
    $showItem = $trayMenu.Items.Add('显示/隐藏')
    $refreshItem = $trayMenu.Items.Add('刷新')
    $priceItem = $trayMenu.Items.Add('更新价格')
    $exitItem = $trayMenu.Items.Add('退出')

    $showItem.Add_Click({ Toggle-Window })
    $refreshItem.Add_Click({ Start-TrackerRefresh; Update-Usage })
    $priceItem.Add_Click({ Update-PricingFile; Update-Usage })
    $exitItem.Add_Click({ Exit-Widget })
    $script:NotifyIcon.ContextMenuStrip = $trayMenu
    $script:NotifyIcon.Add_DoubleClick({ Toggle-Window })
}

$compactButton.Add_Click({ Hide-ToTray })

$closeButton.Add_Click({ Hide-ToTray })

$refreshButton.Add_Click({
    $statusText.Text = '刷新中…'
    Start-TrackerRefresh
    Start-Sleep -Milliseconds 250
    Update-Usage
})


$topmostCheck.Add_Click({
    $window.Topmost = [bool]$topmostCheck.IsChecked
})

$rootBorder.Add_MouseLeftButtonDown({
    if ($_.ChangedButton -eq [System.Windows.Input.MouseButton]::Left) {
        $window.DragMove()
    }
})

$window.Add_SourceInitialized({
    $helper = New-Object System.Windows.Interop.WindowInteropHelper -ArgumentList $window
    $script:HwndSource = [System.Windows.Interop.HwndSource]::FromHwnd($helper.Handle)
    $script:WndProcHook = {
        param($hwnd, $msg, $wParam, $lParam, [ref]$handled)
        if ($msg -eq 0x0010 -and -not $script:Exiting) {
            Hide-ToTray
            $handled.Value = $true
        }
        return [IntPtr]::Zero
    }
    $script:HwndSource.AddHook($script:WndProcHook)
})

$window.Add_Loaded({
    $work = [System.Windows.SystemParameters]::WorkArea
    $window.Left = $work.Right - $window.Width - 24
    $window.Top = $work.Top + 24
    Update-Usage
})

$queryTimer = New-Object System.Windows.Threading.DispatcherTimer
$queryTimer.Interval = [TimeSpan]::FromSeconds(12)
$queryTimer.Add_Tick({ Update-Usage })
$queryTimer.Start()

$refreshTimer = New-Object System.Windows.Threading.DispatcherTimer
$refreshTimer.Interval = [TimeSpan]::FromMinutes(3)
$refreshTimer.Add_Tick({ Start-TrackerRefresh })
$refreshTimer.Start()

$window.Add_Closed({
    $queryTimer.Stop()
    $refreshTimer.Stop()
    if ($script:NotifyIcon) {
        $script:NotifyIcon.Visible = $false
        $script:NotifyIcon.Dispose()
        $script:NotifyIcon = $null
    }
    [System.Windows.Threading.Dispatcher]::CurrentDispatcher.InvokeShutdown()
})

$window.Show()
[System.Windows.Threading.Dispatcher]::Run()
