# Unfocus APT repository

Debian/Ubuntu packages for the Unfocus alpha, published as a signed APT suite
served from GitHub Pages.

This repository holds only the APT tree (`pool/`, `dists/`) and automation.
Application source and release packaging live in
[abhiksark/unfocus](https://github.com/abhiksark/unfocus).

There is no stable suite yet. The suite name is **`alpha`**.

## Install

Linux **X11** is the only qualified Unfocus backend. Wayland is unsupported.

```sh
curl -fsSL https://apt.abhik.ai/public-key.asc \
  | sudo gpg --dearmor -o /usr/share/keyrings/unfocus-archive-keyring.gpg

echo 'deb [arch=amd64 signed-by=/usr/share/keyrings/unfocus-archive-keyring.gpg] https://apt.abhik.ai alpha main' \
  | sudo tee /etc/apt/sources.list.d/unfocus-alpha.list

sudo apt update
sudo apt install unfocus
```

Alpha packages are **not application code-signed**. The archive key signs APT
**repository metadata** only (indexes), so `apt update` can trust this source.
It does not establish a notarized application identity. Prefer verifying a
release package against `SHA256SUMS` and GitHub build provenance when you want
independent supply-chain checks:
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
sudo rm -f /usr/share/keyrings/unfocus-archive-keyring.gpg
sudo apt update
```

Local settings under `~/.config/com.unfocus.desktop/` are not removed by the
package; see the [install guide](https://github.com/abhiksark/unfocus/blob/main/docs/install.md).

## Automation

On each published Unfocus prerelease, `abhiksark/unfocus` dispatches
`unfocus-alpha-published` here. The update workflow downloads
`Unfocus_*_amd64.deb` and `SHA256SUMS`, verifies the checksum, rebuilds the
signed `alpha` suite, and opens a reviewable pull request. Merging that PR
updates GitHub Pages.

Operator setup (secrets and the GitHub App) is documented in the Unfocus
repository under `.github/AGENTS.md` (APT automation boundary).

## Local tests

```sh
./script/build_apt_repo_test.sh
```

## License

Package binaries ship under the Unfocus MIT license from the upstream release.
Repository automation scripts in this tree are available under the MIT License
as published in [abhiksark/unfocus](https://github.com/abhiksark/unfocus/blob/main/LICENSE).
