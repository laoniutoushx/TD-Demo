param(
    [string]$GodotExecutable = 'H:\Godot\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64_console.exe',
    [ValidateSet('forward', 'headless')][string]$Renderer = 'forward',
    [ValidateSet('full', 'menu-exit', 'combat-exit', 'rts-quality', 'selection-input', 'cursor-policy', 'edge-scroll', 'scene-review', 'battle-review', 'bank-review', 'visual-benchmark', 'tree-review', 'skill-click', 'building-vfx', 'foundation-blend', 'tactical-grid', 'tactical-subgrid')][string]$Scenario = 'full',
    [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$artifactRoot = Join-Path $projectRoot '.godot'
$null = New-Item -ItemType Directory -Force -Path $artifactRoot
$logPath = Join-Path $artifactRoot "check-$Renderer-$Scenario.log"
$startInfo = [System.Diagnostics.ProcessStartInfo]::new($GodotExecutable)
$startInfo.WorkingDirectory = $projectRoot
$startInfo.UseShellExecute = $false
$startInfo.CreateNoWindow = $true
$startInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
$startInfo.RedirectStandardOutput = $true
$startInfo.RedirectStandardError = $true
$arguments = @('--path', $projectRoot, '--script', 'res://tests/game_flow_smoke.gd', '--log-file', $logPath)
if ($Scenario -eq 'rts-quality') {
    $arguments = @('--path', $projectRoot, '--script', 'res://tests/rts_quality_smoke.gd', '--log-file', $logPath)
}
if ($Scenario -eq 'selection-input') {
    $arguments = @('--path', $projectRoot, '--script', 'res://tests/selection_input_smoke.gd', '--log-file', $logPath)
}
if ($Scenario -eq 'skill-click') {
    if ($Renderer -eq 'headless') { throw 'skill-click requires native rendering for viewport raycasting and mouse input' }
    $arguments = @('--path', $projectRoot, '--script', 'res://tests/skill_direct_click_smoke.gd', '--log-file', $logPath)
}
if ($Scenario -eq 'building-vfx') {
    if ($Renderer -eq 'headless') { throw 'building-vfx requires native rendering for 3D VFX and building raycasting' }
    $arguments = @('--path', $projectRoot, '--script', 'res://tests/building_and_spell_vfx_smoke.gd', '--log-file', $logPath)
}
if ($Scenario -eq 'foundation-blend') {
    if ($Renderer -eq 'headless') { throw 'foundation-blend requires native rendering for 3D Decal and building raycasting' }
    $arguments = @('--path', $projectRoot, '--script', 'res://tests/foundation_blending_smoke.gd', '--log-file', $logPath)
}
if ($Scenario -eq 'tactical-grid') {
    if ($Renderer -eq 'headless') { throw 'tactical-grid requires native rendering for 3D Decal and building raycasting' }
    $arguments = @('--path', $projectRoot, '--script', 'res://tests/tactical_grid_smoke.gd', '--log-file', $logPath)
}
if ($Scenario -eq 'tactical-subgrid') {
    if ($Renderer -eq 'headless') { throw 'tactical-subgrid requires native rendering for 3D Decal and building raycasting' }
    $arguments = @('--path', $projectRoot, '--script', 'res://tests/tactical_subgrid_smoke.gd', '--log-file', $logPath)
}
if ($Renderer -eq 'headless') { $arguments += '--headless' }
if ($Scenario -eq 'cursor-policy') {
    $arguments = @('--path', $projectRoot, '--script', 'res://tests/cursor_policy_smoke.gd', '--log-file', $logPath)
    if ($Renderer -eq 'headless') { $arguments += '--headless' }
}
$marker = 'FLOW_TEST_OK'
if ($Scenario -in @('scene-review', 'battle-review', 'bank-review', 'visual-benchmark')) {
    if ($Renderer -eq 'headless') { throw "$Scenario requires native rendering" }
    $script = if ($Scenario -eq 'visual-benchmark') { 'res://tests/visual_benchmark.gd' } else { 'res://tests/scene_layout_review.gd' }
    $arguments = @('--path', $projectRoot, '--script', $script, '--log-file', $logPath)
    $marker = if ($Scenario -eq 'visual-benchmark') { 'VISUAL_BENCHMARK_OK' } else { 'SCENE_REVIEW_OK' }
    if ($Scenario -eq 'battle-review') { $arguments += @('--', '--battle-sample') }
    if ($Scenario -eq 'bank-review') {
        $arguments += @('--', '--bank-only')
        $marker = 'BANK_CAPTURE_OK'
    }
}
if ($Scenario -eq 'tree-review') {
    if ($Renderer -eq 'headless') { throw 'tree-review requires native rendering' }
    $arguments = @('--path', $projectRoot, 'res://asset_lab/tree_comparison.tscn', '--log-file', $logPath, '--', '--review', '--quick')
    $marker = 'TREE_REVIEW_OK'
}
if ($Scenario -eq 'edge-scroll') {
    if ($Renderer -eq 'headless') { throw 'edge-scroll requires a native desktop window' }
    $arguments = @('--path', $projectRoot, '--script', 'res://tests/edge_scroll_smoke.gd', '--log-file', $logPath)
    $marker = 'EDGE_SCROLL_OK'
}
if ($Scenario -eq 'cursor-policy') { $marker = 'CURSOR_POLICY_OK' }
if ($Scenario -eq 'rts-quality') { $marker = 'RTS_QUALITY_OK' }
if ($Scenario -eq 'selection-input') { $marker = 'SELECTION_INPUT_OK' }
if ($Scenario -eq 'skill-click') { $marker = 'SKILL_DIRECT_CLICK_OK' }
if ($Scenario -eq 'building-vfx') { $marker = 'BUILDING_VFX_OK' }
if ($Scenario -eq 'foundation-blend') { $marker = 'FOUNDATION_BLEND_OK' }
if ($Scenario -eq 'tactical-grid') { $marker = 'TACTICAL_GRID_OK' }
if ($Scenario -eq 'tactical-subgrid') { $marker = 'TACTICAL_SUBGRID_OK' }
if ($Scenario -eq 'menu-exit') {
    $arguments += @('--', '--exit-from-menu')
    $marker = 'MENU_EXIT_OK'
} elseif ($Scenario -eq 'combat-exit') {
    $arguments += @('--', '--quit-in-combat')
    $marker = 'COMBAT_SHUTDOWN_OK'
}
foreach ($argument in $arguments) { $startInfo.ArgumentList.Add($argument) }
$process = [System.Diagnostics.Process]::new()
$process.StartInfo = $startInfo
try {
    $null = $process.Start()
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        $process.Kill($true)
        $process.WaitForExit()
        throw "Godot timed out after $TimeoutSeconds seconds ($logPath)"
    }
    $stdout.Result | Set-Content -LiteralPath "$logPath.stdout" -Encoding utf8
    $stderr.Result | Set-Content -LiteralPath "$logPath.stderr" -Encoding utf8
    $log = Get-Content -LiteralPath $logPath -Raw
    # Shutdown diagnostics may be emitted after Godot closes the log file.
    $diagnostics = $log + "`n" + $stdout.Result + "`n" + $stderr.Result
    $errors = @($diagnostics -split '\r?\n' | Where-Object { $_ -match '^(SCRIPT ERROR:|ERROR:|WARNING:)' } | Select-Object -Unique)
    if ($Renderer -eq 'headless') {
        # Godot's dummy renderer reports this for built-in sampler functions.
        # The Forward+ run must still be completely free of diagnostics.
        $errors = @($errors | Where-Object { $_ -notmatch '^ERROR: Condition "!actions\.custom_samplers' })
    }
    if ($process.ExitCode -ne 0 -or -not $log.Contains($marker) -or $errors.Count -gt 0) {
        $errors | Write-Output
        throw "Game checks failed: $Renderer / $Scenario ($logPath)"
    }
    Write-Output "PASS: $Renderer / $Scenario; process exited; no unexpected errors or leak warnings."
    Write-Output "Log: $logPath"
} finally {
    $process.Dispose()
}
