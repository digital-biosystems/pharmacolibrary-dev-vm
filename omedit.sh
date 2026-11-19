#!/usr/bin/env bash
# omedit.sh - start OMEdit with the Pharmacolibrary Modelica library loaded.
#
#   omedit.sh [-n] [FILE.mo ...]
#
#   FILE.mo   further files to open (relative paths are fine)
#   -n        print the command instead of running it
#
# Uses the installed OMEdit (the Vagrant box has one). Without it (WSL), OMEdit runs in the
# OpenModelica image $PK_OMC_DOCKER (default openmodelica/openmodelica:v1.26.3-gui; the first
# start pulls it, several GB), shown through WSLg or the X server in $DISPLAY. The container
# runs as you, with your home and the folders of the opened files mounted, so ~/.openmodelica
# keeps the settings and saved files land where they belong. The image has no Modelica
# libraries, so the first start installs the MSL into ~/.openmodelica/libraries.
# The library: $PHARMACOLIBRARY_MO, else ~/Projects/Pharmacolibrary/Pharmacolibrary/package.mo.
set -euo pipefail

DRY=0
if [ "${1:-}" = "-n" ]; then DRY=1; shift; fi
[ -f "$HOME/.pharmacolibrary_env" ] && . "$HOME/.pharmacolibrary_env"
LIB="${PHARMACOLIBRARY_MO:-$HOME/Projects/Pharmacolibrary/Pharmacolibrary/package.mo}"
IMAGE="${PK_OMC_DOCKER:-openmodelica/openmodelica:v1.26.3-gui}"

files=()
for f in "$LIB" "$@"; do
  if [ ! -f "$f" ]; then echo "omedit.sh: $f not found" >&2; exit 2; fi
  files+=("$(realpath "$f")")
done

run() {
  if [ "$DRY" -eq 1 ]; then printf '%q ' "$@"; echo; else "$@"; fi
}

if command -v OMEdit >/dev/null 2>&1; then
  if [ "$DRY" -eq 1 ]; then run OMEdit "${files[@]}"; exit 0; fi
  nohup OMEdit "${files[@]}" >/dev/null 2>&1 &
  exit 0
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "omedit.sh: neither OMEdit nor docker is installed" >&2; exit 1
fi
if [ "$DRY" -eq 0 ] && ! docker info >/dev/null 2>&1; then
  echo "omedit.sh: Docker is not running; start it with: sudo service docker start" >&2; exit 1
fi
if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
  echo "omedit.sh: no display (DISPLAY is empty); in WSL run: wsl --update, then wsl --shutdown" >&2; exit 1
fi

# mount the home and each opened file's folder (~/Projects is a symlink to /mnt/c/... in WSL)
args=(--rm -d --init --user "$(id -u):$(id -g)" -e HOME="$HOME" -v "$HOME:$HOME"
      -w "$(dirname "${files[0]}")" -e QT_X11_NO_MITSHM=1)
# the library: its repository folder, so the whole package can be edited and saved
mounted=("$HOME")
for d in "$(dirname "$(dirname "${files[0]}")")" "${files[@]:1}"; do
  [ -d "$d" ] || d="$(dirname "$d")"
  covered=0
  for m in "${mounted[@]}"; do case "$d/" in "$m"/*) covered=1 ;; esac; done
  [ "$covered" -eq 1 ] && continue
  args+=(-v "$d:$d"); mounted+=("$d")
done
# display: WSLg (X11 and Wayland), else the local X server
if [ -n "${DISPLAY:-}" ]; then args+=(-e DISPLAY="$DISPLAY" -v /tmp/.X11-unix:/tmp/.X11-unix); fi
if [ -d /mnt/wslg ]; then
  args+=(-v /mnt/wslg:/mnt/wslg -e XDG_RUNTIME_DIR=/mnt/wslg/runtime-dir
         -e WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}" -e PULSE_SERVER=/mnt/wslg/PulseServer)
fi

# The image has no Modelica libraries; OMEdit and omc read ~/.openmodelica/libraries. Install
# the MSL that Pharmacolibrary uses (4.0.0; omc takes the newest compatible one) when missing.
if [ "$DRY" -eq 0 ] && ! compgen -G "$HOME/.openmodelica/libraries/Modelica [0-9]*" >/dev/null; then
  echo "installing the Modelica Standard Library into ~/.openmodelica/libraries (once)"
  mos="$(mktemp -p "$HOME" .msl-XXXXXX.mos)"
  echo 'installPackage(Modelica, "4.0.0", exactMatch=false); getErrorString();' > "$mos"
  docker run --rm --user "$(id -u):$(id -g)" -e HOME="$HOME" -v "$HOME:$HOME" -w "$HOME" \
    --entrypoint omc "$IMAGE" "$mos" || echo "omedit.sh: WARNING: installing the MSL failed" >&2
  rm -f "$mos"
fi

[ "$DRY" -eq 1 ] || echo "starting OMEdit in $IMAGE (the first start pulls the image)"
run docker run "${args[@]}" "$IMAGE" OMEdit "${files[@]}"
