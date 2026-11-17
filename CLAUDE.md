# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Purpose

Setup for a Pharmacolibrary development environment: a VirtualBox VM (Vagrant) or, on 8 GB Windows 11 machines, WSL2 (`windows/setup.ps1`). It contains no application code. Both clone the actual project repos from the `digital-biosystems` GitHub org:

- `pharmacolibrary-dev` (private)
- `dbs-components-dev` (private)
- `pharmacolibrary-docs` (public)

## Commands

```bash
vagrant up                 # create + provision VM (runs bootstrap.sh on first boot)
vagrant provision          # re-run bootstrap.sh on existing VM
vagrant ssh                # shell into VM
vagrant halt / destroy     # stop / delete VM
```

There is no build, lint, or test step in this repo.

## How it fits together

- **Vagrantfile**: base box is `westlife-eu/openmodelica1.25`, so OpenModelica comes from the box and bootstrap does not install it. The VM has 8 GB RAM, 4 CPUs and the VirtualBox GUI on. Forwarded ports: guest 80 to host 8080, plus 4000 and 9000 (auto_correct may remap them on conflict). `../../..` (three levels above this dir on the host) syncs to `/vagrant_data`. This dir syncs to `/vagrant` by Vagrant's default.
- **bootstrap.sh**: VirtualBox VM only. Runs as root during provisioning. It adds a 4 GB swapfile, copies `/vagrant/id_rsa*` (the SSH keys in this dir, which are registered with GitHub) into `/home/vagrant/.ssh` and mounts the WebDAV storages.
- **bootstrap-dbs.sh**: the project setup, shared by the VM and WSL; nothing in it may be specific to VirtualBox or WSL. Runs as root with `--user NAME`. It installs git, pins GitHub's host key, clones the three repos over SSH as that user, creates `~/venv` from `pharmacolibrary-dev/requirements.txt`, installs Docker Engine and downloads the Zenodo datasets (research by default; `--with-corpus`, `--with-nc-corpus`, `--with-demo-corpus`; `--no-kb`; the demo mode runs each archive through `zenodo_extract_demo` and unpacks only the `DEMO_DRUGS` folders: a plain `.tar` by HTTP Range (MANIFEST.csv lists the members in tar order, so offsets are computed: 512-byte header, data padded to 512, plus a pax header block for a non-ASCII or over-100-character path; the sum equals the real size of all 10 corpus shards, and every member name and file SHA-256 is checked), a `.tar.gz` or a shard whose offsets do not fit streamed whole with an MD5 check; MANIFEST.csv `link_to` finds the hard-link targets that belong to other drugs, which are spooled and copied; its marker is `<archive>.demo-<hash of the drug list>.done`) into `--kb-dir` (default `~/knowledgebase`), verifies each archive's MD5, unpacks and deletes it (marker `.zenodo/<label>/<file>.done` makes a rerun skip it), and merges `"knowledgebase"` into `~/pharmacolibrary-dev/pharmacolibrary.local.json`, and writes `~/.pharmacolibrary_env` (sourced from `~/.bashrc`). The record ids (24119263 research, 24125755 corpus, 24133749 non-commercial corpus) are variables at its top (`ZENODO_*_ID`); a record that is still a draft answers 404 and is skipped. The Vagrantfile runs it as a second provisioner with `--user vagrant`.
- **windows/setup.ps1**: the Windows counterpart of `vagrant up`. It writes `windows/wslconfig` to `%USERPROFILE%\.wslconfig` and `windows/Ubuntu-24.04.user-data` (cloud-init, `__WSL_USER__` replaced) to `%USERPROFILE%\.cloud-init\`, installs the Ubuntu-24.04 distro, copies the Windows SSH key into WSL, and runs `bootstrap-dbs.sh` as root, CRs stripped. It has not been run on Windows yet.
- **.gitattributes** keeps `*.sh`, `*.user-data` and the Vagrantfile LF: Git for Windows would otherwise check them out with CRLF, which bash and cloud-init reject.
- The Vagrantfile has a commented-out `bootstrap_sw.sh` provisioner, but that file does not exist in this repo.

## Gotchas

- `id_rsa`, `id_rsa_strong` and their `.pub` files are real private/public keys that provisioning needs. Never commit them, print them, or move them. `.gitignore` excludes `id_rsa*`; keep it that way.
- bootstrap.sh and bootstrap-dbs.sh run as root, so `$HOME` is `/root`. bootstrap.sh uses explicit `/home/vagrant` paths; bootstrap-dbs.sh takes the home of `--user` and runs git and pip as that user (`sudo -u NAME -H`). Clones go to `<home>/<repo>`, owned by that user.
- GitHub's ed25519 host key is pinned by bootstrap-dbs.sh in the user's `~/.ssh/known_hosts` so the clones never prompt. If GitHub rotates that key, update it there.
- `{storage_dir}.webdav` files (gitignored) each hold an ownCloud share link `https://host[/path]/index.php/s/<secret>`. bootstrap.sh turns each one into a davfs2 mount at `/mnt/{storage_dir}`: an `add_header X-Requested-With XMLHttpRequest` section in `/etc/davfs2/davfs2.conf`, a line in `/etc/davfs2/secrets` (`<secret>` as user, `null` as password) and an `/etc/fstab` entry pointing at `https://host[/path]/public.php/webdav/`. Secrets are keyed by mount point, not URL, because several shares on one server have the same WebDAV URL. Never print or log the secret.
- bootstrap.sh, bootstrap-dbs.sh and setup.ps1 are idempotent: re-running skips steps already done (swapfile, known_hosts entry, clones, venv, Docker, WebDAV config, distro, user). Keep new steps that way.
