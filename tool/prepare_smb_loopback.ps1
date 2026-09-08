# Build a Windows test-only copy of the vendored library. Never changes or
# replaces the OHOS library. Requires existing MinGW gcc/make and CMake.
param([string]$GccRoot = 'C:\mingw\bin')
$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$staged = Join-Path $project 'build\smb-test-source'
$build = Join-Path $project 'build\smb-test-native'
if (-not (Test-Path -LiteralPath $staged)) {
    Copy-Item -LiteralPath (Join-Path $project 'libsmb2') -Destination $staged -Recurse
}
# Minimal MinGW portability corrections in the disposable test copy only.
$cmakePath = Join-Path $staged 'CMakeLists.txt'
(Get-Content -LiteralPath $cmakePath -Raw).Replace('ws2_32.lib', 'ws2_32') | Set-Content -LiteralPath $cmakePath
$compatPath = Join-Path $staged 'lib\compat.h'
$compat = Get-Content -LiteralPath $compatPath -Raw
$compat = $compat.Replace('int gethostname(char* name, size_t len);', '')
$compat = $compat -replace '(?m)^inline int (writev|readv)\(', 'static inline int $1('
$compat | Set-Content -LiteralPath $compatPath
'/* MinGW stdio.h provides asprintf and vasprintf. */' | Set-Content -LiteralPath (Join-Path $staged 'include\asprintf.h')
$socketPath = Join-Path $staged 'lib\socket.c'
(Get-Content -LiteralPath $socketPath -Raw).Replace('#ifndef _MSC_VER', '#if !defined(_MSC_VER) && !defined(__MINGW32__)') | Set-Content -LiteralPath $socketPath
& cmake -S $staged -B $build -G 'MinGW Makefiles' "-DCMAKE_MAKE_PROGRAM=$GccRoot/mingw32-make.exe" "-DCMAKE_C_COMPILER=$GccRoot/gcc.exe" -DCMAKE_C_FLAGS=-D_WINDOWS -DHAVE_SOCKADDR_STORAGE=1 -DHAVE_LINGER=1 -DENABLE_LIBKRB5=OFF -DENABLE_GSSAPI=OFF -DENABLE_EXAMPLES=OFF -DBUILD_SHARED_LIBS=ON
if ($LASTEXITCODE -ne 0) { throw 'SMB test CMake configuration failed' }
& cmake --build $build -j 4
if ($LASTEXITCODE -ne 0) { throw 'SMB test library build failed' }
& (Join-Path $GccRoot 'gcc.exe') -shared -I (Join-Path $project 'libsmb2\include') (Join-Path $project 'test\native\smb_enum_fixture.c') -o (Join-Path $project 'build\smb_enum_fixture.dll')
if ($LASTEXITCODE -ne 0) { throw 'SMB ABI fixture build failed' }
Write-Host 'SMB loopback and ABI test libraries ready. No OHOS binaries were changed.'
