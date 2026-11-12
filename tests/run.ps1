param(
    [string]$Godot = "godot",
    [switch]$Capture
)

$ErrorActionPreference = "Stop"
$projectPath = Split-Path -Parent $PSScriptRoot

function Invoke-GodotCheck {
    param([string[]]$Arguments)
    & $Godot --path $projectPath @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Godot check failed with exit code $LASTEXITCODE" }
}

Invoke-GodotCheck -Arguments @("--headless", "--editor", "--import", "--quit")
Invoke-GodotCheck -Arguments @("--headless", "--script", "res://tests/run_tests.gd")
Invoke-GodotCheck -Arguments @("--headless", "--script", "res://tests/application_smoke.gd")
Invoke-GodotCheck -Arguments @("--headless", "--script", "res://tests/persistence_restart.gd", "--", "--write")
Invoke-GodotCheck -Arguments @("--headless", "--script", "res://tests/persistence_restart.gd", "--", "--read")
if ($Capture) {
    Invoke-GodotCheck -Arguments @("--resolution", "1280x720", "--script", "res://tests/application_smoke.gd", "--", "--capture")
}
