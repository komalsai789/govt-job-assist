<#
    Starts the whole of NiyuktiAI and prints the address to share.

        powershell -ExecutionPolicy Bypass -File start.ps1

    Three processes come up: the extraction backend, the automation
    engine, and nginx in front of all three on port 80. Each is launched through
    Win32_Process.Create rather than as a child of this shell - a child dies
    with its parent's job object, and closing the window would take the whole
    stack down with it.

    Logs land in .run\. Run stop.ps1 to bring everything down.
#>

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$log  = Join-Path $root '.run'
$nginx = 'C:\nginx'
New-Item -ItemType Directory -Force -Path $log | Out-Null

function Start-Detached([string]$Name, [string]$Exe, [string]$Arguments, [string]$WorkDir, [hashtable]$Env = @{}) {
    $out = Join-Path $log "$Name.log"
    # Win32_Process.Create runs under the WMI host, not as our child, so the
    # service never sees this shell's environment: variables go on the command
    # line instead ("set X=1&&" — no space before &&, or the value gets one).
    $prefix = ''
    foreach ($entry in $Env.GetEnumerator()) { $prefix += "set $($entry.Key)=$($entry.Value)&& " }
    $line = "cmd.exe /c `"$prefix`"$Exe`" $Arguments > `"$out`" 2>&1`""

    # CREATE_NO_WINDOW (0x08000000) gives the service its own hidden console, and
    # CREATE_NEW_PROCESS_GROUP (0x200) puts it outside ours - so closing the
    # window that started the stack cannot deliver Ctrl+C to it, which is what
    # kept killing every service at once.
    #
    # Not DETACHED_PROCESS: with no console at all, cmd's redirection silently
    # writes nothing, and every log in .run\ stays empty just when you need it.
    $startup = New-CimInstance -ClassName Win32_ProcessStartup -ClientOnly `
        -Property @{ CreateFlags = [uint32](0x08000000 -bor 0x200) }

    $r = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{
        CommandLine               = $line
        CurrentDirectory          = $WorkDir
        ProcessStartupInformation = [CimInstance]$startup
    }
    if ($r.ReturnValue -ne 0) { throw "$Name failed to start (Win32_Process returned $($r.ReturnValue))" }
    return $r.ProcessId
}

function Stop-Port([int]$Port) {
    Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue |
        Select-Object -Expand OwningProcess -Unique |
        ForEach-Object { Stop-Process -Id $_ -Force -ErrorAction SilentlyContinue }
}

function Wait-Until([string]$Name, [string]$Url, [int]$Seconds = 90) {
    $deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $deadline) {
        try { Invoke-WebRequest $Url -UseBasicParsing -TimeoutSec 5 | Out-Null; return $true }
        catch { Start-Sleep -Milliseconds 700 }
    }
    Write-Host "  $Name did not answer within $Seconds s - see $log\$Name.log" -ForegroundColor Red
    return $false
}

Write-Host ''
Write-Host 'Stopping anything already on these ports...' -ForegroundColor DarkGray
80, 8765, 8766 | ForEach-Object { Stop-Port $_ }
# nginx writes to stderr when there is no pid file to read - i.e. when it was
# not running, which is the normal case here. Under ErrorActionPreference =
# Stop that complaint is terminating, and it killed this script before a
# single service started. The child scope lowers the preference for this call.
& { $ErrorActionPreference = 'Continue'; & "$nginx\nginx.exe" -p $nginx -s stop *>$null }
Start-Sleep -Seconds 2

# The engine is TypeScript; compile before running. Bundlers inject helpers that
# break page.evaluate, so this is tsc and stays tsc.
Write-Host 'Building the automation engine...' -ForegroundColor DarkGray
Push-Location (Join-Path $root 'runner')
& npm run build 2>&1 | Out-Null
Pop-Location

Write-Host ''
Write-Host 'Starting services...' -ForegroundColor Cyan
$node = (Get-Command node).Source

Start-Detached 'backend' "$root\backend\.venv\Scripts\python.exe" `
    '-m uvicorn app.main:app --host 127.0.0.1 --port 8765' "$root\backend" | Out-Null
# RUNNER_DEMO=1 keeps the runner's own practice portal available in Live
# Working ("Demo Admission Portal") — a full application run that never
# leaves this computer, for trying the flow or showing it.
Start-Detached 'runner' $node 'dist\server.js' "$root\runner" @{ RUNNER_DEMO = '1' } | Out-Null
# There is no website process any more. The front end is static HTML in web\
# and nginx serves it straight off disk — one less thing to start, and one
# less thing that can be down while the pages themselves are fine.

$ok = $true
$ok = (Wait-Until 'backend' 'http://127.0.0.1:8765/openapi.json') -and $ok
$ok = (Wait-Until 'runner'  'http://127.0.0.1:8766/health')       -and $ok

Write-Host 'Starting nginx...' -ForegroundColor DarkGray
Start-Process -FilePath "$nginx\nginx.exe" `
    -ArgumentList '-p', $nginx, '-c', 'conf\niyuktiai.conf' `
    -WorkingDirectory $nginx -WindowStyle Hidden
$ok = (Wait-Until 'nginx' 'http://localhost/' 30) -and $ok

# The address to hand round the room - whichever adapter actually has a route out.
$lan = Get-NetIPConfiguration |
    Where-Object { $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq 'Up' } |
    Select-Object -First 1 -Expand IPv4Address |
    Select-Object -First 1 -Expand IPAddress

Write-Host ''
if ($ok) {
    Write-Host '  NiyuktiAI is running' -ForegroundColor Green
    Write-Host ''
    Write-Host "  On this laptop     http://localhost/"
    if ($lan) { Write-Host "  On the same wifi   http://$lan/" }
    Write-Host ''
    Write-Host '  Logs   .run\*.log        Stop   powershell -File stop.ps1' -ForegroundColor DarkGray
} else {
    Write-Host '  Something did not come up - check .run\*.log' -ForegroundColor Red
}
Write-Host ''
