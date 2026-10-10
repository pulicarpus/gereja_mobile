param([Parameter(Mandatory=$true)][string]$Executable)
$ErrorActionPreference = 'Stop'
$diagnostics = Join-Path (Get-Location) 'windows-startup-diagnostics'
$process = $null
$failure = $null
$report = @{ ready = $false; error = $null; exitCode = $null; cleanupError = $null }
try {
    New-Item -ItemType Directory -Path $diagnostics -Force | Out-Null
    $readyPath = Join-Path $env:RUNNER_TEMP ('gkii-ready-' + [Guid]::NewGuid() + '.txt')
    $env:GKII_SMOKE_READY_PATH = $readyPath
    $process = Start-Process -FilePath (Resolve-Path $Executable).Path -PassThru `
        -RedirectStandardOutput (Join-Path $diagnostics 'stdout.log') `
        -RedirectStandardError (Join-Path $diagnostics 'stderr.log')
    $deadline = (Get-Date).AddSeconds(25)
    while (!(Test-Path $readyPath) -and (Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 250
        $process.Refresh()
        if ($process.HasExited) { throw 'Windows app exited during startup' }
    }
    if (!(Test-Path $readyPath)) { throw 'First Flutter frame was not reached' }
    $process.Refresh()
    if ($process.HasExited) { throw 'Windows app exited before startup verification finished' }
    $report.ready = $true
    Write-Output 'Windows Firebase/SQLite initialization and first Flutter frame passed'
} catch {
    $failure = $_
    $report.error = $_.Exception.Message
    $report.scriptStack = $_.ScriptStackTrace
    if ($null -ne $process) {
        try {
            $process.Refresh()
            if ($process.HasExited) { $report.exitCode = $process.ExitCode }
        } catch { $report.processInspectionError = $_.Exception.Message }
    }
    $detail = $report.error.Replace('%', '%25').Replace("`r", '%0D').Replace("`n", '%0A')
    Write-Output "::error::Startup check: $detail (exit $($report.exitCode))"
    foreach ($name in @('stdout.log', 'stderr.log')) {
        $path = Join-Path $diagnostics $name
        if (Test-Path $path) { Get-Content $path -Tail 30 -ErrorAction SilentlyContinue }
    }
} finally {
    # Cleanup must not hide the original exception or fail a successful check
    # because the process exits between inspection and Stop-Process.
    if ($null -ne $process) {
        try {
            $process.Refresh()
            if (!$process.HasExited) { Stop-Process -Id $process.Id -ErrorAction SilentlyContinue }
        } catch { $report.cleanupError = $_.Exception.Message }
    }
    Remove-Item Env:GKII_SMOKE_READY_PATH -ErrorAction SilentlyContinue
    if ($readyPath -and (Test-Path $readyPath)) { Remove-Item $readyPath -ErrorAction SilentlyContinue }
    if (Test-Path $diagnostics) {
        $report | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $diagnostics 'result.json')
    }
}
if ($null -ne $failure) { throw $failure }
