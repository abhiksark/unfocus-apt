#!/usr/bin/env bash
# Unit tests for build_apt_repo.sh using an ephemeral GPG key and a fixture deb.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BUILD="$ROOT/script/build_apt_repo.sh"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

export GNUPGHOME=$WORK/gnupg
mkdir -p "$GNUPGHOME"
chmod 700 "$GNUPGHOME"

# Ephemeral RSA key (no passphrase) for CI/local tests
gpg --batch --pinentry-mode loopback --passphrase '' --quick-generate-key \
  "Unfocus Apt Test <apt-test@unfocus.example>" default default never
KEY_ID=$(gpg --list-keys --with-colons | awk -F: '/^pub:/ { print $5; exit }')
[ -n "$KEY_ID" ]

# Minimal valid .deb
mkdir -p "$WORK/debroot/DEBIAN" "$WORK/debroot/usr/bin"
cat > "$WORK/debroot/DEBIAN/control" <<CTRL
Package: unfocus
Version: 0.0.0~alpha.1-1
Section: utils
Priority: optional
Architecture: amd64
Maintainer: Unfocus Test <test@unfocus.example>
Description: fixture package for apt repo tests
CTRL
printf '#!/bin/sh\necho fixture\n' > "$WORK/debroot/usr/bin/unfocus"
chmod 755 "$WORK/debroot/usr/bin/unfocus"
dpkg-deb --build --root-owner-group "$WORK/debroot" "$WORK/fixture.deb" >/dev/null

mkdir -p "$WORK/pool-src"
cp "$WORK/fixture.deb" "$WORK/pool-src/"

"$BUILD" \
  --pool-src "$WORK/pool-src" \
  --output "$WORK/repo" \
  --gpg-home "$GNUPGHOME" \
  --gpg-key-id "$KEY_ID" \
  --suite alpha

# Assertions
test -f "$WORK/repo/pool/main/u/unfocus/unfocus_0.0.0~alpha.1-1_amd64.deb"
test -f "$WORK/repo/pool/main/u/unfocus/unfocus_0.0.0~alpha.1-1_amd64.deb.asc"
gpg --batch --verify "$WORK/repo/pool/main/u/unfocus/unfocus_0.0.0~alpha.1-1_amd64.deb.asc" \
  "$WORK/repo/pool/main/u/unfocus/unfocus_0.0.0~alpha.1-1_amd64.deb" >/dev/null 2>&1
test -f "$WORK/repo/dists/alpha/main/binary-amd64/Packages"
test -f "$WORK/repo/dists/alpha/main/binary-amd64/Packages.gz"
test -f "$WORK/repo/dists/alpha/Release"
test -f "$WORK/repo/dists/alpha/InRelease"
test -f "$WORK/repo/dists/alpha/Release.gpg"

grep -q '^Package: unfocus$' "$WORK/repo/dists/alpha/main/binary-amd64/Packages"
grep -q '^Version: 0.0.0~alpha.1-1$' "$WORK/repo/dists/alpha/main/binary-amd64/Packages"
grep -q 'Filename: pool/main/u/unfocus/unfocus_0.0.0~alpha.1-1_amd64.deb' \
  "$WORK/repo/dists/alpha/main/binary-amd64/Packages"

# GPG verify InRelease
gpg --batch --verify "$WORK/repo/dists/alpha/InRelease" >/dev/null 2>&1
gpg --batch --verify "$WORK/repo/dists/alpha/Release.gpg" "$WORK/repo/dists/alpha/Release" >/dev/null 2>&1

echo "build_apt_repo_test: ok"
