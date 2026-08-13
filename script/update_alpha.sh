#!/usr/bin/env bash
# Download a published Unfocus prerelease .deb, verify SHA256SUMS, rebuild the
# alpha APT tree, and report whether the tree changed.
#
# Usage:
#   update_alpha.sh \
#     --source-repository abhiksark/unfocus \
#     --release-id ID \
#     --tag-name vX.Y.Z-alpha.N \
#     --assets-dir DIR \
#     --repo-root DIR \
#     --gpg-home DIR \
#     --gpg-key-id ID \
#     --metadata FILE
set -euo pipefail

EXPECTED_REPOSITORY=abhiksark/unfocus
SOURCE_REPOSITORY=
RELEASE_ID=
TAG_NAME=
ASSETS_DIR=
REPO_ROOT=
GPG_HOME=
GPG_KEY_ID=
PASSPHRASE_FILE=
METADATA=

usage() {
  echo "usage: $0 --source-repository OWNER/REPO --release-id ID --tag-name TAG --assets-dir DIR --repo-root DIR --gpg-home DIR --gpg-key-id ID --metadata FILE" >&2
  exit 2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --source-repository) SOURCE_REPOSITORY=$2; shift 2 ;;
    --release-id) RELEASE_ID=$2; shift 2 ;;
    --tag-name) TAG_NAME=$2; shift 2 ;;
    --assets-dir) ASSETS_DIR=$2; shift 2 ;;
    --repo-root) REPO_ROOT=$2; shift 2 ;;
    --gpg-home) GPG_HOME=$2; shift 2 ;;
    --gpg-key-id) GPG_KEY_ID=$2; shift 2 ;;
    --passphrase-file) PASSPHRASE_FILE=$2; shift 2 ;;
    --metadata) METADATA=$2; shift 2 ;;
    -h|--help) usage ;;
    *) echo "unknown argument: $1" >&2; usage ;;
  esac
done

[ "$SOURCE_REPOSITORY" = "$EXPECTED_REPOSITORY" ] || {
  echo "unexpected source repository: $SOURCE_REPOSITORY" >&2
  exit 1
}
[[ "$RELEASE_ID" =~ ^[0-9]+$ ]] || { echo "release id must be numeric" >&2; exit 1; }
[[ "$TAG_NAME" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*$ ]] || {
  echo "tag is not a supported prerelease: $TAG_NAME" >&2
  exit 1
}
VERSION=${TAG_NAME#v}
DEB_NAME="Unfocus_${VERSION}_amd64.deb"

[ -d "$ASSETS_DIR" ] || { echo "assets dir missing" >&2; exit 1; }
[ -f "$ASSETS_DIR/$DEB_NAME" ] || { echo "missing $DEB_NAME in assets dir" >&2; exit 1; }
[ -f "$ASSETS_DIR/SHA256SUMS" ] || { echo "missing SHA256SUMS in assets dir" >&2; exit 1; }
[ -n "$REPO_ROOT" ] || { echo "--repo-root required" >&2; exit 1; }
[ -n "$METADATA" ] || { echo "--metadata required" >&2; exit 1; }

# Verify checksum for the deb only
(
  cd "$ASSETS_DIR"
  # SHA256SUMS may list many files; check just the deb line
  expected=$(awk -v f="$DEB_NAME" '$2 == f { print $1; found=1 } END { if (!found) exit 1 }' SHA256SUMS)
  actual=$(sha256sum "$DEB_NAME" | awk '{print $1}')
  [ "$expected" = "$actual" ] || {
    echo "SHA256 mismatch for $DEB_NAME: expected $expected got $actual" >&2
    exit 1
  }
)

# Debian control checks
pkg=$(dpkg-deb --field "$ASSETS_DIR/$DEB_NAME" Package)
ver=$(dpkg-deb --field "$ASSETS_DIR/$DEB_NAME" Version)
arch=$(dpkg-deb --field "$ASSETS_DIR/$DEB_NAME" Architecture)
[ "$pkg" = unfocus ] || { echo "Package $pkg != unfocus" >&2; exit 1; }
[ "$arch" = amd64 ] || { echo "Architecture $arch != amd64" >&2; exit 1; }

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/pool-src"
# Keep existing pool packages if present (prior alphas), then add/replace this version
if [ -d "$REPO_ROOT/pool" ]; then
  find "$REPO_ROOT/pool" -type f -name '*.deb' -exec cp -a {} "$WORK/pool-src/" \;
fi
cp -a "$ASSETS_DIR/$DEB_NAME" "$WORK/pool-src/"

# Remove any other package file for the same version path by building fresh
build_args=(
  --pool-src "$WORK/pool-src"
  --output "$WORK/repo"
  --gpg-home "$GPG_HOME"
  --gpg-key-id "$GPG_KEY_ID"
  --suite alpha
)
if [ -n "$PASSPHRASE_FILE" ] && [ -s "$PASSPHRASE_FILE" ]; then
  build_args+=(--passphrase-file "$PASSPHRASE_FILE")
fi
"$SCRIPT_DIR/build_apt_repo.sh" "${build_args[@]}"

# Export public key into tree
gpg --batch --homedir "$GPG_HOME" --armor --export "$GPG_KEY_ID" > "$WORK/repo/public-key.asc"

# Diff against current published tree (pool + dists + public-key)
changed=false
for path in pool dists public-key.asc; do
  if [ -e "$REPO_ROOT/$path" ] || [ -e "$WORK/repo/$path" ]; then
    if ! diff -qr "$REPO_ROOT/$path" "$WORK/repo/$path" >/dev/null 2>&1; then
      changed=true
      break
    fi
  fi
done

if [ "$changed" = true ]; then
  rm -rf "$REPO_ROOT/pool" "$REPO_ROOT/dists"
  mkdir -p "$REPO_ROOT"
  cp -a "$WORK/repo/pool" "$REPO_ROOT/pool"
  cp -a "$WORK/repo/dists" "$REPO_ROOT/dists"
  cp -a "$WORK/repo/public-key.asc" "$REPO_ROOT/public-key.asc"
fi

release_url="https://github.com/${SOURCE_REPOSITORY}/releases/tag/${TAG_NAME}"
cat > "$METADATA" <<JSON
{
  "changed": $( [ "$changed" = true ] && echo true || echo false ),
  "source_repository": "$(printf %s "$SOURCE_REPOSITORY")",
  "release_id": $RELEASE_ID,
  "tag_name": "$(printf %s "$TAG_NAME")",
  "version": "$(printf %s "$VERSION")",
  "debian_version": "$(printf %s "$ver")",
  "deb_name": "$(printf %s "$DEB_NAME")",
  "deb_sha256": "$(sha256sum "$ASSETS_DIR/$DEB_NAME" | awk '{print $1}')",
  "release_url": "$(printf %s "$release_url")"
}
JSON

echo "update_alpha: changed=$changed version=$VERSION debian_version=$ver"
