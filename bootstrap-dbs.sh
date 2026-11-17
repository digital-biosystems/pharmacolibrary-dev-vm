#!/usr/bin/env bash
# bootstrap-dbs.sh - Pharmacolibrary project setup, shared by the Vagrant VM and Windows (WSL2).
#
# Runs as root. Installs what the project needs and clones the digital-biosystems repositories
# into the home of the given user. It contains nothing specific to VirtualBox or WSL:
#   Vagrant: the Vagrantfile runs it after bootstrap.sh       (--user vagrant)
#   Windows: windows/setup.ps1 runs it inside the WSL distro  (--user <WSL user>)
#
# Every step is skipped when already done, so running it again is safe.
#
#   bash bootstrap-dbs.sh --user NAME [--no-docker] [--no-venv]
#                         [--with-grobid] [--with-omc] [--with-wasm]
#                         [--grobid-image IMAGE] [--grobid-mem SIZE]
#                         [--no-kb] [--kb-dir DIR] [--with-corpus | --with-demo-corpus]
#                         [--with-nc-corpus]
#                         [--zenodo-token-file FILE]
#
#   --user NAME          owner of the clones, venv and settings (required)
#   --no-docker          skip Docker Engine (GROBID and omc run in Docker)
#   --no-venv            skip the Python venv in ~/venv
#   --with-grobid        pull the GROBID image now (else on first scripts/run_grobid.sh)
#   --with-omc           pull the OpenModelica image and set PK_OMC_DOCKER
#   --with-wasm          clone Bodylight.js-FMU-Compiler (browser simulator, export.fmu --wasm)
#   --grobid-image IMAGE GROBID image for scripts/run_grobid.sh (written to the env file)
#   --grobid-mem SIZE    GROBID container memory, e.g. 2g (written to the env file)
#   --no-kb              skip the Zenodo knowledge base (below)
#   --kb-dir DIR         where the knowledge base is unpacked (default ~/knowledgebase)
#   --with-corpus        also the redistributable source corpus (PDFs, TEI, text; ~40 GB)
#   --with-demo-corpus   the research dataset AND the redistributable corpus, but only the files of
#                        the ddd and dku panel drugs (12 drugs, ~0.65 GB unpacked); see below
#   --with-nc-corpus     also the non-commercial source corpus (~20 GB; licence terms apply)
#   --zenodo-token-file  Zenodo access token of the record owner, to fetch an unpublished draft
#
# Knowledge base: the public Zenodo datasets are downloaded, checked against Zenodo's MD5 and
# unpacked into --kb-dir, which is then set as "knowledgebase" in
# ~/pharmacolibrary-dev/pharmacolibrary.local.json (the setting the code reads):
#   research   always (unless --no-kb)   per-drug records, provenance, models, ~0.5 GB packed
#   corpus     --with-corpus             redistributable full texts
#   nc corpus  --with-nc-corpus          full texts allowed for non-commercial use only
# --with-demo-corpus: Zenodo serves whole files only, but a plain .tar can be read by byte range:
# the corpus shards are fetched in pieces (the 12 drugs' files and the files they hard-link to,
# ~0.6 GB of the 37 GB), checked against the manifest's SHA-256 and unpacked; if the offsets
# do not fit a shard it is streamed whole instead. The research archive is a .tar.gz, which
# cannot be read by range: it is streamed (0.5 GB). No archive is kept. DEMO_DRUGS lists the drugs.
# A record that is not public yet is skipped with a warning. Record ids: ZENODO_RESEARCH_ID,
# ZENODO_CORPUS_ID, ZENODO_NC_CORPUS_ID. Each archive is deleted after it is unpacked, so the
# disk needs the unpacked size plus the largest archive (4.3 GB); a rerun resumes.
#
# The SSH key that GitHub accepts for the private repositories must already be in
# ~NAME/.ssh. bootstrap.sh (VM) and setup.ps1 (Windows) put it there.
set -euo pipefail

TARGET_USER=""
WITH_DOCKER=1
WITH_VENV=1
WITH_GROBID=0
WITH_OMC=0
WITH_WASM=0
GROBID_IMAGE=""
GROBID_MEM=""
OMC_IMAGE="openmodelica/openmodelica:v1.26.3-gui"
WITH_KB=1
WITH_CORPUS=0
WITH_NC_CORPUS=0
WITH_DEMO=0
# the ddd + dku panels of pharmacolibrary-dev (pk_knowledge_scripts/paths.py: DRUGS_DDD, DRUGS_DKU);
# keep in step with them. Names, not slugs: drug_<name> is the folder.
DEMO_DRUGS="${DEMO_DRUGS:-metformin ibuprofen amoxicillin semaglutide tolvaptan allopurinol clopidogrel vancomycin tacrolimus busulfan infliximab posaconazole}"
KB_DIR=""
ZENODO_TOKEN_FILE=""
# the Zenodo records (https://doi.org/10.5281/zenodo.<id>)
ZENODO_RESEARCH_ID="${ZENODO_RESEARCH_ID:-24119263}"
ZENODO_CORPUS_ID="${ZENODO_CORPUS_ID:-24125755}"
ZENODO_NC_CORPUS_ID="${ZENODO_NC_CORPUS_ID:-24133749}"

while [ $# -gt 0 ]; do
  case "$1" in
    --user)         TARGET_USER="$2"; shift 2 ;;
    --no-docker)    WITH_DOCKER=0; shift ;;
    --no-venv)      WITH_VENV=0; shift ;;
    --with-grobid)  WITH_GROBID=1; shift ;;
    --with-omc)     WITH_OMC=1; shift ;;
    --with-wasm)    WITH_WASM=1; shift ;;
    --grobid-image) GROBID_IMAGE="$2"; shift 2 ;;
    --grobid-mem)   GROBID_MEM="$2"; shift 2 ;;
    --no-kb)        WITH_KB=0; shift ;;
    --kb-dir)       KB_DIR="$2"; shift 2 ;;
    --with-corpus)  WITH_CORPUS=1; shift ;;
    --with-nc-corpus) WITH_NC_CORPUS=1; shift ;;
    --with-demo-corpus) WITH_DEMO=1; shift ;;
    --zenodo-token-file) ZENODO_TOKEN_FILE="$2"; shift 2 ;;
    *) echo "bootstrap-dbs.sh: unknown option $1" >&2; exit 2 ;;
  esac
done

if [ "$(id -u)" -ne 0 ]; then
  echo "bootstrap-dbs.sh: run as root" >&2; exit 2
fi
if [ -z "$TARGET_USER" ] || ! id "$TARGET_USER" >/dev/null 2>&1; then
  echo "bootstrap-dbs.sh: --user must name an existing user (got '$TARGET_USER')" >&2; exit 2
fi
if [ "$WITH_KB" -eq 0 ] && { [ "$WITH_CORPUS" -eq 1 ] || [ "$WITH_NC_CORPUS" -eq 1 ]; }; then
  echo "bootstrap-dbs.sh: --with-corpus and --with-nc-corpus need the knowledge base (drop --no-kb)" >&2; exit 2
fi
if [ "$WITH_DEMO" -eq 1 ] && { [ "$WITH_KB" -eq 0 ] || [ "$WITH_CORPUS" -eq 1 ] || [ "$WITH_NC_CORPUS" -eq 1 ]; }; then
  echo "bootstrap-dbs.sh: --with-demo-corpus replaces --with-corpus and cannot be combined with --with-corpus, --with-nc-corpus or --no-kb" >&2; exit 2
fi
if [ "$WITH_DOCKER" -eq 0 ] && { [ "$WITH_GROBID" -eq 1 ] || [ "$WITH_OMC" -eq 1 ]; }; then
  echo "bootstrap-dbs.sh: --with-grobid and --with-omc need Docker (drop --no-docker)" >&2; exit 2
fi

# Runs as root, so $HOME is /root: always use the target user's home, and run git, pip and
# docker pulls as that user.
USER_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
SSH_DIR="$USER_HOME/.ssh"
[ -n "$KB_DIR" ] || KB_DIR="$USER_HOME/knowledgebase"
case "$KB_DIR" in /*) ;; *) KB_DIR="$USER_HOME/$KB_DIR" ;; esac     # relative: below the home
as_user() { sudo -u "$TARGET_USER" -H "$@"; }
log() { echo "[bootstrap-dbs] $*"; }

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get -y install git openssh-client sudo ca-certificates curl

# --- GitHub host key: pinned, so the first clone never prompts -------------------------------
# If GitHub rotates this key, update it here.
mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"
touch "$SSH_DIR/known_hosts"
chmod 600 "$SSH_DIR/known_hosts"
GITHUB_HOST_KEY='github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl'
grep -qxF "$GITHUB_HOST_KEY" "$SSH_DIR/known_hosts" || echo "$GITHUB_HOST_KEY" >> "$SSH_DIR/known_hosts"
chown -R "$TARGET_USER:" "$SSH_DIR"

# --- repositories ----------------------------------------------------------------------------
clone() {
  local dir="$USER_HOME/$(basename "$1" .git)"
  if [ -d "$dir" ]; then
    log "$dir exists, skipping clone"
  else
    as_user git -C "$USER_HOME" clone "$1"
  fi
}

# private repos
clone git@github.com:digital-biosystems/pharmacolibrary-dev.git
clone git@github.com:digital-biosystems/dbs-components-dev.git

# public repos
clone git@github.com:digital-biosystems/pharmacolibrary-docs.git

if [ "$WITH_WASM" -eq 1 ]; then
  # export.fmu --wasm compiles in this tool's pinned emsdk Docker image: no emsdk install here.
  clone https://github.com/creative-connections/Bodylight.js-FMU-Compiler.git
fi

# --- Python venv (~/venv, the path the project's docs and scripts use) -------------------------
if [ "$WITH_VENV" -eq 1 ]; then
  apt-get -y install python3 python3-venv python3-pip
  if [ ! -x "$USER_HOME/venv/bin/python" ]; then
    as_user python3 -m venv "$USER_HOME/venv"
  fi
  REQ="$USER_HOME/pharmacolibrary-dev/requirements.txt"
  if [ -f "$REQ" ]; then
    as_user "$USER_HOME/venv/bin/pip" install --upgrade pip
    # a failed install (e.g. a Python too old for a pinned package) must not stop the rest
    as_user "$USER_HOME/venv/bin/pip" install -r "$REQ" \
      || log "WARNING: pip install -r $REQ failed; fix and re-run: ~/venv/bin/pip install -r $REQ"
  else
    log "WARNING: $REQ not found (clone failed?); venv left empty"
  fi
fi

# --- Docker Engine (from Docker's apt repository, not Docker Desktop) ------------------------
if [ "$WITH_DOCKER" -eq 1 ]; then
  if ! command -v docker >/dev/null 2>&1; then
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
      > /etc/apt/sources.list.d/docker.list
    apt-get update
    apt-get -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  else
    log "docker already installed, skipping"
  fi
  getent group docker >/dev/null && usermod -aG docker "$TARGET_USER"
  # WSL needs systemd (the user-data file turns it on); a VM has it anyway
  if [ -d /run/systemd/system ]; then
    systemctl enable --now docker
  else
    log "WARNING: systemd is not running; start Docker with: sudo service docker start"
  fi
  # group membership applies to new logins only, so pull through sudo -g docker
  pull() { docker image inspect "$1" >/dev/null 2>&1 || sudo -u "$TARGET_USER" -g docker -H docker pull "$1"; }
  if [ "$WITH_GROBID" -eq 1 ]; then
    pull "${GROBID_IMAGE:-lfoppiano/grobid:0.9.0-crf}"
  fi
  if [ "$WITH_OMC" -eq 1 ]; then
    pull "$OMC_IMAGE"
  fi
fi

# --- knowledge base from the public Zenodo datasets -------------------------------------------
# Lists a record's files as TSV (name, bytes, md5, url); exit 4 when the record is not public.
zenodo_list() {   # <record id>
  python3 - "$1" "$ZENODO_TOKEN_FILE" <<'PY'
import json, sys, urllib.request, urllib.error
rid, tokfile = sys.argv[1], sys.argv[2]
token = open(tokfile).read().strip() if tokfile else ""
def get(url, auth):
    h = {"Accept": "application/json"}
    if auth:
        h["Authorization"] = "Bearer " + token
    with urllib.request.urlopen(urllib.request.Request(url, headers=h), timeout=60) as r:
        return json.load(r)
try:
    d = get(f"https://zenodo.org/api/records/{rid}", False)
    rows = [(f["key"], f["size"], f.get("checksum", ""), f["links"]["self"]) for f in d["files"]]
except urllib.error.HTTPError as e:
    if e.code not in (401, 403, 404):
        sys.exit(f"zenodo record {rid}: HTTP {e.code}")
    if not token:
        sys.exit(4)                     # not published (a draft answers 404 to everyone else)
    try:
        d = get(f"https://zenodo.org/api/deposit/depositions/{rid}", True)
    except urllib.error.HTTPError as e2:
        sys.exit(f"zenodo deposition {rid}: HTTP {e2.code}")
    rows = [(f["filename"], f["filesize"], f.get("checksum", ""), f["links"]["download"])
            for f in d["files"]]
for name, size, md5, url in rows:
    print(f"{name}\t{size}\t{md5.split(':')[-1]}\t{url}")
PY
}

# Unpacks ONLY the demo drugs' files of ONE archive (MANIFEST.csv says which and in what order).
# A plain .tar is read with HTTP Range requests: the manifest lists every member in tar order
# with its size, so each member's byte offset is computed (512-byte header, data padded to 512,
# plus a pax header block for a non-ASCII or over-100-character path; the sum was checked
# against the real size of all 10 corpus shards) and only the demo drugs' runs are fetched, plus
# the files they hard-link to. Every member name is checked against the manifest and every file
# against its SHA-256; if the offsets do not fit, or for a .tar.gz (not seekable), the whole
# archive is streamed instead and its MD5 checked. A file shared with another drug is a tar hard
# link to that drug's copy: the target is spooled, then copied to the demo drug's path.
# Exit: 0 done, 5 not enough disk, 6 checksum mismatch, 7 a file is missing, else failed.
zenodo_extract_demo() {   # <archive> <url> <md5> <MANIFEST.csv> <curl.cfg or ''> <spool dir> <bytes>
  as_user python3 - "$1" "$2" "$3" "$4" "$5" "$6" "$KB_DIR" "$DEMO_DRUGS" "$7" <<'PY'
import csv, hashlib, http.client, os, re, shutil, sys, tarfile, time, urllib.request
name, url, md5, manifest, cfg, spool, kb, drugs, asize = sys.argv[1:10]
asize = int(asize)
GAP = 4_000_000                         # runs closer than this are read as one
want = {"drug_" + re.sub(r"[^a-z0-9]+", "_", d.lower()) for d in drugs.split()}
with open(manifest, encoding="utf-8", newline="") as fh:
    rows = [r for r in csv.DictReader(fh) if r["archive"] == name]          # tar order
byp = {r["path"]: r for r in rows}
sel = {r["path"]: r for r in rows if r["drug"] in want}
if not sel:
    print(f"{name}: none of the demo drugs, not read"); sys.exit(0)
targets = {r["link_to"] for r in sel.values() if r["link_to"]}
need = sum(int(byp[p]["bytes"] or 0) for p in set(sel) | targets if not byp[p]["link_to"])
free = shutil.disk_usage(kb).free
if free < need * 1.2 + 50_000_000:
    print(f"{name}: needs about {need // 1_000_000} MB, {free // 1_000_000} MB free in {kb}")
    sys.exit(5)
token = ""
if cfg and os.path.exists(cfg):
    m = re.search(r'Bearer ([^"\s]+)', open(cfg).read())
    token = m.group(1) if m else ""

class Plan(Exception): pass             # the offsets do not fit: read everything instead
class Corrupt(Exception): pass          # a file does not match its SHA-256

class Stream:
    """A byte range (or all) of the archive as a file object; resumes after a drop."""
    def __init__(self, start=0, end=None):
        self.pos, self.end, self.h, self.r = start, end, hashlib.md5(), None
        self.partial = bool(start or end)
        self.open()
    def open(self):
        for attempt in range(8):
            h = {"Authorization": "Bearer " + token} if token else {}
            if self.pos or self.end is not None:
                h["Range"] = f"bytes={self.pos}-" + ("" if self.end is None else str(self.end - 1))
            try:
                self.r = urllib.request.urlopen(urllib.request.Request(url, headers=h), timeout=90)
                if "Range" in h and self.r.status != 206:
                    raise OSError(f"server ignored Range (HTTP {self.r.status})")
                return
            except OSError:
                time.sleep(5 * (attempt + 1))
        raise SystemExit(f"{name}: cannot open {url}")
    def read(self, n=1 << 20):
        if self.end is not None:
            n = min(n, self.end - self.pos)
            if n <= 0:
                return b""
        for attempt in range(8):
            try:
                b = self.r.read(n)
                break
            except (OSError, http.client.HTTPException):
                time.sleep(5 * (attempt + 1))
                self.open()
        else:
            raise SystemExit(f"{name}: connection lost at byte {self.pos}")
        self.h.update(b)
        self.pos += len(b)
        return b

kbn = os.path.normpath(kb) + os.sep
def dest(p):
    d = os.path.normpath(os.path.join(kb, p))
    if not d.startswith(kbn):
        raise SystemExit(f"{name}: unsafe member path {p!r}")
    return d
def write(tf, m, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    h, src = hashlib.sha256(), tf.extractfile(m)
    with open(path, "wb") as out:
        while True:
            b = src.read(1 << 20)
            if not b:
                break
            h.update(b); out.write(b)
    os.utime(path, (m.mtime, m.mtime))
    want_sha = (byp.get(m.name) or {}).get("sha256")
    if want_sha and h.hexdigest() != want_sha:
        raise Corrupt(f"{m.name}: SHA-256 {h.hexdigest()}, manifest says {want_sha}")

done, spooled = set(), {}
def take(tf, m):
    """One tar member: unpack it when it is a demo file or a hard-link target."""
    p = m.name
    if m.isreg():
        if p in sel:
            write(tf, m, dest(p)); done.add(p)
            if p in targets:
                spooled[p] = dest(p)
        elif p in targets:
            sp = os.path.join(spool, str(len(spooled)))
            write(tf, m, sp); spooled[p] = sp
    elif m.islnk() and p in sel:
        src = spooled.get(m.linkname)
        if src is None:
            return                              # reported below
        d = dest(p)
        os.makedirs(os.path.dirname(d), exist_ok=True)
        shutil.copyfile(src, d)
        os.utime(d, (m.mtime, m.mtime)); done.add(p)

def pax_len(recs):
    total = 0
    for k, v in recs:
        body = len(k.encode()) + len(v.encode()) + 3          # " k=v\n"
        n = len(str(body))
        while len(str(body + n)) != n:
            n += 1
        total += body + n
    return total
def pax_extra(path, link):
    recs = [(k, v) for k, v in (("path", path), ("linkpath", link))
            if v and (not v.isascii() or len(v) > 100)]
    return 512 + ((pax_len(recs) + 511) // 512) * 512 if recs else 0

def ranged():
    spans, off = [], 0
    for r in rows:
        size = 0 if r["link_to"] else int(r["bytes"] or 0)
        start = off
        off += pax_extra(r["path"], r["link_to"]) + 512 + ((size + 511) // 512) * 512
        spans.append((start, off))
    if ((off + 1024 + 10239) // 10240) * 10240 != asize:
        raise Plan(f"offsets add up to {off + 1024} bytes, the archive has {asize}")
    keep = [i for i, r in enumerate(rows) if r["path"] in sel or r["path"] in targets]
    runs = []                                    # [first row, last row]
    for i in keep:
        if runs and spans[i][0] - spans[runs[-1][1]][1] < GAP:
            runs[-1][1] = i
        else:
            runs.append([i, i])
    read = 0
    for a, b in runs:
        s = Stream(spans[a][0], spans[b][1])
        with tarfile.open(fileobj=s, mode="r|", bufsize=1 << 20) as tf:
            exp = iter(rows[a:b + 1])
            for m in tf:
                r = next(exp, None)
                if r is None or m.name != r["path"]:
                    raise Plan(f"member {m.name!r} where the manifest has {(r or {}).get('path')!r}")
                take(tf, m)
            if next(exp, None) is not None:
                raise Plan("the archive ends before the manifest does")
        read += s.pos - spans[a][0]
    return f"{len(runs)} byte ranges, {read // 1_000_000} MB read of {asize // 1_000_000} MB"

def streamed():
    s = Stream()
    with tarfile.open(fileobj=s, mode="r|*", bufsize=1 << 20) as tf:
        for m in tf:
            take(tf, m)
    while s.read():                              # the tar's end padding, for the MD5
        pass
    if md5 and s.h.hexdigest() != md5:
        raise Corrupt(f"MD5 {s.h.hexdigest()}, Zenodo says {md5}")
    return f"whole archive streamed, {s.pos // 1_000_000} MB read, MD5 ok"

os.makedirs(spool, exist_ok=True)
try:
    try:
        if not name.endswith(".tar"):
            raise Plan("a compressed archive cannot be read by range")
        how = ranged()
    except Plan as e:
        done.clear(); spooled.clear()
        print(f"{name}: {e}")
        how = streamed()
except Corrupt as e:
    print(f"{name}: {e}"); sys.exit(6)
finally:
    shutil.rmtree(spool, ignore_errors=True)
miss = sorted(set(sel) - done)
if miss:
    print(f"{name}: {len(miss)} of {len(sel)} demo files not found in the archive, e.g. {miss[0]}")
    sys.exit(7)
print(f"{name}: {len(done)} demo files unpacked ({how})")
PY
}

# Downloads, verifies and unpacks one record into $KB_DIR; demo=1: only the demo drugs' files.
# 0 = unpacked (or already was), 4 = not public, anything else = failed.
fetch_zenodo() {   # <label> <record id> <demo 0|1>
  local label="$1" rid="$2" demo="${3:-0}" meta="$KB_DIR/.zenodo/$1" tmp="$KB_DIR/.zenodo/tmp"
  local list name size md5 url need=0 big=0 free got cfg="" dh rc=0
  dh="$(printf '%s' "$DEMO_DRUGS" | tr ' ' '\n' | sort | tr '\n' ' ' | sha256sum | cut -c1-8)"
  list="$(zenodo_list "$rid")" || rc=$?
  if [ "$rc" -eq 4 ]; then return 4; fi
  if [ "$rc" -ne 0 ]; then return 1; fi
  as_user mkdir -p "$meta" "$tmp"
  if [ -n "$ZENODO_TOKEN_FILE" ]; then      # curl reads the token from a private file, not argv
    cfg="$KB_DIR/.zenodo/curl.cfg"
    printf 'header = "Authorization: Bearer %s"\n' "$(cat "$ZENODO_TOKEN_FILE")" | as_user tee "$cfg" >/dev/null
    chmod 600 "$cfg"
  fi
  # README, MANIFEST.csv, RELEASE.json, NOTICE, CITATION: kept beside the data (the demo needs MANIFEST.csv first)
  while IFS=$'\t' read -r name size md5 url; do
    [ -n "$name" ] || continue
    case "$name" in
      *.tar|*.tar.gz|*.tgz) ;;
      *) if [ ! -s "$meta/$name" ]; then
           as_user curl -fsSL ${cfg:+-K "$cfg"} -o "$meta/$name" "$url" || log "WARNING: could not fetch $label/$name"
         fi ;;
    esac
  done <<< "$list"
  if [ "$demo" -eq 1 ] && [ ! -s "$meta/MANIFEST.csv" ]; then
    log "ERROR: $label has no MANIFEST.csv, so the demo drugs' files cannot be found"; return 1
  fi
  if [ "$demo" -eq 0 ]; then
    while IFS=$'\t' read -r name size md5 url; do
      case "$name" in
        *.tar|*.tar.gz|*.tgz)
          if [ ! -e "$meta/$name.done" ]; then
            need=$((need + size))
            if [ "$size" -gt "$big" ]; then big="$size"; fi
          fi ;;
      esac
    done <<< "$list"
    free="$(df -P -B1 "$KB_DIR" | awk 'NR==2{print $4}')"
    if [ "$((need + big))" -gt "$free" ]; then
      log "ERROR: $label needs about $(( (need + big) / 1000000000 )) GB (unpacked plus the largest archive), $(( free / 1000000000 )) GB free in $KB_DIR"
      return 1
    fi
  fi
  while IFS=$'\t' read -r name size md5 url; do
    [ -n "$name" ] || continue
    case "$name" in
      *.tar|*.tar.gz|*.tgz) ;;
      *) continue ;;
    esac
    if [ -e "$meta/$name.done" ] || { [ "$demo" -eq 1 ] && [ -e "$meta/$name.demo-$dh.done" ]; }; then
      log "$label/$name: already unpacked"; continue
    fi
    if [ "$demo" -eq 1 ]; then
      log "$label/$name: unpacking only the demo drugs"
      rc=0
      zenodo_extract_demo "$name" "$url" "$md5" "$meta/MANIFEST.csv" "$cfg" "$KB_DIR/.zenodo/spool-$name" "$size" || rc=$?
      if [ "$rc" -ne 0 ]; then log "ERROR: $label/$name: demo unpacking failed (exit $rc)"; return 1; fi
      as_user touch "$meta/$name.demo-$dh.done"
    else
      log "$label/$name: downloading $((size / 1000000)) MB"
      as_user curl -fL --retry 5 --retry-delay 15 -C - ${cfg:+-K "$cfg"} -o "$tmp/$name" "$url" || return 1
      got="$(md5sum "$tmp/$name" | cut -d' ' -f1)"
      if [ -n "$md5" ] && [ "$got" != "$md5" ]; then
        log "ERROR: $label/$name: MD5 $got, Zenodo says $md5 — archive deleted, run again"
        as_user rm -f "$tmp/$name"
        return 1
      fi
      log "$label/$name: unpacking into $KB_DIR"
      as_user tar -xf "$tmp/$name" -C "$KB_DIR" || return 1
      as_user rm -f "$tmp/$name"
      as_user touch "$meta/$name.done"
    fi
  done <<< "$list"
  if [ -n "$cfg" ]; then as_user rm -f "$cfg"; fi
  return 0
}

if [ "$WITH_KB" -eq 1 ]; then
  apt-get -y install python3 curl tar coreutils
  as_user mkdir -p "$KB_DIR"
  loaded=0
  for entry in "research:$ZENODO_RESEARCH_ID:1:$WITH_DEMO" \
               "corpus:$ZENODO_CORPUS_ID:$(( WITH_CORPUS || WITH_DEMO )):$WITH_DEMO" \
               "nc-corpus:$ZENODO_NC_CORPUS_ID:$WITH_NC_CORPUS:0"; do
    IFS=: read -r label rid want demo <<< "$entry"
    if [ "$want" -ne 1 ]; then continue; fi
    rc=0
    fetch_zenodo "$label" "$rid" "$demo" || rc=$?
    case "$rc" in
      0) loaded=1 ;;
      4) log "WARNING: Zenodo record $rid ($label) is not public yet — skipped (https://doi.org/10.5281/zenodo.$rid). The owner can pass --zenodo-token-file." ;;
      *) log "WARNING: $label did not finish; run this script again to resume" ;;
    esac
  done
  # Point the code at it: "knowledgebase" in the untracked pharmacolibrary.local.json, keeping
  # its other settings (e.g. the graph URI). Only once some data is there.
  CONF="$USER_HOME/pharmacolibrary-dev/pharmacolibrary.local.json"
  if [ "$loaded" -eq 1 ] || ls "$KB_DIR"/.zenodo/*/*.done >/dev/null 2>&1; then
    python3 - "$CONF" "$KB_DIR" <<'PY'
import json, os, sys
conf, kb = sys.argv[1], sys.argv[2]
try:
    cfg = json.load(open(conf))
except FileNotFoundError:
    cfg = {}
if not isinstance(cfg, dict):
    sys.exit(f"{conf} is not a JSON object; fix it and run again")
old = cfg.get("knowledgebase")
if old not in (None, kb):
    print(f"[bootstrap-dbs] pharmacolibrary.local.json: knowledgebase {old!r} -> {kb!r}")
cfg["knowledgebase"] = kb
tmp = conf + ".tmp"
json.dump(cfg, open(tmp, "w"), indent=2); open(tmp, "a").write("\n")
os.replace(tmp, conf)
PY
    chown "$TARGET_USER:" "$CONF"
    log "knowledgebase set to $KB_DIR in $CONF"
  else
    log "WARNING: no Zenodo data unpacked, so knowledgebase is not configured; rerun when the records are public"
  fi
fi

# --- environment for the project scripts -----------------------------------------------------
# One file, sourced from ~/.bashrc; rewritten on every run so it follows the options given.
ENV_FILE="$USER_HOME/.pharmacolibrary_env"
{
  echo "# written by bootstrap-dbs.sh - re-run it to change, do not edit by hand"
  echo "export REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt"
  [ "$WITH_OMC" -eq 1 ] && echo "export PK_OMC_DOCKER=$OMC_IMAGE"
  [ -n "$GROBID_IMAGE" ] && echo "export GROBID_IMAGE=$GROBID_IMAGE"
  [ -n "$GROBID_MEM" ] && echo "export GROBID_MEM=$GROBID_MEM"
  [ "$WITH_WASM" -eq 1 ] && echo "export BODYLIGHT_FMU_COMPILER=$USER_HOME/Bodylight.js-FMU-Compiler"
  true
} > "$ENV_FILE"
chown "$TARGET_USER:" "$ENV_FILE"
BASHRC="$USER_HOME/.bashrc"
LINE='[ -f ~/.pharmacolibrary_env ] && . ~/.pharmacolibrary_env'
touch "$BASHRC"
grep -qxF "$LINE" "$BASHRC" || echo "$LINE" >> "$BASHRC"
chown "$TARGET_USER:" "$BASHRC"

log "done for $TARGET_USER: repos in $USER_HOME, knowledge base $( [ "$WITH_KB" -eq 1 ] && echo "$KB_DIR" || echo skipped ), venv $( [ "$WITH_VENV" -eq 1 ] && echo "$USER_HOME/venv" || echo skipped ), docker $( [ "$WITH_DOCKER" -eq 1 ] && echo on || echo skipped )"
