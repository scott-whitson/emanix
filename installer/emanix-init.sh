#!/usr/bin/env bash
# emanix-init — turn the config the installer generated into a repo you own.
#
# The installer writes the minimum to boot, into /etc/nixos. That is enough to
# run and not enough to live in: no git, no history, root-owned, and nowhere to
# put a secret. This moves it somewhere you can work, proves it still
# evaluates, and stops.
#
# Safe to re-run: it refuses rather than overwrites.
set -euo pipefail

say()  { printf '\n\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mWARNING:\033[0m %s\n' "$*"; }
die()  { printf '\n\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

SRC=/etc/nixos
DEST="$HOME/flake"

[ -f "$SRC/host.nix" ] ||
  die "no $SRC/host.nix — this machine was not installed by
fresh-emanix-install's interactive mode, so there is nothing to adopt. If you
already keep a flake elsewhere, you do not need this command."

[ -e "$DEST" ] && die "$DEST already exists. Move it aside first; this command
will not overwrite a directory it did not create."

say "Copying $SRC to $DEST"
mkdir -p "$DEST"
cp -r "$SRC/." "$DEST/"
chown -R "$(id -u):$(id -g)" "$DEST"
chmod -R u+w "$DEST"

say "Adding a keys directory and .gitignore"
mkdir -p "$DEST/keys"
cat > "$DEST/.gitignore" <<'EOF'
# Private host key halves. The .pub halves ARE committed: they are the
# recipients your secrets are encrypted to, and the installer verifies a
# staged private key against them.
keys/*_host_ed25519
result
result-*
EOF

# The machine already has a host key -- the installer generated it. Publishing
# the public half here is what lets secrets be encrypted TO this machine later.
if [ -f /etc/ssh/ssh_host_ed25519_key.pub ]; then
  # A silent `|| echo host` fallback here would mis-name the key file as
  # host_host_ed25519.pub whenever `nix eval` fails, instead of saying so --
  # and a mis-named recipient file is exactly the kind of thing that only
  # surfaces much later, as agenix failing to decrypt. Die and say why.
  host="$(nix eval --raw --file "$DEST/host.nix" hostName 2>/dev/null)" ||
    die "could not read hostName from $DEST/host.nix (nix eval failed) --
refusing to guess a name for the key file."
  cp /etc/ssh/ssh_host_ed25519_key.pub "$DEST/keys/${host}_host_ed25519.pub"
  say "Recorded this host's public key as keys/${host}_host_ed25519.pub"
fi

say "Initialising git"
git -C "$DEST" init -q
git -C "$DEST" add -A
git -C "$DEST" -c user.email=emanix@localhost -c user.name=emanix \
  commit -q -m "initial commit: the config this machine was installed with"

say "Checking it still evaluates"
if nix flake check "$DEST" 2>&1 | tail -20; then
  say "emanix-init complete."
  echo "  Your config now lives in $DEST and is a git repo."
  echo "  Rebuild with:  sudo nixos-rebuild switch --flake $DEST"
  echo "  Documentation: https://emanix.net"
else
  warn "$DEST does not pass 'nix flake check'."
  warn "The files are in place and committed, so nothing is lost — but fix this"
  warn "before relying on it. /etc/nixos is untouched and still builds."
  exit 1
fi
