<#
    Brings the whole stack down.

        powershell -ExecutionPolicy Bypass -File stop.ps1
#>

$nginx = 'C:\nginx'

& "$nginx\nginx.exe" -p $nginx -s stop 2>$null | Out-Null
Start-Sleep -Seconds 1
Get-Process nginx -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

foreach ($port in 80, 8765, 8766) {
    Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue |
        Select-Object -Expand OwningProcess -Unique |
        ForEach-Object { Stop-Process -Id $_ -Force -ErrorAction SilentlyContinue }
}

Start-Sleep -Seconds 1
$left = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
    Where-Object { $_.LocalPort -in 80, 8765, 8766 }

if ($left) {
    Write-Host '  Still listening:' -ForegroundColor Red
    $left | Select-Object LocalPort, OwningProcess | Format-Table -AutoSize
} else {
    Write-Host '  NiyuktiAI stopped.' -ForegroundColor Green
}
