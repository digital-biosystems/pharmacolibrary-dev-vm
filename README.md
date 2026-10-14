# Pharmacolibrary dev VM

Vagrant setup for a Pharmacolibrary development virtual machine. `vagrant up` creates a VirtualBox VM from the `westlife-eu/openmodelica1.25` box, which comes with OpenModelica installed. Provisioning (`bootstrap.sh`) then:

- adds a 4 GB swapfile
- installs git
- clones the `digital-biosystems` repositories over SSH into `/home/vagrant`, owned by the `vagrant` user:
  - `pharmacolibrary-dev` (private)
  - `dbs-components-dev` (private)
  - `pharmacolibrary-docs` (public)

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

2. Create and provision the VM:

   ```bash
   vagrant up
   ```

   The first run downloads the base box, so it takes a while. A VirtualBox window opens with the VM's desktop.

3. Open a shell in the VM:

   ```bash
   vagrant ssh
   ```

## Remove

Stop the VM and delete it:

```bash
vagrant destroy
```

This removes the VM and everything stored inside it, including uncommitted work in the cloned repositories. Push your changes first. The downloaded base box stays cached; to delete it as well, run `vagrant box remove westlife-eu/openmodelica1.25`.
