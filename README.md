# Unfocus APT repository

Debian/Ubuntu packages for Unfocus prereleases, published as signed APT suites
served from GitHub Pages.

This repository holds only the APT tree (`pool/`, `dists/`) and automation.
Application source and release packaging live in
[abhiksark/unfocus](https://github.com/abhiksark/unfocus).

There is no stable suite yet. New prereleases are published to **`beta`**.
The **`alpha`** suite remains installable but is frozen at its last alpha.

## Install beta

Linux **X11** is the only qualified Unfocus backend. Wayland is unsupported.

```sh
curl -fsSL https://apt.abhik.ai/public-key.asc \
  | sudo gpg --dearmor -o /usr/share/keyrings/unfocus-archive-keyring.gpg

echo 'deb [arch=amd64 signed-by=/usr/share/keyrings/unfocus-archive-keyring.gpg] https://apt.abhik.ai beta main' \
  | sudo tee /etc/apt/sources.list.d/unfocus-beta.list

sudo apt update
sudo apt install unfocus
```

## Move from alpha to beta

Alpha users stay on alpha until they replace the source explicitly:

```sh
sudo rm -f /etc/apt/sources.list.d/unfocus-alpha.list
echo 'deb [arch=amd64 signed-by=/usr/share/keyrings/unfocus-archive-keyring.gpg] https://apt.abhik.ai beta main' \
  | sudo tee /etc/apt/sources.list.d/unfocus-beta.list
sudo apt update
sudo apt install --only-upgrade unfocus
```

The frozen alpha remains available at `https://apt.abhik.ai alpha main` for
users who do not migrate.

Packages are **not application code-signed**. The archive key signs APT
**repository metadata** and detached package signatures; it does not establish
a notarized application identity. Prefer verifying a release package against
`SHA256SUMS` and GitHub build provenance when you want independent
supply-chain checks:
https://github.com/abhiksark/unfocus/releases

## Upgrade

```sh
sudo apt update
sudo apt install --only-upgrade unfocus
```

## Uninstall

```sh
sudo apt remove unfocus
```

To remove the APT source as well:

```sh
sudo rm -f /etc/apt/sources.list.d/unfocus-alpha.list
sudo rm -f /etc/apt/sources.list.d/unfocus-beta.list
sudo rm -f /usr/share/keyrings/unfocus-archive-keyring.gpg
sudo apt update
```

Local settings under `~/.config/com.unfocus.desktop/` are not removed by the
package; see the [install guide](https://github.com/abhiksark/unfocus/blob/main/docs/install.md).

## Automation

Published alpha releases dispatch `unfocus-alpha-published`; published beta
releases dispatch `unfocus-beta-published`. Each updater accepts only its exact
`X.Y.Z-<channel>.N` tag form, verifies `SHA256SUMS` and the matching Debian
version, and rebuilds only that channel. Alpha uses `pool/main/u/unfocus` and
`dists/alpha`; beta uses `pool/beta/u/unfocus` and `dists/beta`.

The two direct-push workflows share one non-cancelling concurrency group so
they cannot update `main` simultaneously. Operator secrets are documented in
`OPERATOR.md`.

## Local tests

On Debian or Ubuntu with `dpkg-dev` and `gnupg` installed:

```sh
./script/build_apt_repo_test.sh
```

The test uses an ephemeral GPG key and covers signatures, channel isolation,
wrong-channel rejection, version matching, deterministic redispatch, and
preservation of the other channel.

## License

Package binaries ship under the Unfocus MIT license from the upstream release.
Repository automation scripts in this tree are available under the MIT License
as published in [abhiksark/unfocus](https://github.com/abhiksark/unfocus/blob/main/LICENSE).
