#!/usr/bin/env bash
# Build a signed APT repository tree for Unfocus alpha.
# Usage:
#   build_apt_repo.sh --pool-src DIR --output DIR --gpg-home DIR --gpg-key-id ID
#                     [--suite alpha] [--origin Unfocus] [--label Unfocus]
#
# Expects .deb files under --pool-src (flat or nested). Copies them into
# pool/main/u/unfocus/ with Debian-style basenames, then writes dists/<suite>/
# indexes and GPG-signed InRelease + Release.gpg.
set -euo pipefail

SUITE=alpha
ORIGIN=Unfocus
LABEL=Unfocus
POOL_SRC=
OUTPUT=
GPG_HOME=
GPG_KEY_ID=
PASSPHRASE_FILE=
COMPONENT=main
ARCH=amd64

usage() {
  echo "usage: $0 --pool-src DIR --output DIR --gpg-home DIR --gpg-key-id ID [--suite NAME]" >&2
  exit 2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --pool-src) POOL_SRC=$2; shift 2 ;;
    --output) OUTPUT=$2; shift 2 ;;
    --gpg-home) GPG_HOME=$2; shift 2 ;;
    --gpg-key-id) GPG_KEY_ID=$2; shift 2 ;;
    --passphrase-file) PASSPHRASE_FILE=$2; shift 2 ;;
    --suite) SUITE=$2; shift 2 ;;
    --origin) ORIGIN=$2; shift 2 ;;
    --label) LABEL=$2; shift 2 ;;
    -h|--help) usage ;;
    *) echo "unknown argument: $1" >&2; usage ;;
  esac
done

[ -n "$POOL_SRC" ] && [ -d "$POOL_SRC" ] || { echo "--pool-src must be a directory" >&2; exit 1; }
[ -n "$OUTPUT" ] || { echo "--output is required" >&2; exit 1; }
[ -n "$GPG_HOME" ] && [ -d "$GPG_HOME" ] || { echo "--gpg-home must be a directory" >&2; exit 1; }
[ -n "$GPG_KEY_ID" ] || { echo "--gpg-key-id is required" >&2; exit 1; }

command -v dpkg-deb >/dev/null
command -v dpkg-scanpackages >/dev/null
command -v gpg >/dev/null
command -v gzip >/dev/null
command -v sha256sum >/dev/null

export GNUPGHOME=$GPG_HOME

rm -rf "$OUTPUT"
mkdir -p "$OUTPUT/pool/${COMPONENT}/u/unfocus"
mkdir -p "$OUTPUT/dists/${SUITE}/${COMPONENT}/binary-${ARCH}"

# Collect debs and place with package_version_arch.deb names
mapfile -t DEBS < <(find "$POOL_SRC" -type f -name '*.deb' | sort)
if [ "${#DEBS[@]}" -eq 0 ]; then
  echo "no .deb files under $POOL_SRC" >&2
  exit 1
fi

for deb in "${DEBS[@]}"; do
  pkg=$(dpkg-deb --field "$deb" Package)
  ver=$(dpkg-deb --field "$deb" Version)
  arch=$(dpkg-deb --field "$deb" Architecture)
  [ "$pkg" = unfocus ] || { echo "$deb Package is $pkg, expected unfocus" >&2; exit 1; }
  [ "$arch" = "$ARCH" ] || { echo "$deb Architecture is $arch, expected $ARCH" >&2; exit 1; }
  # Debian filenames use the version as-is; ~ is allowed
  dest="$OUTPUT/pool/${COMPONENT}/u/unfocus/${pkg}_${ver}_${arch}.deb"
  if [ -e "$dest" ]; then
    # Identical content is ok (rebuild); different content is not
    if ! cmp -s "$deb" "$dest"; then
      echo "conflicting package already at $dest" >&2
      exit 1
    fi
  else
    cp -a "$deb" "$dest"
  fi
done

# Indexes: run from output root so Filename fields are pool/...
(
  cd "$OUTPUT"
  dpkg-scanpackages -m "pool/${COMPONENT}" /dev/null \
    > "dists/${SUITE}/${COMPONENT}/binary-${ARCH}/Packages"
)
gzip -9n -c "$OUTPUT/dists/${SUITE}/${COMPONENT}/binary-${ARCH}/Packages" \
  > "$OUTPUT/dists/${SUITE}/${COMPONENT}/binary-${ARCH}/Packages.gz"

# Release file for the suite
release_dir="$OUTPUT/dists/${SUITE}"
packages_path="${COMPONENT}/binary-${ARCH}/Packages"
packages_gz_path="${COMPONENT}/binary-${ARCH}/Packages.gz"

hash_line() {
  local algo=$1 file=$2
  local path="$release_dir/$file"
  local size
  size=$(stat -c%s "$path")
  local digest
  if [ "$algo" = MD5Sum ]; then
    digest=$(md5sum "$path" | awk '{print $1}')
  elif [ "$algo" = SHA256 ]; then
    digest=$(sha256sum "$path" | awk '{print $1}')
  else
    echo "unsupported hash $algo" >&2
    exit 1
  fi
  printf " %s %8d %s\n" "$digest" "$size" "$file"
}

{
  echo "Origin: ${ORIGIN}"
  echo "Label: ${LABEL}"
  echo "Suite: ${SUITE}"
  echo "Codename: ${SUITE}"
  echo "Architectures: ${ARCH}"
  echo "Components: ${COMPONENT}"
  echo "Description: Unfocus ${SUITE} packages"
  echo "Date: $(date -Ru)"
  echo "MD5Sum:"
  hash_line MD5Sum "$packages_path"
  hash_line MD5Sum "$packages_gz_path"
  echo "SHA256:"
  hash_line SHA256 "$packages_path"
  hash_line SHA256 "$packages_gz_path"
} > "$release_dir/Release"

# Sign Release
gpg_sign() {
  local args=(--batch --yes --pinentry-mode loopback --local-user "$GPG_KEY_ID")
  if [ -n "$PASSPHRASE_FILE" ] && [ -s "$PASSPHRASE_FILE" ]; then
    args+=(--passphrase-file "$PASSPHRASE_FILE")
  fi
  gpg "${args[@]}" "$@"
}

gpg_sign --clearsign --output "$release_dir/InRelease" "$release_dir/Release"
gpg_sign --detach-sign --armor --output "$release_dir/Release.gpg" "$release_dir/Release"

echo "built apt repo at $OUTPUT (${#DEBS[@]} package(s), suite ${SUITE})"
