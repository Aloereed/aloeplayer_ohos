param()
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$fixtureRoot = Join-Path $projectRoot 'build/media-server-fixtures'
$binary = Join-Path $fixtureRoot 'jellyfin-12-bin/jellyfin/jellyfin.exe'
$runtime = Join-Path $fixtureRoot 'jellyfin-12-runtime'
$stateFile = Join-Path $runtime 'fixture.json'
if (Test-Path $stateFile) {
    $oldState = Get-Content $stateFile -Raw | ConvertFrom-Json
    $oldProcess = Get-Process -Id $oldState.processId -ErrorAction SilentlyContinue
    if ($oldProcess -and $oldProcess.Path -eq $binary) {
        throw 'Fixture is already running. Inspect its recorded process instead of starting another.'
    }
}
if (-not (Test-Path -LiteralPath $binary)) { throw 'Extract the official Jellyfin 12.0 Windows archive first.' }
$listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
$listener.Start()
$fixturePort = $listener.LocalEndpoint.Port
$listener.Stop()
foreach ($part in @('data','config','cache','logs')) {
    New-Item -ItemType Directory -Path (Join-Path $runtime $part) -Force | Out-Null
}
$networkXml = @"
<?xml version="1.0" encoding="utf-8"?>
<NetworkConfiguration>
  <BaseUrl>/fixture</BaseUrl>
  <InternalHttpPort>$fixturePort</InternalHttpPort>
  <PublicHttpPort>$fixturePort</PublicHttpPort>
  <EnableHttps>false</EnableHttps>
  <AutoDiscovery>false</AutoDiscovery>
  <EnableUPnP>false</EnableUPnP>
  <EnableIPv4>true</EnableIPv4>
  <EnableIPv6>false</EnableIPv6>
  <EnableRemoteAccess>false</EnableRemoteAccess>
  <LocalNetworkSubnets><string>127.0.0.0/8</string></LocalNetworkSubnets>
  <LocalNetworkAddresses><string>127.0.0.1</string></LocalNetworkAddresses>
</NetworkConfiguration>
"@
[IO.File]::WriteAllText((Join-Path $runtime 'config/network.xml'), $networkXml)
$arguments = @('--datadir', (Join-Path $runtime 'data'), '--configdir', (Join-Path $runtime 'config'),
    '--cachedir', (Join-Path $runtime 'cache'), '--logdir', (Join-Path $runtime 'logs'),
    '--nowebclient', '--nonetchange', '--service', '--ffmpeg', (Join-Path (Split-Path $binary) 'ffmpeg.exe'))
$fixtureProcess = Start-Process -FilePath $binary -ArgumentList $arguments -WorkingDirectory (Split-Path $binary) `
    -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $runtime 'stdout.log') `
    -RedirectStandardError (Join-Path $runtime 'stderr.log')
$state = @{processId=$fixtureProcess.Id; port=$fixturePort; url="http://127.0.0.1:$fixturePort/fixture";
    binary=$binary; runtime=$runtime; started=(Get-Date).ToString('o');
    archiveSource='https://repo.jellyfin.org/files/server/windows/latest-stable/amd64/jellyfin_12.0-amd64.zip';
    archiveSha256='22A16178160C03F8C9D4BF4350449551B2F9901F708F41A632B2957AD5AE4A57'}
$state | ConvertTo-Json | Set-Content -LiteralPath $stateFile -Encoding utf8
$state | ConvertTo-Json
