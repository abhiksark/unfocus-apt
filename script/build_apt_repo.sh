#!/usr/bin/env bash
# Build one signed Unfocus APT channel.
# Usage:
#   build_apt_repo.sh --channel alpha|beta --pool-src DIR --output DIR
#                     --gpg-home DIR --gpg-key-id ID --source-date-epoch EPOCH
#                     [--origin Unfocus] [--label Unfocus]
set -euo pipefail

CHANNEL=
ORIGIN=Unfocus
LABEL=Unfocus
POOL_SRC=
OUTPUT=
GPG_HOME=
GPG_KEY_ID=
PASSPHRASE_FILE=
SOURCE_DATE_EPOCH=
COMPONENT=main
ARCH=amd64

usage() {
  echo "usage: $0 --channel alpha|beta --pool-src DIR --output DIR --gpg-home DIR --gpg-key-id ID --source-date-epoch EPOCH" >&2
  exit 2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --channel) CHANNEL=$2; shift 2 ;;
    --pool-src) POOL_SRC=$2; shift 2 ;;
    --output) OUTPUT=$2; shift 2 ;;
    --gpg-home) GPG_HOME=$2; shift 2 ;;
    --gpg-key-id) GPG_KEY_ID=$2; shift 2 ;;
    --passphrase-file) PASSPHRASE_FILE=$2; shift 2 ;;
    --source-date-epoch) SOURCE_DATE_EPOCH=$2; shift 2 ;;
    --origin) ORIGIN=$2; shift 2 ;;
    --label) LABEL=$2; shift 2 ;;
    -h|--help) usage ;;
    *) echo "unknown argument: $1" >&2; usage ;;
  esac
done

case "$CHANNEL" in
  alpha)
    POOL_PATH=pool/main/u/unfocus
    POOL_SCAN=pool/main
    ;;
  beta)
    POOL_PATH=pool/beta/u/unfocus
    POOL_SCAN=pool/beta
    ;;
  *)
    echo "--channel must be alpha or beta" >&2
    exit 1
    ;;
esac

[ -n "$POOL_SRC" ] && [ -d "$POOL_SRC" ] || { echo "--pool-src must be a directory" >&2; exit 1; }
[ -n "$OUTPUT" ] || { echo "--output is required" >&2; exit 1; }
[ -n "$GPG_HOME" ] && [ -d "$GPG_HOME" ] || { echo "--gpg-home must be a directory" >&2; exit 1; }
[ -n "$GPG_KEY_ID" ] || { echo "--gpg-key-id is required" >&2; exit 1; }
[[ "$SOURCE_DATE_EPOCH" =~ ^[0-9]+$ ]] || { echo "--source-date-epoch must be a non-negative integer" >&2; exit 1; }

command -v dpkg-deb >/dev/null
command -v dpkg-scanpackages >/dev/null
command -v gpg >/dev/null
command -v gzip >/dev/null
command -v sha256sum >/dev/null

export GNUPGHOME=$GPG_HOME

rm -rf "$OUTPUT"
mkdir -p "$OUTPUT/$POOL_PATH"
mkdir -p "$OUTPUT/dists/$CHANNEL/$COMPONENT/binary-$ARCH"

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
  [[ "$ver" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)~${CHANNEL}\.(0|[1-9][0-9]*)-1$ ]] || {
    echo "$deb has Debian version $ver; expected an $CHANNEL Debian version X.Y.Z~$CHANNEL.N-1" >&2
    exit 1
  }

  dest="$OUTPUT/$POOL_PATH/${pkg}_${ver}_${arch}.deb"
  if [ -e "$dest" ]; then
    if ! cmp -s "$deb" "$dest"; then
      echo "conflicting package already at $dest" >&2
      exit 1
    fi
  else
    cp -a "$deb" "$dest"
  fi
done

(
  cd "$OUTPUT"
  dpkg-scanpackages -m "$POOL_SCAN" /dev/null \
    > "dists/$CHANNEL/$COMPONENT/binary-$ARCH/Packages"
)
gzip -9n -c "$OUTPUT/dists/$CHANNEL/$COMPONENT/binary-$ARCH/Packages" \
  > "$OUTPUT/dists/$CHANNEL/$COMPONENT/binary-$ARCH/Packages.gz"

release_dir="$OUTPUT/dists/$CHANNEL"
packages_path="$COMPONENT/binary-$ARCH/Packages"
packages_gz_path="$COMPONENT/binary-$ARCH/Packages.gz"

hash_line() {
  local algo=$1 file=$2
  local path="$release_dir/$file"
  local size digest
  size=$(stat -c%s "$path")
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
  echo "Origin: $ORIGIN"
  echo "Label: $LABEL"
  echo "Suite: $CHANNEL"
  echo "Codename: $CHANNEL"
  echo "Architectures: $ARCH"
  echo "Components: $COMPONENT"
  echo "Description: Unfocus $CHANNEL packages"
  echo "Date: $(date -Ru --date="@$SOURCE_DATE_EPOCH")"
  echo "MD5Sum:"
  hash_line MD5Sum "$packages_path"
  hash_line MD5Sum "$packages_gz_path"
  echo "SHA256:"
  hash_line SHA256 "$packages_path"
  hash_line SHA256 "$packages_gz_path"
} > "$release_dir/Release"

gpg_sign() {
  local args=(
    --batch
    --yes
    --pinentry-mode loopback
    --faked-system-time "${SOURCE_DATE_EPOCH}!"
    --local-user "$GPG_KEY_ID"
  )
  if [ -n "$PASSPHRASE_FILE" ] && [ -s "$PASSPHRASE_FILE" ]; then
    args+=(--passphrase-file "$PASSPHRASE_FILE")
  fi
  gpg "${args[@]}" "$@"
}

while IFS= read -r -d '' deb; do
  gpg_sign --detach-sign --armor --output "${deb}.asc" "$deb"
done < <(find "$OUTPUT/$POOL_PATH" -type f -name '*.deb' -print0 | sort -z)

gpg_sign --clearsign --output "$release_dir/InRelease" "$release_dir/Release"
gpg_sign --detach-sign --armor --output "$release_dir/Release.gpg" "$release_dir/Release"

echo "built apt repo at $OUTPUT (${#DEBS[@]} package(s), channel $CHANNEL)"
