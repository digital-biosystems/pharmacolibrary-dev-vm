# Pharmacolibrary dev VM

Vagrant setup for a Pharmacolibrary development virtual machine. Two ways to get the same project setup:

- **VirtualBox VM** (`vagrant up`): a full Ubuntu desktop with 8 GB RAM, kept apart from the host. Needs a host with 16 GB or more.
- **Windows 11 with WSL2** (`windows\setup.cmd`): a minimal Ubuntu 24.04 inside Windows, without a VM that takes a fixed 8 GB. For machines with 8 GB RAM. See [Windows 11 (WSL2)](#windows-11-wsl2).

The provisioning is split in two:

- `bootstrap.sh`: VirtualBox VM only. It adds a 4 GB swapfile, copies the SSH keys from this directory, and mounts each WebDAV storage configured by a `{storage_dir}.webdav` file to `/mnt/{storage_dir}` (davfs2, remounted after reboot).
- `bootstrap-dbs.sh`: the project setup, shared by the VM and WSL. It installs git, pins GitHub's host key and clones the `digital-biosystems` repositories side by side into `--projects-dir` (default the user's home; on Windows `%USERPROFILE%\Projects`):
  - `pharmacolibrary-dev` (private)
  - `dbs-components-dev` (private)
  - `pharmacolibrary-docs` (public)
  - `Pharmacolibrary` (public; the Modelica library, exported as `PHARMACOLIBRARY_MO`)

  It then creates the Python venv `~/venv` from `pharmacolibrary-dev/requirements.txt`, installs Docker Engine (for GROBID and OpenModelica), and writes `~/.pharmacolibrary_env`, which `~/.bashrc` sources (`PK_OMC_DOCKER` where Docker is on and omc is not installed; without systemd also `RUN_LOGGED_INHIBIT=0` and `LANG=C.UTF-8`). Without systemd (WSL) Docker is started by its init script. Options: `--with-grobid`, `--with-omc` (pull the OpenModelica image now), `--with-wasm` (clones Bodylight.js-FMU-Compiler for the browser simulator), `--projects-dir DIR`, `--no-docker`, `--no-venv`. The header of `bootstrap-dbs.sh` lists them all.

  Last it unpacks the public Zenodo knowledge base into `~/knowledgebase` and sets it as `"knowledgebase"` in `~/pharmacolibrary-dev/pharmacolibrary.local.json` (other settings in that file are kept; a different earlier value is replaced and printed). By default this is the **research** dataset (record 24119263: per-drug records, provenance, models; about 0.5 GB packed, 2.3 GB unpacked). `--with-corpus` adds the redistributable full-text corpus (record 24125755, about 43 GB free disk needed) and `--with-nc-corpus` the non-commercial one (record 24133749; its licence terms apply). `--with-demo-corpus` is the small alternative to `--with-corpus`: the research dataset **and** the redistributable corpus, unpacking only the files of the `ddd` and `dku` panel drugs (metformin, ibuprofen, amoxicillin, semaglutide, tolvaptan, allopurinol, clopidogrel, vancomycin, tacrolimus, busulfan, infliximab, posaconazole), about 0.7 GB unpacked, about 1.1 GB read from Zenodo (the research archive is a `.tar.gz`, which can only be streamed: 0.5 GB; the corpus shards are plain `.tar`, so only the byte ranges of these drugs and of the files they hard-link to are fetched: 0.5 GB of 37 GB). Each file is checked against the SHA-256 in the dataset's `MANIFEST.csv`, and a shard whose offsets do not fit the manifest is streamed whole instead. No archive is kept; the test run took under 5 minutes. It cannot be combined with `--with-corpus`; with `--with-nc-corpus` it adds the whole non-commercial corpus. The drug list is `DEMO_DRUGS` at the top of the script; keep it in step with the panels in `pharmacolibrary-dev`. `--kb-dir DIR` changes the place and `--no-kb` skips all of it. Every archive is checked against Zenodo's MD5, unpacked, then deleted, and a rerun resumes. A record that is not public yet is skipped with a warning and the knowledge base is not configured; the record owner can pass `--zenodo-token-file FILE`. Anyone else downloads a draft with its **share link**: the owner opens the draft on Zenodo, *Share* → *Get a link*, permission *Can preview*, and hands out the link; put one link per line (`https://zenodo.org/records/24119263?preview=1&token=…`, or `ID TOKEN`) in `zenodo-links.txt` in this repository or its `windows` folder (gitignored, picked up automatically by `setup.ps1`; `bootstrap-dbs.sh` alone looks beside itself) or pass `--zenodo-links-file FILE`. The draft's files are then read through the draft API with the link's token, byte ranges included, so `--with-demo-corpus` works too. A link can be revoked or given an expiry date; once the records are published it is not needed. In the Vagrant VM the default also applies, so pass `--no-kb` in the `Vagrantfile` to keep using the `/vagrant_data` share.

The VM is created from the `westlife-eu/openmodelica1.25` box, which comes with OpenModelica installed.

VM resources: 8 GB RAM, 4 CPUs, VirtualBox GUI enabled.

Forwarded ports (guest → host): 80 → 8080, 4000 → 4000, 9000 → 9000.

Shared folders: this directory is mounted in the VM at `/vagrant`, and the directory three levels above it (`../../..`) at `/vagrant_data`.

## Requirements

Install [VirtualBox](https://www.virtualbox.org/wiki/Downloads) and [Vagrant](https://developer.hashicorp.com/vagrant/install).

**Windows / macOS:** download and run the installers from the two links above.

**Ubuntu / Debian:**

```bash
# VirtualBox
sudo apt update
sudo apt install virtualbox

# Vagrant (HashiCorp repository)
wget -O - https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install vagrant
```

Check that both are installed:

```bash
vagrant --version
VBoxManage --version
```

## Start

1. Copy your SSH key pair into this directory as `id_rsa` and `id_rsa.pub`. The public key must be registered with a GitHub account that has access to the private `digital-biosystems` repositories. Provisioning copies the keys to `/home/vagrant/.ssh` in the VM.

   The keys are excluded by `.gitignore`. Never commit them.

2. Optional: for each ownCloud storage to mount, add a `{storage_dir}.webdav` file to this directory. The file contains one line, the public share link:

   ```
   https://owncloud.cesnet.cz/index.php/s/<secret>
   ```

   The storage is mounted to `/mnt/{storage_dir}`, owned by the `vagrant` user. The link contains the secret that grants access to the storage. `.webdav` files are excluded by `.gitignore`. Never commit them.

3. Create and provision the VM:

   ```bash
   vagrant up
   ```

   The first run downloads the base box, so it takes a while. A VirtualBox window opens with the VM's desktop.

4. Open a shell in the VM:

   ```bash
   vagrant ssh
   ```

## Remove the VM

Stop the VM and delete it:

```bash
vagrant destroy
```

This removes the VM and everything stored inside it, including uncommitted work in the cloned repositories. Push your changes first. The downloaded base box stays cached; to delete it as well, run `vagrant box remove westlife-eu/openmodelica1.25`.

## Windows 11 (WSL2)

For machines with 8 GB RAM. A minimal Ubuntu 24.04 (the `ubuntu-base` root filesystem, about 30 MB, not the Microsoft Store Ubuntu) is imported as the WSL distro `Pharmacolibrary`, limited to 5 GB RAM plus 6 GB swap. Docker Engine runs inside it (Docker Desktop is not needed); GROBID, OpenModelica and the FMU compiler run in Docker.

### Requirements

- Windows 11, with virtualisation enabled in the firmware.
- This repository in `%USERPROFILE%\Projects\pharmacolibrary-dev-vm` ([Git for Windows](https://git-scm.com/download/win) to clone it, or a downloaded ZIP).
- An SSH key registered with a GitHub account that has access to the private `digital-biosystems` repositories, as `%USERPROFILE%\.ssh\id_ed25519` or `id_rsa`. Without one, the script generates a key inside WSL and waits while you register it on GitHub.

### Start

1. Clone this repository and run the setup script, from PowerShell or cmd:

   ```powershell
   mkdir $HOME\Projects -Force; cd $HOME\Projects
   git clone git@github.com:digital-biosystems/pharmacolibrary-dev-vm.git
   cd pharmacolibrary-dev-vm
   windows\setup.cmd
   ```

   `setup.cmd` starts `setup.ps1` with the execution policy bypassed for that one run (`powershell -ExecutionPolicy Bypass -File windows\setup.ps1` does the same) and passes its options on. Started directly as `.\windows\setup.ps1`, the script stops with *"running scripts is disabled on this system"*, because Windows blocks local scripts by default. If the error remains, an administrator has set the policy by Group Policy (`Get-ExecutionPolicy -List` shows `MachinePolicy` or `UserPolicy`); ask them to allow it.

   If WSL is not installed yet, the script installs it and asks you to restart Windows. Run it again after the restart.

2. Without options the script sets up everything:
   1. writes `windows\wslconfig` to `%USERPROFILE%\.wslconfig` (memory limits; an existing file is backed up first);
   2. downloads the newest `ubuntu-base-24.04.x-base-amd64.tar.gz` (arm64 on ARM) from `cdimage.ubuntu.com`, checks it against `SHA256SUMS` and imports it with `wsl --import` into `%LOCALAPPDATA%\Pharmacolibrary\wsl\Pharmacolibrary`;
   3. installs sudo, ssh and an editor, creates your Linux user, asks for its password and writes `/etc/wsl.conf` (default user; `systemd=false`; a boot command that starts Docker whenever the distro starts; `[automount] options="metadata,case=dir"`: Linux permissions on `C:` and case-sensitive directories when created from Linux); links `~/Projects` in Linux to `%USERPROFILE%\Projects`;
   4. copies your Windows SSH key into the Linux user's `~/.ssh` and checks that GitHub accepts it;
   5. runs `bootstrap-dbs.sh --projects-dir ~/Projects --kb-dir ~/Projects/knowledgebase --with-wasm --with-demo-corpus --grobid-image lfoppiano/grobid:0.9.0-crf --grobid-mem 2g`: the repositories cloned beside this one, the Python venv with the full `requirements.txt` (JupyterLab included) in `~/venv` inside Linux, Docker Engine, and the Zenodo knowledge base with the full texts of the 12 demo drugs. The Docker images (GROBID, OpenModelica, emsdk) are pulled when first used.

   Options: `-WithCorpus` (the whole redistributable full-text corpus, about 43 GB of disk, instead of the demo drugs' files), `-WithNcCorpus` (also the non-commercial corpus, about 20 GB; its licence terms apply), `-NoKnowledgebase` (no Zenodo download), `-ProjectsDir DIR` (another Windows folder), `-ZenodoLinks FILE` (share links of the unpublished Zenodo drafts, see above; `zenodo-links.txt` in this repo is used when present), `-LinuxUser name`, `-Distro name`.

3. Open the environment with `wsl -d Pharmacolibrary`, or in VS Code with the WSL extension: `code ~/Projects/pharmacolibrary-dev` from that shell.

### Layout

Everything stays in one Windows folder, which Linux sees at the same relative paths:

| Windows | Linux (WSL) | |
|---|---|---|
| `%USERPROFILE%\Projects\pharmacolibrary-dev-vm` | `~/Projects/pharmacolibrary-dev-vm` | this repository |
| `%USERPROFILE%\Projects\pharmacolibrary-dev` | `~/Projects/pharmacolibrary-dev` | the pipeline |
| `%USERPROFILE%\Projects\pharmacolibrary-docs` | `~/Projects/pharmacolibrary-docs` | the docs site, written by `docs.build` |
| `%USERPROFILE%\Projects\Pharmacolibrary` | `~/Projects/Pharmacolibrary` | the Modelica library (`PHARMACOLIBRARY_MO`) |
| `%USERPROFILE%\Projects\dbs-components-dev`, `Bodylight.js-FMU-Compiler` | `~/Projects/…` | components, FMU compiler |
| `%USERPROFILE%\Projects\knowledgebase` | `~/Projects/knowledgebase` | the knowledge base (`"knowledgebase"` in `pharmacolibrary.local.json`) |
| | `~/venv`, `~/.pharmacolibrary_env` | inside Linux only |

`~/Projects` is a symlink to `/mnt/c/Users/<you>/Projects`.

The script skips steps already done, so running it again is safe, as `vagrant provision` is.

### Working in WSL

- The repositories and the knowledge base are on the Windows disk, so Windows programs can use them. From Linux that disk is slower, several times for many small files (a full-knowledge-base pass, `git status` on a large tree); the venv stays inside Linux for that reason. Windows Defender scans every file Linux reads there; an exclusion for `%USERPROFILE%\Projects\knowledgebase` speeds it up, if your organisation allows one.
- Directories created from Linux are case-sensitive (`case=dir`), as the knowledge base needs. Folders created from Windows Explorer are not; create new knowledge-base folders from Linux.
- Use git from Linux for these repositories. Git for Windows on the same working tree converts line endings and file modes differently.
- On 8 GB, run one pipeline group at a time and start GROBID (`scripts/run_grobid.sh`) only when you need it. LLM calls go to remote services, so no local model runs.
- The distro runs without systemd: Docker is started by `/usr/local/sbin/pharmacolibrary-boot` when the distro starts (`sudo service docker start` by hand), and `run_logged.sh` holds no sleep lock (`RUN_LOGGED_INHIBIT=0`). Windows still sleeps during a long run; change its power plan for that.
- `.wslconfig` applies to every WSL distro and only after `wsl --shutdown`.

### Remove

```powershell
wsl --unregister Pharmacolibrary
```

This deletes the distro: the Linux user, the venv and the Docker images. The repositories and the knowledge base in `%USERPROFILE%\Projects` stay. The downloaded image stays in `%LOCALAPPDATA%\Pharmacolibrary`; delete that folder too if you like.

An `Ubuntu-24.04` distro made by an earlier version of this script is not touched; remove it the same way (`wsl --unregister Ubuntu-24.04`) once your work in it is pushed.
