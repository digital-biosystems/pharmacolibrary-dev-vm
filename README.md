# Pharmacolibrary dev VM

Vagrant setup for a Pharmacolibrary development virtual machine. Two ways to get the same project setup:

- **VirtualBox VM** (`vagrant up`): a full Ubuntu desktop with 8 GB RAM, kept apart from the host. Needs a host with 16 GB or more.
- **Windows 11 with WSL2** (`windows\setup.ps1`): Ubuntu inside Windows, without a VM that takes a fixed 8 GB. For machines with 8 GB RAM. See [Windows 11 (WSL2)](#windows-11-wsl2).

The provisioning is split in two:

- `bootstrap.sh`: VirtualBox VM only. It adds a 4 GB swapfile, copies the SSH keys from this directory, and mounts each WebDAV storage configured by a `{storage_dir}.webdav` file to `/mnt/{storage_dir}` (davfs2, remounted after reboot).
- `bootstrap-dbs.sh`: the project setup, shared by the VM and WSL. It installs git, pins GitHub's host key and clones the `digital-biosystems` repositories into the user's home:
  - `pharmacolibrary-dev` (private)
  - `dbs-components-dev` (private)
  - `pharmacolibrary-docs` (public)

  It then creates the Python venv `~/venv` from `pharmacolibrary-dev/requirements.txt`, installs Docker Engine (for GROBID and OpenModelica), and writes `~/.pharmacolibrary_env`, which `~/.bashrc` sources. Options: `--with-grobid`, `--with-omc` (OpenModelica image, sets `PK_OMC_DOCKER`), `--with-wasm` (clones Bodylight.js-FMU-Compiler for the browser simulator), `--no-docker`, `--no-venv`. The header of `bootstrap-dbs.sh` lists them all.

  Last it unpacks the public Zenodo knowledge base into `~/knowledgebase` and sets it as `"knowledgebase"` in `~/pharmacolibrary-dev/pharmacolibrary.local.json` (other settings in that file are kept; a different earlier value is replaced and printed). By default this is the **research** dataset (record 24119263: per-drug records, provenance, models; about 0.5 GB packed, 2.3 GB unpacked). `--with-corpus` adds the redistributable full-text corpus (record 24125755, about 43 GB free disk needed) and `--with-nc-corpus` the non-commercial one (record 24133749; its licence terms apply). `--with-demo-corpus` is the small alternative to `--with-corpus`: the research dataset **and** the redistributable corpus, unpacking only the files of the `ddd` and `dku` panel drugs (metformin, ibuprofen, amoxicillin, semaglutide, tolvaptan, allopurinol, clopidogrel, vancomycin, tacrolimus, busulfan, infliximab, posaconazole), about 0.7 GB unpacked, about 1.1 GB read from Zenodo (the research archive is a `.tar.gz`, which can only be streamed: 0.5 GB; the corpus shards are plain `.tar`, so only the byte ranges of these drugs and of the files they hard-link to are fetched: 0.5 GB of 37 GB). Each file is checked against the SHA-256 in the dataset's `MANIFEST.csv`, and a shard whose offsets do not fit the manifest is streamed whole instead. No archive is kept; the test run took under 5 minutes. It cannot be combined with `--with-corpus` or `--with-nc-corpus`. The drug list is `DEMO_DRUGS` at the top of the script; keep it in step with the panels in `pharmacolibrary-dev`. `--kb-dir DIR` changes the place and `--no-kb` skips all of it. Every archive is checked against Zenodo's MD5, unpacked, then deleted, and a rerun resumes. A record that is not public yet is skipped with a warning and the knowledge base is not configured; the record owner can pass `--zenodo-token-file FILE`. In the Vagrant VM the default also applies, so pass `--no-kb` in the `Vagrantfile` to keep using the `/vagrant_data` share.

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

For machines with 8 GB RAM. Ubuntu 24.04 runs in WSL2, limited to 5 GB RAM plus 6 GB swap, and Docker Engine runs inside it (Docker Desktop is not needed).

### Requirements

- Windows 11, with virtualisation enabled in the firmware.
- [Git for Windows](https://git-scm.com/download/win).
- An SSH key registered with a GitHub account that has access to the private `digital-biosystems` repositories, as `%USERPROFILE%\.ssh\id_ed25519` or `id_rsa`. Without one, the script generates a key inside WSL and waits while you register it on GitHub.

### Start

1. Clone this repository and run the setup script from PowerShell:

   ```powershell
   git clone git@github.com:digital-biosystems/pharmacolibrary-dev-vm.git
   cd pharmacolibrary-dev-vm
   powershell -ExecutionPolicy Bypass -File windows\setup.ps1
   ```

   If WSL is not installed yet, the script installs it and asks you to restart Windows. Run it again after the restart.

2. The script then:
   1. writes `windows\wslconfig` to `%USERPROFILE%\.wslconfig` (memory limits; an existing file is backed up first);
   2. writes `windows\Ubuntu-24.04.user-data` to `%USERPROFILE%\.cloud-init\`, so the distro's first boot creates your Linux user and turns systemd on;
   3. installs the `Ubuntu-24.04` distro and asks for a password for the Linux user;
   4. copies your Windows SSH key into the Linux user's `~/.ssh` and checks that GitHub accepts it;
   5. runs `bootstrap-dbs.sh` in the distro with the GROBID CRF image and 2 GB for GROBID (`--with-grobid --grobid-image lfoppiano/grobid:0.9.0-crf --grobid-mem 2g`).

   Options: `-WithOmc` (OpenModelica image, several GB of disk), `-WithWasm` (Bodylight.js-FMU-Compiler), `-LinuxUser name`, `-NoCopySshKey` (generate a new key in WSL instead of copying the Windows one), `-WithDemoCorpus` (Zenodo knowledge base and full texts of the 12 demo drugs only, 0.65 GB on disk), `-WithCorpus` / `-WithNcCorpus` (the Zenodo full-text corpora, 20–40 GB each: the WSL disk grows by that much), `-NoKnowledgebase` (skip the Zenodo download).

3. Open the environment with `wsl -d Ubuntu-24.04`, or in VS Code with the WSL extension: `code ~/pharmacolibrary-dev` from the Ubuntu shell.

The script skips steps already done, so running it again is safe, as `vagrant provision` is.

### Working in WSL

- Keep the repositories and the knowledge base in the Linux filesystem (`~/…`). Files under `/mnt/c` are about ten times slower to read, treat names that differ only in case as the same file, and break the knowledge base's view symlinks.
- On 8 GB, run one pipeline group at a time and start GROBID (`scripts/run_grobid.sh`) only when you need it. LLM calls go to remote services, so no local model runs.
- `.wslconfig` applies to every WSL distro and only after `wsl --shutdown`.

### Remove

```powershell
wsl --unregister Ubuntu-24.04
```

This deletes the distro and everything stored in it, including uncommitted work in the cloned repositories. Push your changes first.
