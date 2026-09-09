$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$fixtureRoot = Join-Path $projectRoot 'build/media-server-fixtures'
$binary = Join-Path $fixtureRoot 'emby-4.10-bin/system/EmbyServer.exe'
$runtime = Join-Path $fixtureRoot 'emby-4.10-runtime'
$stateFile = Join-Path $runtime 'fixture.json'
if (Test-Path $stateFile) {
    $previous = Get-Content $stateFile -Raw | ConvertFrom-Json
    $previousProcess = Get-Process -Id $previous.processId -ErrorAction SilentlyContinue
    if ($previousProcess -and $previousProcess.Path -eq $binary) { throw 'Fixture is already running.' }
}
if (-not (Test-Path $binary)) { throw 'Extract the official Emby Windows archive first.' }
$blockingRules = @(Get-NetFirewallApplicationFilter -Program $binary | Get-NetFirewallRule |
    Where-Object { $_.Action -eq 'Block' -and $_.Direction -eq 'Inbound' -and $_.Enabled -eq 'True' })
if ($blockingRules.Count -lt 2) { throw 'Fixture requires its existing TCP/UDP inbound block rules; do not expose this server to the LAN.' }
# This portable version ignores the legacy dlna.xml switch. Keep its optional
# discovery plugin outside both plugin search paths in our fixture only.
$disabledPlugins = Join-Path $fixtureRoot 'disabled-plugins'
New-Item -ItemType Directory -Path $disabledPlugins -Force | Out-Null
foreach ($plugin in @(
    @{source=(Join-Path $fixtureRoot 'emby-4.10-bin/system/plugins/Emby.Dlna.dll');name='system-Emby.Dlna.dll'},
    @{source=(Join-Path $runtime 'plugins/Emby.Dlna.dll');name='runtime-Emby.Dlna.dll'}
)) {
    $sourcePath = [IO.Path]::GetFullPath($plugin.source)
    $destinationPath = [IO.Path]::GetFullPath((Join-Path $disabledPlugins $plugin.name))
    $allowedPrefix = [IO.Path]::GetFullPath($fixtureRoot).TrimEnd('\') + '\'
    if (-not $sourcePath.StartsWith($allowedPrefix, [StringComparison]::OrdinalIgnoreCase) -or
        -not $destinationPath.StartsWith($allowedPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Plugin path escaped fixture.' }
    if (Test-Path -LiteralPath $sourcePath) {
        if (Test-Path -LiteralPath $destinationPath) { throw 'Disabled plugin backup already exists; inspect before replacing it.' }
        Move-Item -LiteralPath $sourcePath -Destination $destinationPath
    }
}
$listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
$listener.Start()
$fixturePort = $listener.LocalEndpoint.Port
$listener.Stop()
if (Test-Path (Join-Path $runtime 'config/system.xml')) {
    [xml]$existingConfig = Get-Content (Join-Path $runtime 'config/system.xml')
    $fixturePort = [int]$existingConfig.ServerConfiguration.HttpServerPortNumber
}
New-Item -ItemType Directory -Path (Join-Path $runtime 'config') -Force | Out-Null
$config = @"
<?xml version="1.0" encoding="utf-8"?>
<ServerConfiguration>
  <HttpServerPortNumber>$fixturePort</HttpServerPortNumber>
  <PublicPort>$fixturePort</PublicPort>
  <EnableHttps>false</EnableHttps>
  <EnableUPnP>false</EnableUPnP>
  <EnableAutomaticPortMapping>false</EnableAutomaticPortMapping>
  <EnableRemoteAccess>false</EnableRemoteAccess>
  <EnableAutoUpdate>false</EnableAutoUpdate>
  <AutoRunWebApp>false</AutoRunWebApp>
  <LocalNetworkAddresses><string>127.0.0.1</string></LocalNetworkAddresses>
  <LocalNetworkSubnets><string>127.0.0.0/8</string></LocalNetworkSubnets>
</ServerConfiguration>
"@
if (-not (Test-Path (Join-Path $runtime 'config/system.xml'))) {
    [IO.File]::WriteAllText((Join-Path $runtime 'config/system.xml'), $config)
}
[IO.File]::WriteAllText((Join-Path $runtime 'config/dlna.xml'), '<DlnaOptions><EnablePlayTo>false</EnablePlayTo><EnableServer>false</EnableServer><EnableDebugLog>false</EnableDebugLog></DlnaOptions>')
$fixtureProcess = Start-Process -FilePath $binary -ArgumentList @('-programdata', $runtime, '-noautorunwebapp', '-nolocalportconfig', '-service', '-nointerface') `
    -WorkingDirectory (Split-Path $binary) -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput (Join-Path $runtime 'stdout.log') -RedirectStandardError (Join-Path $runtime 'stderr.log')
$state = @{processId=$fixtureProcess.Id;port=$fixturePort;url="http://127.0.0.1:$fixturePort/emby";
    binary=$binary;runtime=$runtime;started=(Get-Date).ToString('o');
    archiveSource='https://github.com/MediaBrowser/Emby.Releases/releases/download/4.10.0.40/embyserver-win-x64-4.10.0.40.7z';
    archiveSha256='974F595F536A442DE28145337818E36423611C5F00910C5ABD1488ECB4DB3B32'}
$state | ConvertTo-Json | Set-Content $stateFile -Encoding utf8
$state | ConvertTo-Json
