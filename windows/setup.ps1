<#
.SYNOPSIS
  Pharmacolibrary dev environment on Windows 11 in WSL2 - the Windows counterpart of `vagrant up`.

.DESCRIPTION
  Run without options it sets up everything: the base system, Python with the full
  requirements.txt (JupyterLab included), Docker Engine (GROBID, OpenModelica and the FMU
  compiler run in it), Bodylight.js-FMU-Compiler and the Zenodo knowledge base with the full
  texts of the demo drugs. The options choose only the large data downloads.

  1. Checks Windows 11 and WSL (installs WSL if missing; then a restart is needed).
  2. Copies wslconfig to %USERPROFILE%\.wslconfig (memory limits for 8 GB machines).
  3. Downloads the minimal Ubuntu 24.04 root filesystem (ubuntu-base, about 30 MB), checks its
     SHA-256 and imports it as the WSL distro "Pharmacolibrary" (not the Microsoft Store Ubuntu).
  4. Creates the Linux user and writes /etc/wsl.conf: default user, no systemd, Docker started
     when the distro starts, Windows drives mounted with Linux permissions and with directories
     created from Linux case-sensitive. Links ~/Projects in Linux to %USERPROFILE%\Projects.
  5. Puts an SSH key that GitHub accepts into the Linux user's ~/.ssh, and copies the user
     configuration and keys of %USERPROFILE%\.config\pharmacolibrary into ~/.config/pharmacolibrary
     (mode 600). If that folder is missing, it is created from ..\config-template.
  6. Runs ..\bootstrap-dbs.sh in the distro as root: the repositories cloned side by side into
     %USERPROFILE%\Projects (beside this one), Python venv (~/venv, inside Linux), Docker Engine,
     Bodylight.js-FMU-Compiler, the Zenodo knowledge base in %USERPROFILE%\Projects\knowledgebase.

  Layout, the same path from Windows and Linux:
    %USERPROFILE%\Projects\pharmacolibrary-dev-vm   = ~/Projects/pharmacolibrary-dev-vm (this repo)
    %USERPROFILE%\Projects\pharmacolibrary-pipeline, pharmacolibrary-docs, Pharmacolibrary,
                           dbs-components-dev, Bodylight.js-FMU-Compiler
    %USERPROFILE%\Projects\knowledgebase

  Running it again is safe (as `vagrant provision`): the repositories are pulled, Docker and finished
  Zenodo archives are skipped.
  Remove everything with:  wsl --unregister Pharmacolibrary   (deletes the distro and all work in it)

.PARAMETER LinuxUser
  Linux user name in the distro. Default: the Windows user name, lower-cased.
.PARAMETER Distro
  WSL distro name. Default: Pharmacolibrary.
.PARAMETER WithCorpus
  Unpack the whole redistributable Zenodo full-text corpus (about 43 GB of disk) instead of the
  full texts of the 12 demo drugs only.
.PARAMETER WithNcCorpus
  Also the non-commercial Zenodo corpus (CC BY-NC papers; its licence terms apply). The default
  setup already has the 12 demo drugs' files of it; with -WithCorpus this adds all of it (about 20 GB).
.PARAMETER NoNcCorpus
  Leave the non-commercial corpus out of the default setup.
.PARAMETER NoKnowledgebase
  Skip the Zenodo knowledge base.
.PARAMETER ProjectsDir
  Windows folder for the repositories and the knowledge base. Default: %USERPROFILE%\Projects.
.PARAMETER ZenodoLinks
  Text file with Zenodo share links, one per line, to download the datasets while they are
  still unpublished drafts (the record owner makes them: the draft's Share > Get a link,
  "Can preview"). Default: the first zenodo-links.txt found in %USERPROFILE%\.config\pharmacolibrary,
  this repository or its windows folder (gitignored).
  Not needed once the records are published.

.EXAMPLE
  windows\setup.cmd
  windows\setup.cmd -WithCorpus
  windows\setup.cmd -ZenodoLinks C:\Users\me\Downloads\zenodo-links.txt
  powershell -ExecutionPolicy Bypass -File windows\setup.ps1
#>
[CmdletBinding()]
param(
  [string]$LinuxUser = ($env:USERNAME.ToLower() -replace '[^a-z0-9_-]', ''),
  [string]$Distro = 'Pharmacolibrary',
  [switch]$WithCorpus,
  [switch]$WithNcCorpus,
  [switch]$NoNcCorpus,
  [switch]$NoKnowledgebase,
  [string]$ProjectsDir = (Join-Path $env:USERPROFILE 'Projects'),
  [string]$ZenodoLinks = ''
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # Windows PowerShell 5 downloads slowly with a progress bar
# wsl.exe writes UTF-16 by default; this makes its output plain text PowerShell can compare
$env:WSL_UTF8 = '1'
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoDir = Split-Path -Parent $Here
$BaseUrl = 'https://cdimage.ubuntu.com/ubuntu-base/releases/24.04/release'
$DataDir = Join-Path $env:LOCALAPPDATA 'Pharmacolibrary'

function Step($msg) { Write-Host "`n== $msg" -ForegroundColor Cyan }
function Fail($msg) { Write-Host "ERROR: $msg" -ForegroundColor Red; exit 1 }
# Run a command in the distro; -Root runs it as root. Its output goes to the console, so the
# function returns only the exit code ($LASTEXITCODE holds it too). Keep double quotes out of
# $cmd: Windows PowerShell 5.1 passes them to wsl.exe unescaped. A longer script goes through a
# file (InWslScript).
function InWsl([string]$cmd, [switch]$Root) {
  $u = if ($Root) { 'root' } else { $LinuxUser }
  & wsl.exe -d $Distro -u $u -- bash -lc ($cmd -replace "`r", '') | Out-Host
  return $LASTEXITCODE
}
function InWslScript([string]$text, [switch]$Root) {
  $f = Join-Path $env:TEMP "pharmacolibrary-$PID.sh"
  [IO.File]::WriteAllText($f, ($text -replace "`r", ''))     # LF, no BOM
  try { return (InWsl "bash '$(WslPath $f)'" -Root:$Root) } finally { Remove-Item $f -ErrorAction SilentlyContinue }
}
function WslPath([string]$winPath) {
  # C:\Users\x\repo -> /mnt/c/Users/x/repo
  $p = $winPath -replace '\\', '/'
  if ($p -match '^([A-Za-z]):(.*)$') { return "/mnt/$($Matches[1].ToLower())$($Matches[2])" }
  return $p
}
function Installed { return [bool]((& wsl.exe -l -q 2>$null) | ForEach-Object { $_.Trim() } | Where-Object { $_ -eq $Distro }) }

if (-not $LinuxUser -or $LinuxUser -notmatch '^[a-z_][a-z0-9_-]*$') {
  Fail "'$LinuxUser' is not a valid Linux user name; pass -LinuxUser name"
}
if ($NoKnowledgebase -and ($WithCorpus -or $WithNcCorpus)) {
  Fail '-WithCorpus and -WithNcCorpus need the knowledge base; drop -NoKnowledgebase'
}
if ($WithNcCorpus -and $NoNcCorpus) { Fail '-WithNcCorpus and -NoNcCorpus exclude each other' }

$ProjectsDir = [IO.Path]::GetFullPath($ProjectsDir)
if ((Split-Path -Parent $RepoDir) -ne $ProjectsDir.TrimEnd('\')) {
  Write-Host "NOTE: this repository is in $RepoDir, not in $ProjectsDir; the other repositories and the knowledge base go to $ProjectsDir" -ForegroundColor Yellow
}
New-Item -ItemType Directory -Force -Path $ProjectsDir | Out-Null
$ProjectsWsl = WslPath $ProjectsDir
if ($ProjectsWsl -match "['`"]") { Fail "the folder $ProjectsDir has a quote in its name; pass -ProjectsDir" }

# --- 1. prerequisites ------------------------------------------------------------------------
Step 'Checking Windows and WSL'
$build = [Environment]::OSVersion.Version.Build
if ($build -lt 22000) { Fail "Windows 11 is required (this is build $build)" }
& wsl.exe --status *> $null
if ($LASTEXITCODE -ne 0) {
  Write-Host 'WSL is not installed. Installing it (administrator rights needed)...'
  Start-Process wsl.exe -ArgumentList '--install', '--no-distribution' -Verb RunAs -Wait
  Write-Host 'Restart Windows, then run this script again.' -ForegroundColor Yellow
  exit 3010
}
& wsl.exe --update *> $null   # a current WSL is needed for autoMemoryReclaim

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

# --- 3. the distro: minimal Ubuntu 24.04 (ubuntu-base) ------------------------------------------
if (-not (Installed)) {
  Step "Importing $Distro (ubuntu-base 24.04)"
  $arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'amd64' }
  New-Item -ItemType Directory -Force -Path $DataDir | Out-Null
  # curl.exe to a file, read as text: the server sends SHA256SUMS without a Content-Type, so
  # Invoke-WebRequest in Windows PowerShell 5.1 returns its .Content as bytes, not lines
  $sumsFile = Join-Path $DataDir 'SHA256SUMS'
  & curl.exe -fsSL --retry 3 -o $sumsFile "$BaseUrl/SHA256SUMS"
  if ($LASTEXITCODE -ne 0) { Fail "download of $BaseUrl/SHA256SUMS failed" }
  $sums = Get-Content -Encoding Ascii $sumsFile | ForEach-Object { $_.Trim() }
  # the newest point release listed, e.g. ubuntu-base-24.04.4-base-amd64.tar.gz
  $entry = $sums | ForEach-Object {
      if ($_ -match "^([0-9a-f]{64}) \*?(ubuntu-base-24\.04(\.(\d+))?-base-$arch\.tar\.gz)$") {
        [pscustomobject]@{ Sha = $Matches[1]; Name = $Matches[2]; Point = [int]("0$($Matches[4])") }
      } } | Sort-Object Point | Select-Object -Last 1
  if (-not $entry) { Fail "no ubuntu-base 24.04 $arch image listed in $BaseUrl/SHA256SUMS" }
  $tar = Join-Path $DataDir $entry.Name
  if (-not (Test-Path $tar) -or (Get-FileHash -Algorithm SHA256 $tar).Hash.ToLower() -ne $entry.Sha) {
    Write-Host "downloading $($entry.Name)"
    & curl.exe -fL --retry 3 -o $tar "$BaseUrl/$($entry.Name)"
    if ($LASTEXITCODE -ne 0) { Fail "download of $BaseUrl/$($entry.Name) failed" }
  }
  $got = (Get-FileHash -Algorithm SHA256 $tar).Hash.ToLower()
  if ($got -ne $entry.Sha) { Remove-Item $tar; Fail "$($entry.Name): SHA-256 $got, SHA256SUMS says $($entry.Sha); deleted, run again" }
  $target = Join-Path $DataDir "wsl\$Distro"
  New-Item -ItemType Directory -Force -Path $target | Out-Null
  & wsl.exe --import $Distro $target $tar --version 2
  if ($LASTEXITCODE -ne 0) { Fail "wsl --import $Distro failed" }
  Write-Host "imported into $target"
}

# --- 4. user and wsl.conf ----------------------------------------------------------------------
Step "Linux user $LinuxUser"
# ubuntu-base has neither sudo nor ssh nor an editor; bootstrap-dbs.sh installs the rest
$base = @"
set -e
export DEBIAN_FRONTEND=noninteractive
need=''
for p in sudo procps openssh-client ca-certificates nano less; do
  dpkg -s `$p >/dev/null 2>&1 || need="`$need `$p"
done
if [ -n "`$need" ]; then apt-get update && apt-get -y install `$need; fi
id $LinuxUser >/dev/null 2>&1 || useradd -m -s /bin/bash -G sudo $LinuxUser
# started by WSL as root when the distro starts; Docker is installed later by bootstrap-dbs.sh
cat > /usr/local/sbin/pharmacolibrary-boot <<'EOF'
#!/bin/sh
[ -x /etc/init.d/docker ] && service docker start >/dev/null 2>&1
exit 0
EOF
chmod 755 /usr/local/sbin/pharmacolibrary-boot
# automount: Linux permissions on C: (git file modes, chmod) and case-sensitive directories when
# created from Linux, which the knowledge base needs (paper files that differ only in case)
conf='[user]
default=$LinuxUser

[boot]
systemd=false
command=/usr/local/sbin/pharmacolibrary-boot

[automount]
options="metadata,case=dir"
'
if [ "`$(cat /etc/wsl.conf 2>/dev/null)" != "`$(printf '%s' "`$conf")" ]; then
  printf '%s' "`$conf" > /etc/wsl.conf
  touch /tmp/.wslconf-changed
fi
"@
if ((InWslScript $base -Root) -ne 0) { Fail 'could not set up the base system and the Linux user' }
# ~/Projects in Linux is the Windows Projects folder, so both see the same paths
if ((InWsl "home=`$(getent passwd $LinuxUser | cut -d: -f6); [ -e `$home/Projects ] || { ln -s '$ProjectsWsl' `$home/Projects && chown -h ${LinuxUser}: `$home/Projects; }" -Root) -ne 0) {
  Fail "could not link ~/Projects to $ProjectsWsl"
}
if ((InWsl 'rm /tmp/.wslconf-changed 2>/dev/null' -Root) -eq 0) {
  # wsl.conf (default user, boot command) applies on the next start of the distro
  & wsl.exe --terminate $Distro | Out-Null
  Write-Host '/etc/wsl.conf written'
}
if ((InWsl "passwd -S $LinuxUser | grep -q ' P '" -Root) -ne 0) {
  Write-Host "Set a password for $LinuxUser (sudo asks for it):"
  & wsl.exe -d $Distro -u root -- passwd $LinuxUser
  if ($LASTEXITCODE -ne 0) { Fail 'the password was not set; run this script again' }
}

# --- 5. SSH key for GitHub ---------------------------------------------------------------------
Step 'SSH key for GitHub'
if ((InWsl 'ls ~/.ssh/id_ed25519 ~/.ssh/id_rsa 2>/dev/null | grep -q .') -ne 0) {
  $winKey = @('id_ed25519', 'id_rsa') | ForEach-Object { Join-Path $env:USERPROFILE ".ssh\$_" } |
            Where-Object { (Test-Path $_) -and (Test-Path "$_.pub") } | Select-Object -First 1
  if ($winKey) {
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
if ((InWsl "ssh -o StrictHostKeyChecking=accept-new -T git@github.com 2>&1 | grep -q 'successfully authenticated'") -ne 0) {
  Fail 'GitHub does not accept the SSH key in WSL ~/.ssh. Register it at https://github.com/settings/keys and run this script again.'
}
Write-Host 'GitHub accepts the key'

# --- 5b. user configuration and keys (e-INFRA CZ, OpenAI, NCBI, Semantic Scholar, Zenodo, ...) -
# All of it lives in %USERPROFILE%\.config\pharmacolibrary (config-template\README.md lists the
# files). The code reads it from the Linux home (~/.config/pharmacolibrary): copy each file,
# subfolders included, that WSL does not have yet, mode 600, CRs stripped. *.example, README*
# and empty files are skipped; a file that differs is reported, not overwritten. Key contents
# are never printed.
Step 'User configuration and keys (~/.config/pharmacolibrary)'
$winConf = Join-Path $env:USERPROFILE '.config\pharmacolibrary'
if (-not (Test-Path $winConf)) {
  New-Item -ItemType Directory -Force $winConf | Out-Null
  Copy-Item (Join-Path $RepoDir 'config-template\*') $winConf -Recurse
  Write-Host "created $winConf from config-template. Fill in the keys you have, drop the .example suffix (README.md there lists the files) and run this script again." -ForegroundColor Yellow
}
$src = WslPath $winConf
$null = InWslScript @"
set -u
dst=`$HOME/.config/pharmacolibrary
mkdir -p "`$dst" && chmod 700 "`$HOME/.config" "`$dst"
cd '$src' || exit 1
find . -type f ! -name '*.example' ! -name 'README*' -size +0 | sort | while IFS= read -r f; do
  n=`${f#./}
  d=`$(dirname "`$dst/`$n")
  mkdir -p "`$d" && chmod 700 "`$d"
  if [ ! -e "`$dst/`$n" ]; then
    tr -d '\r' < "`$f" > "`$dst/`$n" && chmod 600 "`$dst/`$n" && echo "copied `$n"
  elif ! tr -d '\r' < "`$f" | cmp -s - "`$dst/`$n"; then
    echo "kept ~/.config/pharmacolibrary/`$n: it differs from the Windows copy (delete it to copy again)"
  fi
done
"@

# --- 6. project setup (shared with the Vagrant VM) ---------------------------------------------
Step 'Project setup: bootstrap-dbs.sh'
$script = WslPath (Join-Path $RepoDir 'bootstrap-dbs.sh')
# GROBID: the CRF-only image and 2 GB, not run_grobid.sh's deep-learning image and 8 GB.
# Docker images (GROBID, OpenModelica, emsdk) are pulled when first used, not here.
$bootArgs = "--user $LinuxUser --projects-dir '$ProjectsWsl' --kb-dir '$ProjectsWsl/knowledgebase'" +
            ' --with-wasm --grobid-image lfoppiano/grobid:0.9.0-crf --grobid-mem 2g'
if ($NoKnowledgebase) { $bootArgs += ' --no-kb' }
elseif ($WithCorpus) { $bootArgs += ' --with-corpus' }
else { $bootArgs += ' --with-demo-corpus' }
# the demo setup includes the non-commercial corpus (demo drugs only) unless -NoNcCorpus
if ($NoNcCorpus) { $bootArgs += ' --no-nc-corpus' }
elseif ($WithNcCorpus) { $bootArgs += ' --with-nc-corpus' }
# share links of unpublished Zenodo drafts: read from a file, never on the command line
if (-not $ZenodoLinks) {
  $ZenodoLinks = @((Join-Path $winConf 'zenodo-links.txt'), (Join-Path $RepoDir 'zenodo-links.txt'),
                   (Join-Path $Here 'zenodo-links.txt')) |
    Where-Object { Test-Path $_ } | Select-Object -First 1
}
if ($ZenodoLinks -and -not $NoKnowledgebase) {
  if (-not (Test-Path $ZenodoLinks)) { Fail "ZenodoLinks file not found: $ZenodoLinks" }
  $ZenodoLinks = (Resolve-Path $ZenodoLinks).Path
  Write-Host "Zenodo share links: $ZenodoLinks"
  $bootArgs += " --zenodo-links-file '$(WslPath $ZenodoLinks)'"
}
# strip CR: Git for Windows may have checked the script out with CRLF line endings
$rc = InWsl "tr -d '\r' < '$script' > /tmp/bootstrap-dbs.sh && bash /tmp/bootstrap-dbs.sh $bootArgs" -Root
if ($rc -ne 0) { Fail "bootstrap-dbs.sh failed (exit $rc); fix the cause and run this script again" }

Step 'Done'
Write-Host @"
Open the environment:   wsl -d $Distro
Repositories:           $ProjectsDir  (= ~/Projects in Linux): pharmacolibrary-pipeline,
                        pharmacolibrary-docs, Pharmacolibrary, dbs-components-dev,
                        Bodylight.js-FMU-Compiler
Knowledge base:         $ProjectsDir\knowledgebase (Zenodo; set in pharmacolibrary-pipeline\pharmacolibrary.local.json)
Python:                 source ~/venv/bin/activate   (inside Linux; jupyter lab works from there)
GROBID:                 cd ~/Projects/pharmacolibrary-pipeline && scripts/run_grobid.sh   (CRF image, 2 GB)
OpenModelica:           in Docker (PK_OMC_DOCKER), pulled on first use
Editor:                 code ~/Projects/pharmacolibrary-pipeline   (VS Code with the WSL extension)
Use git from Linux for these repositories; Windows programs can read and edit the files.
Remove:                 wsl --unregister $Distro   (deletes the distro and the venv; $ProjectsDir stays)
"@
