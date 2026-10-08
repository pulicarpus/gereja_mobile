param([Parameter(Mandatory = $true)][string]$Executable)
$ErrorActionPreference = 'Stop'
$resolved = (Resolve-Path $Executable).Path
function Run-NativeCase([string]$mode, [int]$expected, [string]$phase) {
  $start = [System.Diagnostics.ProcessStartInfo]::new()
  $start.FileName = $resolved
  $start.Arguments = $mode
  $start.UseShellExecute = $false
  $start.RedirectStandardOutput = $true
  $start.RedirectStandardError = $true
  $process = [System.Diagnostics.Process]::new()
  $process.StartInfo = $start
  try {
    if (!$process.Start()) { throw 'Native process did not start' }
    $outTask = $process.StandardOutput.ReadToEndAsync()
    $errTask = $process.StandardError.ReadToEndAsync()
    if (!$process.WaitForExit(40000)) {
      $process.Kill()
      throw "Native case timed out: $mode"
    }
    $output = $outTask.GetAwaiter().GetResult() + $errTask.GetAwaiter().GetResult()
    Write-Output $output
    if ($process.ExitCode -ne $expected -or !$output.Contains($phase)) {
      $detail = "Native case $mode exited $($process.ExitCode), expected $expected. $output"
      $detail = $detail.Replace('%', '%25').Replace("`r", '%0D').Replace("`n", '%0A')
      Write-Output "::error::$detail"
      throw "Native case failed: $mode"
    }
    Write-Output "Passed: $mode (exit $expected)"
  } finally { $process.Dispose() }
}
# Match the C++ exception seen in the supplied dump, not an arbitrary nonzero
# exit. Verify the deliberately unsafe call separately from the guarded call.
Run-NativeCase '--unsafe-settings' -529697949 'Phase: reproduce original exception'
Run-NativeCase '--guarded' 0 'Repeated identical settings passed without native exception'
Run-NativeCase '--late-change' -529697949 'Phase: reject changed settings'
