param(
    [string]$Godot = "godot",
    [switch]$Capture
)

$ErrorActionPreference = "Stop"
$projectPath = Split-Path -Parent $PSScriptRoot
function Invoke-GodotCheck {
    param([string[]]$Arguments, [switch]$PackOnly)
    $pathArguments = @("--path", $projectPath)
    if ($PackOnly) { $pathArguments = @() }
    $previousErrorAction = $ErrorActionPreference
    try {
        # Collect stderr as well as the final report before failing the check.
        $ErrorActionPreference = "Continue"
        $checkOutput = & $Godot @pathArguments @Arguments 2>&1
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorAction
    }
    $checkOutput | ForEach-Object { Write-Output $_ }
    if ($code -ne 0 -or ($checkOutput -match 'SCRIPT ERROR:|^ERROR:|FAIL:')) {
        throw "Godot check failed (exit $code)"
    }
}

if (Get-Command python -ErrorAction SilentlyContinue) {
    & python "$projectPath/tools/verify_armory.py"
} else {
    & py -3 "$projectPath/tools/verify_armory.py"
}
if ($LASTEXITCODE -ne 0) { throw "Armory snapshot verification failed" }
Invoke-GodotCheck -Arguments @("--headless", "--editor", "--import", "--quit")
Invoke-GodotCheck -Arguments @("--headless", "--script", "res://tests/run_tests.gd")
Invoke-GodotCheck -Arguments @("--headless", "--script", "res://tests/voxel_tests.gd")
Invoke-GodotCheck -Arguments @("--headless", "--script", "res://tests/signal_decay_tests.gd")
Invoke-GodotCheck -Arguments @("--headless", "--script", "res://tests/hand_poses.gd")
Invoke-GodotCheck -Arguments @("--headless", "--script", "res://tests/application_smoke.gd")
Invoke-GodotCheck -Arguments @("--headless", "--script", "res://tests/persistence_restart.gd", "--", "--write")
Invoke-GodotCheck -Arguments @("--headless", "--script", "res://tests/persistence_restart.gd", "--", "--read")
Invoke-GodotCheck -Arguments @("--headless", "--export-pack", "Windows Desktop", ".godot/last-haul-armory.pck")
Invoke-GodotCheck -PackOnly -Arguments @("--headless", "--main-pack", "$projectPath/.godot/last-haul-armory.pck", "--script", "$projectPath/tests/export_smoke.gd")
if ($Capture) {
    Invoke-GodotCheck -Arguments @("--resolution", "1280x720", "--script", "res://tests/signal_decay_tests.gd", "--", "--capture", "--benchmark")
    Invoke-GodotCheck -Arguments @("--resolution", "1280x720", "--script", "res://tests/application_smoke.gd", "--", "--capture")
    Invoke-GodotCheck -Arguments @("--resolution", "1280x720", "--script", "res://tests/hand_review.gd")
}
