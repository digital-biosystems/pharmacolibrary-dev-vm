# Pharmacolibrary dev VM

Two ways to set up the same development environment:

1. **WSL2 on Windows 11**: a minimal Ubuntu 24.04 distro that shares resources with Windows. For machines with 8 GB RAM.
2. **Vagrant + VirtualBox**: an isolated Ubuntu desktop VM with 8 GB RAM, on any host OS. Needs a host with 16 GB or more.

Both clone the `digital-biosystems` repositories `pharmacolibrary-dev`, `dbs-components-dev` (both private), `pharmacolibrary-docs` and `Pharmacolibrary` (public) and set up a Python venv, Docker Engine and the Zenodo knowledge base (see [Provisioning](#provisioning)).

## User configuration and keys

All per-user configuration lives in `~/.config/pharmacolibrary` (mode 700, files 600), never in a repository. That covers the API keys (e-INFRA CZ, OpenAI, Ollama, NCBI, Semantic Scholar), the Neo4j password, the Zenodo token, `zenodo-links.txt` and `dashboard/resources.yaml`. [`config-template/`](config-template/README.md) lists the files and has an `.example` for each. On Windows, keep them in `%USERPROFILE%\.config\pharmacolibrary`: `setup.ps1` copies that folder into WSL, and if the folder is missing it creates it from the template. In the VM, put them in `~/.config/pharmacolibrary` inside the VM.

## Option 1: WSL2

The `ubuntu-base` 24.04 root filesystem (not the Microsoft Store Ubuntu) is imported as the distro `Pharmacolibrary`, limited to 5 GB RAM, 6 GB swap and 4 CPUs (`windows/wslconfig`). Docker Engine runs inside it, so Docker Desktop is not needed. GROBID, OpenModelica and the FMU compiler run in Docker.

### Requirements

- Windows 11, with virtualisation enabled in the firmware.
- [Git for Windows](https://git-scm.com/download/win), or this repository as a ZIP.
- An SSH key registered on GitHub with access to the private repositories, as `%USERPROFILE%\.ssh\id_ed25519` or `id_rsa`. If there is none, the script generates a key in WSL and waits while you register it.

### Install

```powershell
mkdir $HOME\Projects -Force; cd $HOME\Projects
git clone git@github.com:digital-biosystems/pharmacolibrary-dev-vm.git
cd pharmacolibrary-dev-vm
windows\setup.cmd
```

`setup.cmd` runs `setup.ps1` with `-ExecutionPolicy Bypass`, because Windows blocks a `.ps1` started directly. If WSL is missing, the script installs it and asks for a restart; run it again after the restart. Re-running it is safe: steps that are already done are skipped.

The script:

1. copies `windows\wslconfig` to `%USERPROFILE%\.wslconfig` and backs up an existing file;
2. downloads the newest `ubuntu-base-24.04.x` image from `cdimage.ubuntu.com`, checks its SHA-256 and imports it into `%LOCALAPPDATA%\Pharmacolibrary\wsl`;
3. creates your Linux user (it asks for a password) and writes `/etc/wsl.conf`: `systemd=false`, Docker started at boot, `[automount] options="metadata,case=dir"`;
4. links `~/Projects` to `%USERPROFILE%\Projects` and copies the SSH key and `%USERPROFILE%\.config\pharmacolibrary` into WSL. Only files that WSL lacks are copied; a file that differs is reported, not overwritten;
5. runs `bootstrap-dbs.sh --projects-dir ~/Projects --kb-dir ~/Projects/knowledgebase --with-wasm --with-demo-corpus --grobid-image lfoppiano/grobid:0.9.0-crf --grobid-mem 2g`.

Options:

| Option | Effect |
|---|---|
| `-WithCorpus` | the whole redistributable corpus (about 43 GB) instead of the demo drugs |
| `-WithNcCorpus` | also the non-commercial corpus (about 20 GB; its licence terms apply) |
| `-NoKnowledgebase` | no Zenodo download |
| `-ZenodoLinks FILE` | share links for unpublished Zenodo drafts (default: the first `zenodo-links.txt` in `%USERPROFILE%\.config\pharmacolibrary`, this repo or `windows\`) |
| `-ProjectsDir DIR` | another Windows folder instead of `%USERPROFILE%\Projects` |
| `-LinuxUser NAME`, `-Distro NAME` | user and distro name |

Open a shell with `wsl -d Pharmacolibrary`. To use VS Code with the WSL extension, run `code ~/Projects/pharmacolibrary-dev` from that shell.

### Layout

Everything except the venv lives in `%USERPROFILE%\Projects`, which Linux sees as `~/Projects` (a symlink to `/mnt/c/Users/<you>/Projects`):

| Folder in `Projects` | Contents |
|---|---|
| `pharmacolibrary-dev-vm` | this repository |
| `pharmacolibrary-dev` | the pipeline |
| `pharmacolibrary-docs` | the docs site, written by `docs.build` |
| `Pharmacolibrary` | the Modelica library (`PHARMACOLIBRARY_MO`) |
| `dbs-components-dev`, `Bodylight.js-FMU-Compiler` | components, FMU compiler |
| `knowledgebase` | the knowledge base |

`~/venv` and `~/.pharmacolibrary_env` live inside Linux only.

### Notes

- Linux reads the Windows disk slowly, especially many small files, which is why the venv stays in Linux. If your organisation allows it, a Defender exclusion for `%USERPROFILE%\Projects\knowledgebase` speeds things up.
- Directories created from Linux are case-sensitive, and the knowledge base needs that. Create knowledge-base folders from Linux, not from Explorer.
- Run git from Linux, not Git for Windows: the two handle line endings and file modes differently.
- On 8 GB, run one pipeline group at a time and start GROBID (`scripts/run_grobid.sh`) only when you need it.
- There is no systemd: start Docker by hand with `sudo service docker start`. `RUN_LOGGED_INHIBIT=0`, so no sleep lock is held; set the Windows power plan if a long run must not be interrupted by sleep.
- `.wslconfig` applies to all distros and takes effect only after `wsl --shutdown`.

### Remove

```powershell
wsl --unregister Pharmacolibrary
```

This deletes the distro: the Linux user, the venv and the Docker images. `%USERPROFILE%\Projects` is kept. You can also delete `%LOCALAPPDATA%\Pharmacolibrary`, which holds the downloaded image.

## Option 2: Vagrant + VirtualBox

Base box `westlife-eu/openmodelica1.25` (OpenModelica preinstalled), with 8 GB RAM, 4 CPUs and the GUI enabled. Forwarded ports (guest → host): 80 → 8080, 4000 → 4000, 9000 → 9000. This directory is shared as `/vagrant` and `../../..` as `/vagrant_data`.

### Requirements

[VirtualBox](https://www.virtualbox.org/wiki/Downloads) and [Vagrant](https://developer.hashicorp.com/vagrant/install). On Ubuntu/Debian:

```bash
sudo apt update && sudo apt install virtualbox
wget -O - https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install vagrant
```

### Install

1. Copy your SSH key pair, registered on GitHub with access to the private repositories, into this directory as `id_rsa` and `id_rsa.pub`. `.gitignore` excludes them; never commit them.
2. Run `vagrant up`. The first run downloads the base box.
3. Use the VirtualBox desktop or `vagrant ssh`.

`vagrant provision` re-runs the provisioning, which is safe to repeat. `vagrant destroy` deletes the VM and everything in it, so push your work first. `vagrant box remove westlife-eu/openmodelica1.25` also deletes the cached box.

## Provisioning

- `bootstrap.sh` (VM only): adds a 4 GB swapfile, copies `id_rsa*` to `/home/vagrant/.ssh`, and mounts each ownCloud share configured in a `{storage_dir}.webdav` file to `/mnt/{storage_dir}`. Each such file is one line, `https://host/index.php/s/<secret>`. `.gitignore` excludes these files; never commit them.
- `bootstrap-dbs.sh` (VM and WSL): clones the repositories into `--projects-dir`, creates `~/venv` from `pharmacolibrary-dev/requirements.txt`, installs Docker Engine, writes `~/.pharmacolibrary_env` (sourced from `~/.bashrc`), and installs the knowledge base. The script header lists all options.

### Knowledge base

The Zenodo datasets are unpacked into `--kb-dir` (default `~/knowledgebase`), which is then set as `"knowledgebase"` in `pharmacolibrary-dev/pharmacolibrary.local.json`. Each archive is MD5-checked, unpacked and deleted, and a rerun resumes where it stopped.

| Flag | Dataset |
|---|---|
| (default) | research, record 24119263: per-drug records, provenance, models (0.5 GB packed, 2.3 GB unpacked) |
| `--with-corpus` | + redistributable full-text corpus, record 24125755 (about 43 GB of disk) |
| `--with-demo-corpus` | research + the corpus files of the 12 `ddd`/`dku` panel drugs only (`DEMO_DRUGS`): about 1.1 GB downloaded, 0.7 GB unpacked; not combinable with `--with-corpus` |
| `--with-nc-corpus` | + non-commercial corpus, record 24133749 (its licence terms apply) |
| `--no-kb` | nothing |

`--with-demo-corpus` fetches only the needed byte ranges of the plain `.tar` shards and checks each file against the SHA-256 in `MANIFEST.csv`. The research `.tar.gz` is streamed whole. Keep `DEMO_DRUGS` in step with the panels in `pharmacolibrary-dev`.

Records that are not yet published are skipped with a warning. To download one anyway:

- **Owner:** put the token in `~/.config/pharmacolibrary/zenodo_access_token`, which is used automatically, or pass `--zenodo-token-file FILE`. The token is sent only for records that are not public.
- **Everyone else:** use a share link (on Zenodo: *Share* → *Get a link*, *Can preview*). Put one link per line (`https://zenodo.org/records/ID?preview=1&token=…` or `ID TOKEN`) in `~/.config/pharmacolibrary/zenodo-links.txt`, or pass `--zenodo-links-file FILE`. `bootstrap-dbs.sh` also accepts the file next to itself, and `setup.ps1` also accepts it in this repo or `windows\`; there it is gitignored.

In the VM, pass `--no-kb` in the `Vagrantfile` if you use the `/vagrant_data` share instead.
