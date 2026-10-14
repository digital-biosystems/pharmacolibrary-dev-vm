apt-get update
# add swap
fallocate -l 4G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab

# provisioning runs as root - set up ssh and clones for vagrant user explicitly
VAGRANT_HOME=/home/vagrant
SSH_DIR="$VAGRANT_HOME/.ssh"

# copy id rsa keys - registered for git/github
mkdir -p "$SSH_DIR"
cp /vagrant/id_rsa* "$SSH_DIR"
chmod 700 "$SSH_DIR"
chmod 600 "$SSH_DIR"/id_rsa*

# trust github host key - avoids interactive prompt on first clone
touch "$SSH_DIR/known_hosts"
chmod 600 "$SSH_DIR/known_hosts"
GITHUB_HOST_KEY='github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl'
grep -qxF "$GITHUB_HOST_KEY" "$SSH_DIR/known_hosts" || echo "$GITHUB_HOST_KEY" >> "$SSH_DIR/known_hosts"
chown -R vagrant:vagrant "$SSH_DIR"

# git clone repos as vagrant user into its home
apt-get -y install git
clone() {
  local dir="$VAGRANT_HOME/$(basename "$1" .git)"
  if [ -d "$dir" ]; then
    echo "$dir exists, skipping clone"
  else
    sudo -u vagrant -H git -C "$VAGRANT_HOME" clone "$1"
  fi
}

# private repos
clone git@github.com:digital-biosystems/pharmacolibrary-dev.git
clone git@github.com:digital-biosystems/dbs-components-dev.git

# public repos
clone git@github.com:digital-biosystems/pharmacolibrary-docs.git
