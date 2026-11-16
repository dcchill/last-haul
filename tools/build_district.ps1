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

& python "$projectPath/tools/build_district_signs.py"
if ($LASTEXITCODE -ne 0) { throw "Sign generation failed" }
Invoke-DistrictTool -Arguments @("--headless", "--editor", "--import", "--quit")
Invoke-DistrictTool -Arguments @("--headless", "--script", "res://tools/build_district_assets.gd")
Invoke-DistrictTool -Arguments @("--headless", "--script", "res://tools/review_district_assets.gd")
Invoke-DistrictTool -Arguments @("--headless", "--script", "res://tools/build_art_showcase.gd")
if ($Capture) {
    Invoke-DistrictTool -Arguments @("--resolution", "768x768", "--script", "res://tools/review_district_assets.gd")
    Invoke-DistrictTool -Arguments @("--resolution", "1280x720", "--script", "res://tools/review_art_showcase.gd")
}
if ($ReviewOnly) { return }
Invoke-DistrictTool -Arguments @("--headless", "--script", "res://tools/build_district.gd")
Invoke-DistrictTool -Arguments @("--headless", "--script", "res://tests/district_tests.gd")
if ($Capture) {
    Invoke-DistrictTool -Arguments @("--resolution", "1920x1080", "--script", "res://tests/district_review.gd")
}
