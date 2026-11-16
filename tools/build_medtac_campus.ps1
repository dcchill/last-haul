param(
    [string]$Godot = "C:/Users/dsmar/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe",
    [switch]$Capture
)

# Rebuilds the MedTac Research Campus: printed signs, import, authoring,
# floor scene split, navigation bake, validation, then the integration test.
$ErrorActionPreference = "Stop"
$projectPath = Split-Path -Parent $PSScriptRoot
function Invoke-CampusTool {
    param([string[]]$Arguments)
    $previousErrorAction = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $result = & $Godot --path $projectPath @Arguments 2>&1
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previousErrorAction }
    $result | ForEach-Object { Write-Output $_ }
    if ($code -ne 0 -or ($result -match 'SCRIPT ERROR:|FAIL:|CAMPUS ERROR:')) {
        throw "Campus authoring failed (exit $code)"
    }
}

if (Get-Command python -ErrorAction SilentlyContinue) { & python "$projectPath/tools/build_campus_signs.py" }
else { & py -3 "$projectPath/tools/build_campus_signs.py" }
if ($LASTEXITCODE -ne 0) { throw "Campus sign generation failed" }
Invoke-CampusTool -Arguments @("--headless", "--editor", "--import", "--quit")
Invoke-CampusTool -Arguments @("--headless", "--script", "res://tools/build_medtac_campus.gd")
Invoke-CampusTool -Arguments @("--headless", "--editor", "--import", "--quit")
Invoke-CampusTool -Arguments @("--headless", "--script", "res://tests/medtac_campus_tests.gd")
if ($Capture) {
    Invoke-CampusTool -Arguments @("--resolution", "1920x1080", "--script", "res://tests/medtac_campus_review.gd")
}
