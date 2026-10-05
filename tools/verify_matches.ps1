# Runs one full bot match in every arena headless and asserts the whole loop
# completed: no script errors, a winner resolved, and the reward write landed in
# the saved profile.
#
#   powershell -ExecutionPolicy Bypass -File devprobe/verify_matches.ps1

$ErrorActionPreference = 'Continue'
$profilePath = Join-Path $env:APPDATA 'Godot\app_userdata\Book Bash\book_bash_profile.json'
$arenas = @('SkyLibrary', 'ClassroomChaos', 'AncientRuins', 'TechTower', 'CandyIsland', 'VolcanoCore')
$failures = @()

Remove-Item $profilePath -ErrorAction SilentlyContinue
Remove-Item "$profilePath.bak" -ErrorAction SilentlyContinue

foreach ($arena in $arenas) {
    $before = 0
    if (Test-Path $profilePath) {
        $before = (Get-Content $profilePath -Raw | ConvertFrom-Json).stats.matches
    }

    Write-Host "=== $arena ==="
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $output = & devtools\Godot\godot.cmd --headless --path . "res://scenes/arenas/$arena.tscn" `
        --fixed-fps 60 --quit-after 11000 2>&1
    $sw.Stop()

    $scriptErrors = $output | Select-String -Pattern 'SCRIPT ERROR|Parse Error|Invalid call|Invalid get|Nonexistent|Cannot call'
    if ($scriptErrors) {
        $failures += "$arena : script errors"
        $scriptErrors | Select-Object -First 8 | ForEach-Object { Write-Host "   ! $_" }
    }

    if (-not (Test-Path $profilePath)) {
        $failures += "$arena : no profile written"
        Write-Host '   ! profile file missing'
        continue
    }
    $saved = Get-Content $profilePath -Raw | ConvertFrom-Json
    $after = $saved.stats.matches
    if ($after -le $before) {
        $failures += "$arena : match never resolved (matches stayed at $after)"
        Write-Host "   ! matches did not increase ($before -> $after)"
    }
    else {
        Write-Host ("   ok  {0:n1}s real  matches={1}  wins={2}  kos={3}  coins={4}  xp={5}" -f `
            $sw.Elapsed.TotalSeconds, $after, $saved.stats.wins, $saved.stats.knockouts, `
            $saved.coins, $saved.level_xp)
    }
}

Write-Host ''
if ($failures.Count -eq 0) {
    Write-Host 'ALL ARENAS PASSED'
    exit 0
}
Write-Host 'FAILURES:'
$failures | ForEach-Object { Write-Host "  - $_" }
exit 1
