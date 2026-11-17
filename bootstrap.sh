# VirtualBox VM only: swap, SSH keys from this directory, WebDAV mounts.
# The project setup (repos, venv, Docker) is bootstrap-dbs.sh, which the Vagrantfile runs next
# and windows/setup.ps1 runs in WSL.

apt-get update
# add swap - each step skipped if already done, so re-provision is safe
if [ ! -f /swapfile ]; then
  fallocate -l 4G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
fi
swapon --show=NAME --noheadings | grep -qxF /swapfile || swapon /swapfile
grep -qxF '/swapfile none swap sw 0 0' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab

# provisioning runs as root - set up ssh for the vagrant user explicitly
VAGRANT_HOME=/home/vagrant
SSH_DIR="$VAGRANT_HOME/.ssh"

# copy id rsa keys - registered for git/github; bootstrap-dbs.sh clones with them
mkdir -p "$SSH_DIR"
cp /vagrant/id_rsa* "$SSH_DIR"
chmod 700 "$SSH_DIR"
chmod 600 "$SSH_DIR"/id_rsa*
chown -R vagrant:vagrant "$SSH_DIR"

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
