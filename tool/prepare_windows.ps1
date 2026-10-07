$ErrorActionPreference = 'Stop'
if (Test-Path 'windows/runner/main.cpp') { exit 0 }
# Generate only the native Windows runner in a temporary project. Never run
# flutterfire configure or alter the existing Android Firebase configuration.
$runnerTemp = Join-Path ([System.IO.Path]::GetTempPath()) ('gkii-runner-' + [Guid]::NewGuid())
try {
  flutter create --platforms=windows --project-name gereja_mobile --org com.puli --empty --no-pub $runnerTemp
  if ($LASTEXITCODE -ne 0) { throw 'Windows runner generation failed' }
  if (!(Test-Path 'windows')) { Copy-Item (Join-Path $runnerTemp 'windows') 'windows' -Recurse }
  $cmake = Get-Content 'windows/CMakeLists.txt' -Raw
  if (!$cmake.Contains('CMAKE_POLICY_VERSION_MINIMUM')) {
    Set-Content 'windows/CMakeLists.txt' ("set(CMAKE_POLICY_VERSION_MINIMUM 3.5)`n" + $cmake)
  }
  $entry = Get-Content 'windows/runner/main.cpp' -Raw
  Set-Content 'windows/runner/main.cpp' ($entry.Replace('L"gereja_mobile"', 'L"GKII Mobile"'))
} finally {
  if (Test-Path $runnerTemp) { Remove-Item $runnerTemp -Recurse -Force }
}
