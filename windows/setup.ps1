<#
.SYNOPSIS
  Pharmacolibrary dev environment on Windows 11 in WSL2 - the Windows counterpart of `vagrant up`.

.DESCRIPTION
  1. Checks Windows 11, Git for Windows and WSL (installs WSL if missing; then a reboot is needed).
  2. Copies wslconfig to %USERPROFILE%\.wslconfig (memory limits for 8 GB machines).
  3. Copies Ubuntu-24.04.user-data to %USERPROFILE%\.cloud-init\ with the Linux user name.
  4. Installs the Ubuntu-24.04 distro; cloud-init creates the user and turns systemd on.
  5. Puts an SSH key that GitHub accepts into the Linux user's ~/.ssh.
  6. Runs ..\bootstrap-dbs.sh in the distro as root: repos, Python venv, Docker Engine, GROBID,
     the Zenodo knowledge base in ~/knowledgebase (set in pharmacolibrary.local.json).

  Every step is skipped when already done, so running it again is safe (as `vagrant provision`).
  Remove everything with:  wsl --unregister Ubuntu-24.04   (deletes the distro and all work in it)

.PARAMETER LinuxUser
  Linux user name in the distro. Default: the Windows user name, lower-cased.
.PARAMETER Distro
  WSL distro name. Default: Ubuntu-24.04.
.PARAMETER WithOmc
  Also pull the OpenModelica Docker image and set PK_OMC_DOCKER (several GB of disk).
.PARAMETER WithWasm
  Also clone Bodylight.js-FMU-Compiler (browser simulator builds, export.fmu --wasm).
.PARAMETER WithDemoCorpus
  Unpack the Zenodo research dataset and the full-text corpus for the ddd and dku panel drugs only
  (12 drugs, about 0.7 GB on disk, about 1.1 GB read from Zenodo). Not with -WithCorpus.
.PARAMETER WithCorpus
  Also unpack the redistributable Zenodo full-text corpus (about 43 GB of disk).
.PARAMETER WithNcCorpus
  Also unpack the non-commercial Zenodo corpus (about 20 GB; its licence terms apply).
.PARAMETER NoKnowledgebase
  Skip the Zenodo knowledge base (the research dataset is unpacked into ~/knowledgebase by default).
.PARAMETER NoCopySshKey
  Do not copy the Windows SSH key (%USERPROFILE%\.ssh\id_ed25519 or id_rsa) into WSL;
  generate a new key in WSL instead.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File windows\setup.ps1
  powershell -ExecutionPolicy Bypass -File windows\setup.ps1 -WithOmc -WithWasm
#>
[CmdletBinding()]
param(
  [string]$LinuxUser = ($env:USERNAME.ToLower() -replace '[^a-z0-9_-]', ''),
  [string]$Distro = 'Ubuntu-24.04',
  [switch]$WithOmc,
  [switch]$WithWasm,
  [switch]$WithDemoCorpus,
  [switch]$WithCorpus,
  [switch]$WithNcCorpus,
  [switch]$NoKnowledgebase,
  [switch]$NoCopySshKey
)
$ErrorActionPreference = 'Stop'
# wsl.exe writes UTF-16 by default; this makes its output plain text PowerShell can compare
$env:WSL_UTF8 = '1'
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoDir = Split-Path -Parent $Here

function Step($msg) { Write-Host "`n== $msg" -ForegroundColor Cyan }
function Fail($msg) { Write-Host "ERROR: $msg" -ForegroundColor Red; exit 1 }
# Run a command in the distro; -Root runs it as root. Its output goes to the console, so the
# function returns only the exit code ($LASTEXITCODE holds it too).
function InWsl([string]$cmd, [switch]$Root) {
  $u = if ($Root) { 'root' } else { $LinuxUser }
  & wsl.exe -d $Distro -u $u -- bash -lc $cmd | Out-Host
  return $LASTEXITCODE
}
function WslPath([string]$winPath) {
  # C:\Users\x\repo -> /mnt/c/Users/x/repo
  $p = $winPath -replace '\\', '/'
  if ($p -match '^([A-Za-z]):(.*)$') { return "/mnt/$($Matches[1].ToLower())$($Matches[2])" }
  return $p
}

if (-not $LinuxUser -or $LinuxUser -notmatch '^[a-z_][a-z0-9_-]*$') {
  Fail "'$LinuxUser' is not a valid Linux user name; pass -LinuxUser name"
}

if ($WithDemoCorpus -and ($WithCorpus -or $WithNcCorpus -or $NoKnowledgebase)) {
  Fail '-WithDemoCorpus replaces -WithCorpus and cannot be combined with -WithCorpus, -WithNcCorpus or -NoKnowledgebase'
}

# --- 1. prerequisites ------------------------------------------------------------------------
Step 'Checking Windows, Git and WSL'
$build = [Environment]::OSVersion.Version.Build
if ($build -lt 22000) { Fail "Windows 11 is required (this is build $build)" }
if (-not (Get-Command git.exe -ErrorAction SilentlyContinue)) {
  Fail 'Git for Windows is not installed: https://git-scm.com/download/win'
}
& wsl.exe --status *> $null
if ($LASTEXITCODE -ne 0) {
  Write-Host 'WSL is not installed. Installing it (administrator rights needed)...'
  Start-Process wsl.exe -ArgumentList '--install', '--no-distribution' -Verb RunAs -Wait
  Write-Host 'Restart Windows, then run this script again.' -ForegroundColor Yellow
  exit 3010
}
& wsl.exe --update *> $null   # a current WSL is needed for cloud-init and autoMemoryReclaim

# --- 2. .wslconfig -----------------------------------------------------------------------------
Step 'Memory limits (%USERPROFILE%\.wslconfig)'
$wslconfig = Join-Path $env:USERPROFILE '.wslconfig'
$wanted = Get-Content -Raw (Join-Path $Here 'wslconfig')
$changed = $false
if (Test-Path $wslconfig) {
  if ((Get-Content -Raw $wslconfig) -ne $wanted) {
    $bak = "$wslconfig.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
    Copy-Item $wslconfig $bak
    Write-Host "existing .wslconfig backed up to $bak"
    $changed = $true
  }
} else { $changed = $true }
if ($changed) {
  Set-Content -Path $wslconfig -Value $wanted -NoNewline
  $running = (& wsl.exe -l --running -q 2>$null) | Where-Object { $_.Trim() }
  if ($running) {
    Write-Host "written; it applies after 'wsl --shutdown' (distros running now: $($running -join ', '))" -ForegroundColor Yellow
  } else {
    & wsl.exe --shutdown
    Write-Host 'written and applied'
  }
} else { Write-Host 'already in place' }

# --- 3. cloud-init user-data -------------------------------------------------------------------
$installed = (& wsl.exe -l -q 2>$null) | ForEach-Object { $_.Trim() } | Where-Object { $_ -eq $Distro }
if (-not $installed) {
  Step "cloud-init user-data for $Distro (user $LinuxUser)"
  $ciDir = Join-Path $env:USERPROFILE '.cloud-init'
  New-Item -ItemType Directory -Force -Path $ciDir | Out-Null
  $ciFile = Join-Path $ciDir "$Distro.user-data"
  if (Test-Path $ciFile) {
    Copy-Item $ciFile "$ciFile.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
  }
  $userData = (Get-Content -Raw (Join-Path $Here "$Distro.user-data")) -replace '__WSL_USER__', $LinuxUser
  # LF line endings: cloud-init reads it inside Linux
  [IO.File]::WriteAllText($ciFile, ($userData -replace "`r`n", "`n"))

  # --- 4. the distro -------------------------------------------------------------------------
  Step "Installing $Distro"
  & wsl.exe --install -d $Distro --no-launch
  if ($LASTEXITCODE -ne 0) { Fail "wsl --install -d $Distro failed" }
  # A store-packaged distro is registered only on its first launch; register it without the
  # interactive user prompt (cloud-init creates the user).
  $registered = (& wsl.exe -l -q 2>$null) | ForEach-Object { $_.Trim() } | Where-Object { $_ -eq $Distro }
  if (-not $registered) {
    $launcher = ($Distro -replace '[-.]', '').ToLower() + '.exe'   # ubuntu2404.exe
    & $launcher install --root
  }
}

Step 'Waiting for cloud-init (first boot)'
$null = InWsl 'command -v cloud-init >/dev/null && cloud-init status --wait || true' -Root
# Fallback for an image without cloud-init: create the user and the wsl.conf entries here.
$fix = @"
id $LinuxUser >/dev/null 2>&1 || useradd -m -s /bin/bash -G adm,sudo $LinuxUser
grep -q '^systemd=true' /etc/wsl.conf 2>/dev/null || printf '\n[boot]\nsystemd=true\n' >> /etc/wsl.conf
grep -q '^default=$LinuxUser' /etc/wsl.conf || printf '\n[user]\ndefault=$LinuxUser\n' >> /etc/wsl.conf
"@
if ((InWsl ($fix -replace "`r", '') -Root) -ne 0) { Fail 'could not create the Linux user' }
# wsl.conf (systemd, default user) applies on the next start of the distro
& wsl.exe --terminate $Distro | Out-Null
if ((InWsl "passwd -S $LinuxUser | grep -q ' P '" -Root) -ne 0) {
  Write-Host "Set a password for $LinuxUser (sudo asks for it):"
  & wsl.exe -d $Distro -u root -- passwd $LinuxUser
}

# --- 5. SSH key for GitHub ---------------------------------------------------------------------
Step 'SSH key for GitHub'
if ((InWsl 'ls ~/.ssh/id_ed25519 ~/.ssh/id_rsa 2>/dev/null | grep -q .') -ne 0) {
  $winKey = @('id_ed25519', 'id_rsa') | ForEach-Object { Join-Path $env:USERPROFILE ".ssh\$_" } |
            Where-Object { (Test-Path $_) -and (Test-Path "$_.pub") } | Select-Object -First 1
  if ($winKey -and -not $NoCopySshKey) {
    $src = WslPath $winKey
    $name = Split-Path -Leaf $winKey
    Write-Host "copying $winKey into WSL ~/.ssh/$name"
    if ((InWsl "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cp '$src' '$src.pub' ~/.ssh/ && chmod 600 ~/.ssh/$name && chmod 644 ~/.ssh/$name.pub") -ne 0) {
      Fail "could not copy $winKey into WSL"
    }
  } else {
    $null = InWsl "mkdir -p ~/.ssh && chmod 700 ~/.ssh && ssh-keygen -t ed25519 -N '' -C '$LinuxUser@wsl-pharmacolibrary' -f ~/.ssh/id_ed25519"
    Write-Host "`nAdd this public key to your GitHub account (https://github.com/settings/keys):`n" -ForegroundColor Yellow
    $null = InWsl 'cat ~/.ssh/id_ed25519.pub'
    Read-Host "`nPress Enter once the key is added"
  }
}
if ((InWsl 'ssh -o StrictHostKeyChecking=accept-new -T git@github.com 2>&1 | grep -q "successfully authenticated"') -ne 0) {
  Fail 'GitHub does not accept the SSH key in WSL ~/.ssh. Register it at https://github.com/settings/keys and run this script again.'
}
Write-Host 'GitHub accepts the key'

# --- 6. project setup (shared with the Vagrant VM) ---------------------------------------------
Step 'Project setup: bootstrap-dbs.sh'
$script = WslPath (Join-Path $RepoDir 'bootstrap-dbs.sh')
# strip CR: Git for Windows may have checked the script out with CRLF line endings
# GROBID: the CRF-only image and 2 GB, not run_grobid.sh's deep-learning image and 8 GB
$bootArgs = "--user $LinuxUser --with-grobid --grobid-image lfoppiano/grobid:0.9.0-crf --grobid-mem 2g"
if ($WithOmc)  { $bootArgs += ' --with-omc' }
if ($WithWasm) { $bootArgs += ' --with-wasm' }
if ($NoKnowledgebase) { $bootArgs += ' --no-kb' }
if ($WithDemoCorpus) { $bootArgs += ' --with-demo-corpus' }
if ($WithCorpus) { $bootArgs += ' --with-corpus' }
if ($WithNcCorpus) { $bootArgs += ' --with-nc-corpus' }
$rc = InWsl "tr -d '\r' < '$script' > /tmp/bootstrap-dbs.sh && bash /tmp/bootstrap-dbs.sh $bootArgs" -Root
if ($rc -ne 0) { Fail "bootstrap-dbs.sh failed (exit $rc); fix the cause and run this script again" }

Step 'Done'
Write-Host @"
Open the environment:   wsl -d $Distro
Repositories:           ~/pharmacolibrary-dev, ~/dbs-components-dev, ~/pharmacolibrary-docs
Knowledge base:         ~/knowledgebase (Zenodo; set in ~/pharmacolibrary-dev/pharmacolibrary.local.json)
Python:                 source ~/venv/bin/activate
GROBID:                 cd ~/pharmacolibrary-dev && scripts/run_grobid.sh   (CRF image, 2 GB)
Editor:                 code ~/pharmacolibrary-dev   (VS Code with the WSL extension)
Keep the knowledge base inside WSL (~/...), not under /mnt/c.
"@
