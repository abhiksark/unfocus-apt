#!/usr/bin/env bash
# Verify one published Unfocus package and update only its APT channel.
set -euo pipefail

EXPECTED_REPOSITORY=abhiksark/unfocus
CHANNEL=
SOURCE_REPOSITORY=
RELEASE_ID=
TAG_NAME=
ASSETS_DIR=
REPO_ROOT=
GPG_HOME=
GPG_KEY_ID=
PASSPHRASE_FILE=
SOURCE_DATE_EPOCH=
METADATA=

usage() {
  echo "usage: $0 --channel alpha|beta|stable --source-repository OWNER/REPO --release-id ID --tag-name TAG --assets-dir DIR --repo-root DIR --gpg-home DIR --gpg-key-id ID --source-date-epoch EPOCH --metadata FILE" >&2
  exit 2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --channel) CHANNEL=$2; shift 2 ;;
    --source-repository) SOURCE_REPOSITORY=$2; shift 2 ;;
    --release-id) RELEASE_ID=$2; shift 2 ;;
    --tag-name) TAG_NAME=$2; shift 2 ;;
    --assets-dir) ASSETS_DIR=$2; shift 2 ;;
    --repo-root) REPO_ROOT=$2; shift 2 ;;
    --gpg-home) GPG_HOME=$2; shift 2 ;;
    --gpg-key-id) GPG_KEY_ID=$2; shift 2 ;;
    --passphrase-file) PASSPHRASE_FILE=$2; shift 2 ;;
    --source-date-epoch) SOURCE_DATE_EPOCH=$2; shift 2 ;;
    --metadata) METADATA=$2; shift 2 ;;
    -h|--help) usage ;;
    *) echo "unknown argument: $1" >&2; usage ;;
  esac
done

case "$CHANNEL" in
  alpha) POOL_PATH=pool/main/u/unfocus ;;
  beta) POOL_PATH=pool/beta/u/unfocus ;;
  stable) POOL_PATH=pool/stable/u/unfocus ;;
  *) echo "--channel must be alpha, beta, or stable" >&2; exit 1 ;;
esac

[ "$SOURCE_REPOSITORY" = "$EXPECTED_REPOSITORY" ] || {
  echo "unexpected source repository: $SOURCE_REPOSITORY" >&2
  exit 1
}
[[ "$RELEASE_ID" =~ ^[0-9]+$ ]] || { echo "release id must be numeric" >&2; exit 1; }
if [ "$CHANNEL" = stable ]; then
  tag_pattern='^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
else
  tag_pattern="^v(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)-${CHANNEL}\\.(0|[1-9][0-9]*)$"
fi
[[ "$TAG_NAME" =~ $tag_pattern ]] || {
  echo "tag must be an exact $CHANNEL version: $TAG_NAME" >&2
  exit 1
}
CORE_VERSION="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.${BASH_REMATCH[3]}"
VERSION=${TAG_NAME#v}
if [ "$CHANNEL" = stable ]; then
  EXPECTED_DEBIAN_VERSION="$CORE_VERSION-1"
else
  CHANNEL_NUMBER=${BASH_REMATCH[4]}
  EXPECTED_DEBIAN_VERSION="$CORE_VERSION~$CHANNEL.$CHANNEL_NUMBER-1"
fi
DEB_NAME="Unfocus_${VERSION}_amd64.deb"

[ -d "$ASSETS_DIR" ] || { echo "assets dir missing" >&2; exit 1; }
[ -f "$ASSETS_DIR/$DEB_NAME" ] || { echo "missing $DEB_NAME in assets dir" >&2; exit 1; }
[ -f "$ASSETS_DIR/SHA256SUMS" ] || { echo "missing SHA256SUMS in assets dir" >&2; exit 1; }
[ -n "$REPO_ROOT" ] || { echo "--repo-root required" >&2; exit 1; }
[ -n "$GPG_HOME" ] && [ -d "$GPG_HOME" ] || { echo "--gpg-home must be a directory" >&2; exit 1; }
[ -n "$GPG_KEY_ID" ] || { echo "--gpg-key-id is required" >&2; exit 1; }
[[ "$SOURCE_DATE_EPOCH" =~ ^[0-9]+$ ]] || { echo "--source-date-epoch must be a non-negative integer" >&2; exit 1; }
[ -n "$METADATA" ] || { echo "--metadata required" >&2; exit 1; }

(
  cd "$ASSETS_DIR"
  expected=$(awk -v f="$DEB_NAME" '$2 == f { print $1; found=1 } END { if (!found) exit 1 }' SHA256SUMS)
  actual=$(sha256sum "$DEB_NAME" | awk '{print $1}')
  [ "$expected" = "$actual" ] || {
    echo "SHA256 mismatch for $DEB_NAME: expected $expected got $actual" >&2
    exit 1
  }
)

pkg=$(dpkg-deb --field "$ASSETS_DIR/$DEB_NAME" Package)
ver=$(dpkg-deb --field "$ASSETS_DIR/$DEB_NAME" Version)
arch=$(dpkg-deb --field "$ASSETS_DIR/$DEB_NAME" Architecture)
[ "$pkg" = unfocus ] || { echo "Package $pkg != unfocus" >&2; exit 1; }
[ "$arch" = amd64 ] || { echo "Architecture $arch != amd64" >&2; exit 1; }
[ "$ver" = "$EXPECTED_DEBIAN_VERSION" ] || {
  echo "Debian version $ver does not match tag $TAG_NAME (expected $EXPECTED_DEBIAN_VERSION)" >&2
  exit 1
}

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/pool-src"

existing_package="$REPO_ROOT/$POOL_PATH/unfocus_${ver}_amd64.deb"
if [ -f "$existing_package" ] && ! cmp -s "$ASSETS_DIR/$DEB_NAME" "$existing_package"; then
  echo "published $CHANNEL package $ver differs from the immutable release asset" >&2
  exit 1
fi
if [ -d "$REPO_ROOT/$POOL_PATH" ]; then
  while IFS= read -r published_package; do
    published_version=$(dpkg-deb --field "$published_package" Version)
    if dpkg --compare-versions "$published_version" gt "$ver"; then
      echo "refusing to downgrade $CHANNEL from $published_version to $ver" >&2
      exit 1
    fi
  done < <(find "$REPO_ROOT/$POOL_PATH" -type f -name '*.deb' | sort)
fi
if [ -d "$REPO_ROOT/$POOL_PATH" ]; then
  find "$REPO_ROOT/$POOL_PATH" -type f -name '*.deb' -exec cp -a {} "$WORK/pool-src/" \;
fi
cp -a "$ASSETS_DIR/$DEB_NAME" "$WORK/pool-src/"

build_args=(
  --channel "$CHANNEL"
  --pool-src "$WORK/pool-src"
  --output "$WORK/repo"
  --gpg-home "$GPG_HOME"
  --gpg-key-id "$GPG_KEY_ID"
  --source-date-epoch "$SOURCE_DATE_EPOCH"
)
if [ -n "$PASSPHRASE_FILE" ] && [ -s "$PASSPHRASE_FILE" ]; then
  build_args+=(--passphrase-file "$PASSPHRASE_FILE")
fi
"$SCRIPT_DIR/build_apt_repo.sh" "${build_args[@]}"

gpg --batch --homedir "$GPG_HOME" --armor --export "$GPG_KEY_ID" > "$WORK/repo/public-key.asc"

changed=false
for path in "$POOL_PATH" "dists/$CHANNEL" public-key.asc; do
  if [ -e "$REPO_ROOT/$path" ] || [ -e "$WORK/repo/$path" ]; then
    if ! diff -qr "$REPO_ROOT/$path" "$WORK/repo/$path" >/dev/null 2>&1; then
      changed=true
      break
    fi
  fi
done

if [ "$changed" = true ]; then
  rm -rf "$REPO_ROOT/$POOL_PATH" "$REPO_ROOT/dists/$CHANNEL"
  mkdir -p "$(dirname "$REPO_ROOT/$POOL_PATH")" "$REPO_ROOT/dists"
  cp -a "$WORK/repo/$POOL_PATH" "$REPO_ROOT/$POOL_PATH"
  cp -a "$WORK/repo/dists/$CHANNEL" "$REPO_ROOT/dists/$CHANNEL"
  cp -a "$WORK/repo/public-key.asc" "$REPO_ROOT/public-key.asc"
fi

release_url="https://github.com/$SOURCE_REPOSITORY/releases/tag/$TAG_NAME"
cat > "$METADATA" <<JSON
{
  "changed": $( [ "$changed" = true ] && echo true || echo false ),
  "channel": "$CHANNEL",
  "source_repository": "$SOURCE_REPOSITORY",
  "release_id": $RELEASE_ID,
  "tag_name": "$TAG_NAME",
  "version": "$VERSION",
  "debian_version": "$ver",
  "deb_name": "$DEB_NAME",
  "deb_sha256": "$(sha256sum "$ASSETS_DIR/$DEB_NAME" | awk '{print $1}')",
  "release_url": "$release_url"
}
JSON

echo "update_repo: channel=$CHANNEL changed=$changed version=$VERSION debian_version=$ver"
