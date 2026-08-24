#!/usr/bin/env bash
# Integration tests for the channel-aware APT builder and updater.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BUILD="$ROOT/script/build_apt_repo.sh"
UPDATE="$ROOT/script/update_repo.sh"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

export GNUPGHOME=$WORK/gnupg
mkdir -p "$GNUPGHOME"
chmod 700 "$GNUPGHOME"

gpg --batch --pinentry-mode loopback --passphrase '' --quick-generate-key \
  "Unfocus Apt Test <apt-test@unfocus.example>" default default never
KEY_ID=$(gpg --list-keys --with-colons | awk -F: '/^pub:/ { print $5; exit }')
SOURCE_DATE_EPOCH=$(date +%s)
[ -n "$KEY_ID" ]

make_deb() {
  local version=$1 output=$2 marker=$3
  local root=$WORK/debroot-$marker
  mkdir -p "$root/DEBIAN" "$root/usr/bin"
  cat > "$root/DEBIAN/control" <<CTRL
Package: unfocus
Version: $version
Section: utils
Priority: optional
Architecture: amd64
Maintainer: Unfocus Test <test@unfocus.example>
Description: fixture package for apt repo tests
CTRL
  printf '#!/bin/sh\necho %s\n' "$marker" > "$root/usr/bin/unfocus"
  chmod 755 "$root/usr/bin/unfocus"
  dpkg-deb --build --root-owner-group "$root" "$output" >/dev/null
}

write_sums() {
  local directory=$1 filename=$2
  (
    cd "$directory"
    sha256sum "$filename" > SHA256SUMS
  )
}

tree_digest() {
  local root=$1
  shift
  (
    cd "$root"
    find "$@" -type f -print0 | sort -z | xargs -0 sha256sum
  ) | sha256sum | awk '{print $1}'
}

assert_rejected() {
  local expected=$1
  shift
  if output=$("$@" 2>&1); then
    echo "command unexpectedly succeeded: $*" >&2
    exit 1
  fi
  grep -Fq -- "$expected" <<<"$output" || {
    echo "expected rejection containing '$expected', got:" >&2
    echo "$output" >&2
    exit 1
  }
}

mkdir -p "$WORK/alpha-src" "$WORK/beta-src"
make_deb "0.5.0~alpha.1-1" "$WORK/alpha-src/alpha.deb" alpha
make_deb "0.6.0~beta.1-1" "$WORK/beta-src/beta.deb" beta

common_build_args=(
  --gpg-home "$GNUPGHOME"
  --gpg-key-id "$KEY_ID"
  --source-date-epoch "$SOURCE_DATE_EPOCH"
)

"$BUILD" \
  --channel alpha \
  --pool-src "$WORK/alpha-src" \
  --output "$WORK/alpha-repo" \
  "${common_build_args[@]}"
"$BUILD" \
  --channel beta \
  --pool-src "$WORK/beta-src" \
  --output "$WORK/beta-repo" \
  "${common_build_args[@]}"

alpha_deb="$WORK/alpha-repo/pool/main/u/unfocus/unfocus_0.5.0~alpha.1-1_amd64.deb"
beta_deb="$WORK/beta-repo/pool/beta/u/unfocus/unfocus_0.6.0~beta.1-1_amd64.deb"
test -f "$alpha_deb"
test -f "${alpha_deb}.asc"
test -f "$beta_deb"
test -f "${beta_deb}.asc"
gpg --batch --verify "${alpha_deb}.asc" "$alpha_deb" >/dev/null 2>&1
gpg --batch --verify "${beta_deb}.asc" "$beta_deb" >/dev/null 2>&1

for channel in alpha beta; do
  release_dir="$WORK/${channel}-repo/dists/$channel"
  test -f "$release_dir/main/binary-amd64/Packages"
  test -f "$release_dir/main/binary-amd64/Packages.gz"
  test -f "$release_dir/Release"
  test -f "$release_dir/InRelease"
  test -f "$release_dir/Release.gpg"
  gpg --batch --verify "$release_dir/InRelease" >/dev/null 2>&1
  gpg --batch --verify "$release_dir/Release.gpg" "$release_dir/Release" >/dev/null 2>&1
done

grep -q '^Version: 0.5.0~alpha.1-1$' \
  "$WORK/alpha-repo/dists/alpha/main/binary-amd64/Packages"
grep -q 'Filename: pool/main/u/unfocus/unfocus_0.5.0~alpha.1-1_amd64.deb' \
  "$WORK/alpha-repo/dists/alpha/main/binary-amd64/Packages"
grep -q '^Version: 0.6.0~beta.1-1$' \
  "$WORK/beta-repo/dists/beta/main/binary-amd64/Packages"
grep -q 'Filename: pool/beta/u/unfocus/unfocus_0.6.0~beta.1-1_amd64.deb' \
  "$WORK/beta-repo/dists/beta/main/binary-amd64/Packages"

assert_rejected "expected an alpha Debian version" \
  "$BUILD" --channel alpha --pool-src "$WORK/beta-src" --output "$WORK/wrong-build" \
  "${common_build_args[@]}"
assert_rejected "--channel must be alpha or beta" \
  "$BUILD" --channel stable --pool-src "$WORK/alpha-src" --output "$WORK/wrong-build" \
  "${common_build_args[@]}"

mkdir -p "$WORK/repository/pool/main/u" "$WORK/repository/dists"
cp -a "$WORK/alpha-repo/pool/main/u/unfocus" "$WORK/repository/pool/main/u/unfocus"
cp -a "$WORK/alpha-repo/dists/alpha" "$WORK/repository/dists/alpha"
gpg --batch --armor --export "$KEY_ID" > "$WORK/repository/public-key.asc"
alpha_before=$(tree_digest "$WORK/repository" pool/main/u/unfocus dists/alpha)

mkdir -p "$WORK/assets"
cp -a "$WORK/beta-src/beta.deb" "$WORK/assets/Unfocus_0.6.0-beta.1_amd64.deb"
write_sums "$WORK/assets" "Unfocus_0.6.0-beta.1_amd64.deb"

common_update_args=(
  --channel beta
  --source-repository abhiksark/unfocus
  --release-id 601
  --tag-name v0.6.0-beta.1
  --assets-dir "$WORK/assets"
  --repo-root "$WORK/repository"
  --gpg-home "$GNUPGHOME"
  --gpg-key-id "$KEY_ID"
  --source-date-epoch "$SOURCE_DATE_EPOCH"
)

"$UPDATE" "${common_update_args[@]}" --metadata "$WORK/first-update.json"
test "$(jq -r .changed "$WORK/first-update.json")" = true
test "$(jq -r .channel "$WORK/first-update.json")" = beta
test "$(jq -r .debian_version "$WORK/first-update.json")" = "0.6.0~beta.1-1"
test -f "$WORK/repository/pool/beta/u/unfocus/unfocus_0.6.0~beta.1-1_amd64.deb"
test -f "$WORK/repository/dists/beta/InRelease"
test "$alpha_before" = "$(tree_digest "$WORK/repository" pool/main/u/unfocus dists/alpha)"
grep -q '^Version: 0.6.0~beta.1-1$' \
  "$WORK/repository/dists/beta/main/binary-amd64/Packages"
if grep -q '~beta\.' "$WORK/repository/dists/alpha/main/binary-amd64/Packages"; then
  echo "beta version leaked into the alpha Packages index" >&2
  exit 1
fi

published_before=$(tree_digest "$WORK/repository" pool dists public-key.asc)
"$UPDATE" "${common_update_args[@]}" --metadata "$WORK/second-update.json"
test "$(jq -r .changed "$WORK/second-update.json")" = false
test "$published_before" = "$(tree_digest "$WORK/repository" pool dists public-key.asc)"

wrong_tag_args=("${common_update_args[@]}")
for index in "${!wrong_tag_args[@]}"; do
  if [ "${wrong_tag_args[$index]}" = v0.6.0-beta.1 ]; then
    wrong_tag_args[$index]=v0.6.0-alpha.1
  fi
done
assert_rejected "tag must be an exact beta prerelease" \
  "$UPDATE" "${wrong_tag_args[@]}" --metadata "$WORK/wrong-tag.json"

mkdir -p "$WORK/wrong-assets"
cp -a "$WORK/alpha-src/alpha.deb" "$WORK/wrong-assets/Unfocus_0.6.0-beta.1_amd64.deb"
write_sums "$WORK/wrong-assets" "Unfocus_0.6.0-beta.1_amd64.deb"
wrong_version_args=("${common_update_args[@]}")
for index in "${!wrong_version_args[@]}"; do
  if [ "${wrong_version_args[$index]}" = "$WORK/assets" ]; then
    wrong_version_args[$index]="$WORK/wrong-assets"
  fi
done
assert_rejected "Debian version 0.5.0~alpha.1-1 does not match tag v0.6.0-beta.1" \
  "$UPDATE" "${wrong_version_args[@]}" --metadata "$WORK/wrong-version.json"

echo "build_apt_repo_test: ok"
