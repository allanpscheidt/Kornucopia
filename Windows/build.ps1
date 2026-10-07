param([ValidateSet('win-x64','win-arm64')][string]$Runtime = 'win-x64', [switch]$Test)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if ($Test) {
    dotnet run --project (Join-Path $PSScriptRoot 'Tests/Kornucopia.Core.Tests.csproj') -c Release
    if ($LASTEXITCODE -ne 0) { throw 'Core tests failed.' }
}
$outputDirectory = Join-Path $projectRoot "dist/windows/$Runtime"
dotnet publish (Join-Path $PSScriptRoot 'Kornucopia.Windows.csproj') -c Release -r $Runtime --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -p:DebugType=None -p:DebugSymbols=false -o $outputDirectory
if ($LASTEXITCODE -ne 0) { throw 'Windows publish failed.' }
Write-Output "Portable application: $outputDirectory"
