apt-get update
# add swap - each step skipped if already done, so re-provision is safe
if [ ! -f /swapfile ]; then
  fallocate -l 4G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
fi
swapon --show=NAME --noheadings | grep -qxF /swapfile || swapon /swapfile
grep -qxF '/swapfile none swap sw 0 0' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab

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

# mount webdav storages - each /vagrant/{storage_dir}.webdav holds an owncloud
# public share link https://host[/path]/index.php/s/{secret}, mounted to /mnt/{storage_dir}
DEBIAN_FRONTEND=noninteractive apt-get -y install davfs2
VAGRANT_UID=$(id -u vagrant)
VAGRANT_GID=$(id -g vagrant)
touch /etc/davfs2/secrets
chmod 600 /etc/davfs2/secrets
for webdav_file in /vagrant/*.webdav; do
  [ -f "$webdav_file" ] || continue
  storage_dir=$(basename "$webdav_file" .webdav)
  mount_point="/mnt/$storage_dir"
  share_url=$(head -n 1 "$webdav_file" | tr -d '[:space:]')
  case "$share_url" in
    http*://*/s/?*) ;;
    *) echo "$webdav_file: expected share link .../s/{secret}, skipping"; continue ;;
  esac
  secret=${share_url##*/s/}
  secret=${secret%%[/?#]*}
  base_url=${share_url%%/s/*}
  base_url=${base_url%/index.php}
  dav_url="$base_url/public.php/webdav/"

  mkdir -p "$mount_point"

  # owncloud public webdav requires this header
  grep -qxF "[$mount_point]" /etc/davfs2/davfs2.conf || printf '\n[%s]\nadd_header X-Requested-With XMLHttpRequest\n' "$mount_point" >> /etc/davfs2/davfs2.conf

  # secrets keyed by mount point - several shares on one server share the same dav url
  sed -i "\#^$mount_point #d" /etc/davfs2/secrets
  echo "$mount_point \"$secret\" \"null\"" >> /etc/davfs2/secrets

  # fstab entry - mounted again after VM restart
  sed -i "\# $mount_point davfs #d" /etc/fstab
  echo "$dav_url $mount_point davfs rw,uid=$VAGRANT_UID,gid=$VAGRANT_GID,_netdev,auto 0 0" >> /etc/fstab

  mountpoint -q "$mount_point" || mount "$mount_point"
done
