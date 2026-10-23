#!/bin/sh
# Init container: fetches the helper binaries into the PVC, pinned by SHA-256,
# and only when the cached copy is missing or doesn't match. Also creates the
# directories that get mounted by subPath, so they are owned by the steam user
# rather than created as root by the kubelet.
set -eu

tools=/data/tools
mkdir -p "$tools" /data/server /data/Zomboid /data/zombie_buddy /data/steam-home

# fetch <file> <url> <sha256>
fetch() {
  if echo "$3  $tools/$1" | sha256sum -c -s 2>/dev/null; then
    echo "==> $1 (cached)"
    return
  fi
  echo "==> $1"
  rm -f "$tools/$1.part"
  wget -qO "$tools/$1.part" "$2"
  if ! echo "$3  $tools/$1.part" | sha256sum -c -s; then
    echo "checksum mismatch for $1"
    rm -f "$tools/$1.part"
    exit 1
  fi
  mv "$tools/$1.part" "$tools/$1"
}

fetch jq \
  https://github.com/jqlang/jq/releases/download/jq-1.8.2/jq-linux-amd64 \
  b1c22172dd303f3be49e935aa56aa48a8b7a46e0bc838b4997d3bb451495870f
chmod 755 "$tools/jq"

fetch rcon.tar.gz \
  https://github.com/gorcon/rcon-cli/releases/download/v0.10.3/rcon-0.10.3-amd64_linux.tar.gz \
  6962a641ebf9a5957bd0cda1b8acf3e34a23686ae709f6c6a14ac3898521a5cc
rm -rf "$tools/rcon.x"
mkdir "$tools/rcon.x"
tar -xzf "$tools/rcon.tar.gz" -C "$tools/rcon.x"
mv "$tools/rcon.x/rcon-0.10.3-amd64_linux/rcon" "$tools/rcon"
rm -rf "$tools/rcon.x"
chmod 755 "$tools/rcon"

# Only seeds the agent: start.sh copies it into place once, after which
# ZombieBuddy replaces it from its Workshop item whenever that is newer.
fetch ZombieBuddy.jar \
  https://github.com/zed-0xff/ZombieBuddy/releases/download/v2.3.4/ZombieBuddy.jar \
  eb79b9876332010733a8e0d7ce4fe0377846059a9e28859029e2a0fb449f6cf2
