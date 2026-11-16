param(
    [string]$Godot = "godot",
    [switch]$Capture,
    [switch]$ReviewOnly
)

$ErrorActionPreference = "Stop"
$projectPath = Split-Path -Parent $PSScriptRoot
function Invoke-DistrictTool {
    param([string[]]$Arguments)
    $previousErrorAction = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $result = & $Godot --path $projectPath @Arguments 2>&1
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previousErrorAction }
    $result | ForEach-Object { Write-Output $_ }
    if ($code -ne 0 -or ($result -match 'SCRIPT ERROR:|^ERROR:|FAIL:')) {
        throw "District authoring failed (exit $code)"
    }
}

Invoke-DistrictTool -Arguments @("--headless", "--editor", "--import", "--quit")
if ($ReviewOnly) { return }
Invoke-DistrictTool -Arguments @("--headless", "--script", "res://tools/build_district.gd")
Invoke-DistrictTool -Arguments @("--headless", "--script", "res://tests/district_tests.gd")
Invoke-DistrictTool -Arguments @("--headless", "--script", "res://tests/campus_tests.gd")
if ($Capture) {
    Invoke-DistrictTool -Arguments @("--resolution", "1920x1080", "--script", "res://tests/district_review.gd")
}
