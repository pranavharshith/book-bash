# Two-process ENet verification.
#
# Starts a headless host with `--book-bash-server --book-bash-autostart`, joins it
# with a second headless client via `--book-bash-connect=`, and asserts that the
# lobby registered both peers, the match started on both, and neither process
# logged a script or RPC error.
#
#   powershell -ExecutionPolicy Bypass -File devprobe/verify_network.ps1

$ErrorActionPreference = 'Continue'
$logDir = Join-Path $env:TEMP 'bookbash_net'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$hostLog = Join-Path $logDir 'host.log'
$clientLog = Join-Path $logDir 'client.log'
Remove-Item $hostLog, $clientLog -ErrorAction SilentlyContinue

$godot = Resolve-Path 'devtools\Godot\Godot_v4.7-stable_win64_console.exe'
$project = (Get-Location).Path

# Deliberately no --fixed-fps here. It decouples game time from the wall clock, so
# the processes burned through their frame budget in a few real seconds and ENet
# never got time to complete a handshake.
Write-Host 'starting host...'
$hostProc = Start-Process -FilePath $godot -PassThru -NoNewWindow -RedirectStandardOutput $hostLog `
    -ArgumentList @('--headless', '--path', $project, '--quit-after', '4200',
        '--', '--book-bash-server', '--book-bash-autostart')
Start-Sleep -Seconds 4

Write-Host 'starting client...'
$clientProc = Start-Process -FilePath $godot -PassThru -NoNewWindow -RedirectStandardOutput $clientLog `
    -ArgumentList @('--headless', '--path', $project, '--quit-after', '3300',
        '--', '--book-bash-connect=127.0.0.1')

$hostProc.WaitForExit(180000) | Out-Null
$clientProc.WaitForExit(60000) | Out-Null
foreach ($p in @($hostProc, $clientProc)) {
    if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
}

$hostText = if (Test-Path $hostLog) { Get-Content $hostLog -Raw } else { '' }
$clientText = if (Test-Path $clientLog) { Get-Content $clientLog -Raw } else { '' }

$failures = @()
function Assert-Contains($text, $pattern, $label) {
    if ($text -notmatch $pattern) { return "missing: $label" }
    return $null
}

# ASCII-only fragments: the status strings contain em-dashes, and the redirected
# log is not read back as UTF-8, so matching around them fails spuriously.
$checks = @(
    (Assert-Contains $hostText 'Hosting up to 6 players' 'host opened a server'),
    (Assert-Contains $hostText 'Lobby ready' 'host registered the client'),
    (Assert-Contains $hostText '2/6 human player' 'host saw two humans'),
    (Assert-Contains $hostText 'Starting match' 'host started the match'),
    (Assert-Contains $clientText 'waiting for host' 'client connected'),
    (Assert-Contains $clientText '2/6 human player' 'client saw the synced lobby'),
    (Assert-Contains $clientText 'Starting match' 'client entered the match')
)
$failures += $checks | Where-Object { $_ }

foreach ($pair in @(@('host', $hostText), @('client', $clientText))) {
    $errs = [regex]::Matches($pair[1], '(?m)^.*(SCRIPT ERROR|Parse Error|Invalid call|Nonexistent function|rpc.*[Ff]ailed|Cannot call).*$')
    if ($errs.Count -gt 0) {
        $failures += "$($pair[0]) : $($errs.Count) error line(s)"
        $errs | Select-Object -First 6 | ForEach-Object { Write-Host "   ! [$($pair[0])] $($_.Value.Trim())" }
    }
}

Write-Host ''
Write-Host '--- host log (network lines) ---'
$hostText -split "`r?`n" | Select-String -Pattern '\[Network\]' | Select-Object -First 12 | ForEach-Object { Write-Host "  $_" }
Write-Host '--- client log (network lines) ---'
$clientText -split "`r?`n" | Select-String -Pattern '\[Network\]' | Select-Object -First 12 | ForEach-Object { Write-Host "  $_" }

Write-Host ''
if ($failures.Count -eq 0) {
    Write-Host 'NETWORK VERIFICATION PASSED'
    exit 0
}
Write-Host 'FAILURES:'
$failures | ForEach-Object { Write-Host "  - $_" }
exit 1
