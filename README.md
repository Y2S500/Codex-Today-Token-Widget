# Codex Today Token Widget

Windows desktop widget for today's Codex token usage, current model, and estimated cost.

## Displays

- Today's total tokens.
- Today's input, cached input, uncached input, output, reasoning tokens, and call count.
- Current model detected from today's calls.
- Estimated cost for today's calls.
- Pricing source and fetch time.

## Prerequisites

- Windows 10 or Windows 11.
- Windows PowerShell 5.1 and .NET WPF, included with Windows.
- Codex Desktop or Codex CLI with plugin support; hooks must be enabled (`[features] hooks = true`).
- Codex Usage Tracker runtime: https://github.com/douglasmonsky/codex-usage-tracker
  - Python 3.10 or newer.
  - `pipx` is recommended for installing the tracker in an isolated environment.
  - Node.js 22 or newer and npm on PATH are required by the tracker's plugin marketplace flow.
  - `codex-usage-tracker.exe` must be available on PATH.
  - Run `codex-usage-tracker setup` and `codex-usage-tracker refresh --wait 30` once.
- Network access to the official DeepSeek pricing page and the Chinese government holiday notice for `Update-Pricing.ps1`. The repository includes `pricing.json` and `holidays.json` for offline use.
- No API key is required by this widget. It reads local Codex usage data.
- Official price mapping currently covers `deepseek-flash` and `deepseek-v4-pro`. Other models display without an estimated price until the table is extended.
- Run `Check-Prerequisites.cmd` to verify the environment.

## Pricing source

- DeepSeek official Models & Pricing: https://api-docs.deepseek.com/quick_start/pricing
- Chinese public holiday schedule: https://www.gov.cn/zhengce/content/202511/content_7047090.htm

The widget follows the official DeepSeek peak/off-peak rule:

- Peak: 01:00-04:00 and 06:00-10:00 UTC, Monday-Friday.
- Off-peak: all other times, weekends, and Chinese public holidays.
- Current holiday list is for 2026.

The estimated cost uses cached input, uncached input, and output tokens. Reasoning tokens are displayed separately but are not added to the cost calculation to avoid double counting.

## Window and tray behavior

- The window is always on top by default.
- It does not appear in the Windows taskbar.
- The minimize and close buttons hide it to the tray.
- The tray icon stays active while the widget is running.
- Windows 11 may place the tray icon in the ^ overflow; drag it out once to pin it.
- Double-click the tray icon to show or hide the window.
- Tray menu: Show/Hide, Refresh, Update Price, Exit. The window has a single Refresh button.
- The widget is not started at Windows boot.

## Starting with Codex

The local Codex plugin `token-widget-launcher` starts the widget from the `SessionStart` hook. Approve the hook once when Codex asks for hook review. After that, opening Codex starts the widget automatically; if it is already running, no duplicate instance is created.

## Manual launch

Run `Launch-TokenUsageWidget.cmd`, or `Launch-TokenUsageWidget.vbs` to avoid a console flash.

## Update prices

Run `Update-Pricing.ps1`, or use the tray menu's Update Price command. The update reads the official DeepSeek pricing page and writes `pricing.json`.
