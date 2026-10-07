$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$widgetDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$sourceUrl = 'https://api-docs.deepseek.com/quick_start/pricing'

$response = Invoke-WebRequest -UseBasicParsing -Uri $sourceUrl -Headers @{ 'User-Agent' = 'Mozilla/5.0' } -TimeoutSec 30
$text = [regex]::Replace($response.Content, '<script[\s\S]*?</script>|<style[\s\S]*?</style>', ' ')
$text = [regex]::Replace($text, '<[^>]+>', ' ')
$text = [System.Net.WebUtility]::HtmlDecode($text)
$text = [regex]::Replace($text, '\s+', ' ')

function Get-Rates {
    param([string]$Label)
    $pattern = [regex]::Escape($Label) + '\s*OFF-PEAK\s*\$([0-9.]+)\s*\$([0-9.]+)\s*PEAK\s*\$([0-9.]+)\s*\$([0-9.]+)'
    $match = [regex]::Match($text, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $match.Success) { throw "Could not parse pricing section: $Label" }
    return @{
        flash_off_peak = [double]$match.Groups[1].Value
        pro_off_peak = [double]$match.Groups[2].Value
        flash_peak = [double]$match.Groups[3].Value
        pro_peak = [double]$match.Groups[4].Value
    }
}

$cacheHit = Get-Rates '1M INPUT TOKENS (CACHE HIT)'
$cacheMiss = Get-Rates '1M INPUT TOKENS (CACHE MISS)'
$output = Get-Rates '1M OUTPUT TOKENS'

$pricing = [ordered]@{
    source = 'DeepSeek API Docs - Models & Pricing'
    source_url = $sourceUrl
    fetched_at = (Get-Date).ToString('o')
    currency = 'USD'
    unit = 'per_1m_tokens'
    peak_hours_utc = @(@(1, 4), @(6, 10))
    peak_weekdays = @('Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday')
    holiday_source_url = 'https://www.gov.cn/zhengce/content/202511/content_7047090.htm'
    notes = @(
        'Official DeepSeek prices. Off-peak rates are half of peak rates.',
        'Reasoning tokens are displayed separately; estimated cost uses output tokens only to avoid double counting.'
    )
    models = [ordered]@{
        'deepseek-flash' = [ordered]@{
            display_name = 'DeepSeek V4.1 Flash'
            off_peak = [ordered]@{ cache_hit = $cacheHit.flash_off_peak; cache_miss = $cacheMiss.flash_off_peak; output = $output.flash_off_peak }
            peak = [ordered]@{ cache_hit = $cacheHit.flash_peak; cache_miss = $cacheMiss.flash_peak; output = $output.flash_peak }
        }
        'deepseek-v4-pro' = [ordered]@{
            display_name = 'DeepSeek V4 Pro'
            off_peak = [ordered]@{ cache_hit = $cacheHit.pro_off_peak; cache_miss = $cacheMiss.pro_off_peak; output = $output.pro_off_peak }
            peak = [ordered]@{ cache_hit = $cacheHit.pro_peak; cache_miss = $cacheMiss.pro_peak; output = $output.pro_peak }
        }
    }
}

$pricing | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $widgetDir 'pricing.json') -Encoding UTF8
Write-Output "Updated pricing.json from $sourceUrl"
