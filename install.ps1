# Installs the command `vaudit` for the Vaudit internal tool APIs (Windows).
#
#   irm https://raw.githubusercontent.com/blokid/vaudit-cli/main/install.ps1 | iex
#
# What it does, and nothing else:
#   1. Downloads kubelogin (github.com/int128/kubelogin) at a FIXED version and
#      stops unless the file matches the SHA-256 below.
#   2. Puts kubelogin and the small `vaudit` command in
#      %LOCALAPPDATA%\vaudit\bin, and adds that folder to your user PATH.
#      No administrator rights.
#   3. Runs `vaudit login` once.
#
# It holds no secret: the Keycloak address and the client id are public.
# To move to a new kubelogin version, change $KubeloginVersion and the sum,
# copied from the .sha256 file of that GitHub release.
$ErrorActionPreference = 'Stop'

$KubeloginVersion = 'v1.36.4'
$Sha256 = 'a68be8ff153a7d3df1de19f272a9879164f55b8bb39298859d0e20c9e2c414ad'  # windows_amd64

$VauditHome = if ($env:VAUDIT_HOME) { $env:VAUDIT_HOME } else { Join-Path $env:LOCALAPPDATA 'vaudit' }
$Bin = Join-Path $VauditHome 'bin'

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("vaudit-" + [guid]::NewGuid())
New-Item -ItemType Directory -Force $tmp | Out-Null
try {
  Write-Host "Downloading kubelogin $KubeloginVersion (windows/amd64)..."
  $zip = Join-Path $tmp 'kubelogin.zip'
  Invoke-WebRequest -UseBasicParsing -OutFile $zip `
    "https://github.com/int128/kubelogin/releases/download/$KubeloginVersion/kubelogin_windows_amd64.zip"

  $got = (Get-FileHash -Algorithm SHA256 $zip).Hash.ToLower()
  if ($got -ne $Sha256) { throw "The download does not match the expected SHA-256. Nothing was installed." }

  Expand-Archive -Force $zip $tmp
  New-Item -ItemType Directory -Force $Bin | Out-Null
  Copy-Item -Force (Join-Path $tmp 'kubelogin.exe') (Join-Path $Bin 'kubelogin.exe')
} finally {
  Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

# The command itself. A .cmd file runs under every PowerShell execution
# policy, so nobody has to change a security setting.
$vaudit = @'
@echo off
setlocal
set "KL=%~dp0kubelogin.exe"
set "CACHE=%~dp0..\cache"
set ARGS=get-token --oidc-issuer-url=https://id.internal.vaudit.com/realms/vaudit --oidc-client-id=internal-cli --grant-type=device-code --oidc-extra-scope=email --oidc-extra-scope=offline_access --oidc-use-access-token --token-cache-storage=keyring --token-cache-dir="%CACHE%"
if /i "%~1"=="login" (
  "%KL%" %ARGS% >nul || exit /b 1
  echo Signed in for 8 hours.
  exit /b 0
)
if /i "%~1"=="token" (
  "%KL%" %ARGS% | powershell -NoProfile -Command "($input | Out-String | ConvertFrom-Json).status.token"
  exit /b %ERRORLEVEL%
)
if /i "%~1"=="signout" goto logout
if /i "%~1"=="logout" goto logout
goto usage
:logout
set "OUT=%TEMP%\vaudit-logout-%RANDOM%.txt"
"%KL%" clean --token-cache-dir="%CACHE%" >"%OUT%" 2>&1
if errorlevel 1 (
  type "%OUT%" 1>&2
  del "%OUT%" >nul 2>&1
  echo Sign-out failed. The sign-in may still be on this computer. 1>&2
  exit /b 1
)
del "%OUT%" >nul 2>&1
echo Signed out.
exit /b 0
:usage
echo usage: vaudit login ^| token ^| logout (or signout) 1>&2
echo   login   sign in with Google (once a day) 1>&2
echo   token   print a token for a script 1>&2
echo   logout  forget the sign-in on this computer (same as: signout) 1>&2
exit /b 2
'@
Set-Content -Encoding ASCII -Path (Join-Path $Bin 'vaudit.cmd') -Value $vaudit

# Add the folder to the user PATH once, and to this window now.
if (-not $env:VAUDIT_NO_PATH) {
  $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
  if (-not (($userPath -split ';') -contains $Bin)) {
    $newPath = (@($userPath, $Bin) | Where-Object { $_ }) -join ';'
    [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
  }
}
$env:Path = "$Bin;$env:Path"

Write-Host "Installed: $(Join-Path $Bin 'vaudit.cmd')"
if (-not $env:VAUDIT_NO_LOGIN) {
  Write-Host 'Signing in. Open the link below, sign in with Google, and approve the code.'
  & (Join-Path $Bin 'vaudit.cmd') login
}
Write-Host 'Done. In a new window use: vaudit login, vaudit token'
