# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Purpose

Vagrant setup for a Pharmacolibrary development VM. It contains no application code. It provisions a VirtualBox VM and clones the actual project repos from the `digital-biosystems` GitHub org:

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
- **bootstrap.sh**: runs as root during provisioning. It adds a 4 GB swapfile, copies `/vagrant/id_rsa*` (the SSH keys in this dir, which are registered with GitHub) into `/home/vagrant/.ssh`, pins GitHub's host key, installs git, then clones the three repos over SSH as the `vagrant` user.
- The Vagrantfile has a commented-out `bootstrap_sw.sh` provisioner, but that file does not exist in this repo.

## Gotchas

- `id_rsa`, `id_rsa_strong` and their `.pub` files are real private/public keys that provisioning needs. Never commit them, print them, or move them. `.gitignore` excludes `id_rsa*`; keep it that way.
- bootstrap.sh runs as root, so `$HOME` is `/root`. Always use explicit `/home/vagrant` paths, and run git as `sudo -u vagrant -H`. Clones go to `/home/vagrant/<repo>`, owned by `vagrant:vagrant`.
- GitHub's ed25519 host key is pinned in `/home/vagrant/.ssh/known_hosts` so the clones never prompt. If GitHub rotates that key, update it here.
- `{storage_dir}.webdav` files (gitignored) each hold an ownCloud share link `https://host[/path]/index.php/s/<secret>`. bootstrap.sh turns each one into a davfs2 mount at `/mnt/{storage_dir}`: an `add_header X-Requested-With XMLHttpRequest` section in `/etc/davfs2/davfs2.conf`, a line in `/etc/davfs2/secrets` (`<secret>` as user, `null` as password) and an `/etc/fstab` entry pointing at `https://host[/path]/public.php/webdav/`. Secrets are keyed by mount point, not URL, because several shares on one server have the same WebDAV URL. Never print or log the secret.
- bootstrap.sh is idempotent: re-running `vagrant provision` skips steps already done (swapfile, known_hosts entry, clones, WebDAV config). Keep new steps that way.
