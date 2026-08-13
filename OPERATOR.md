# Operator setup for unfocus-apt

## Custom domain (apt.abhik.ai)

GitHub Pages serves **`https://apt.abhik.ai`**. DNS CNAME:

| Type | Host | Answer |
| --- | --- | --- |
| CNAME | `apt` | `abhiksark.github.io` |

Enforce HTTPS in Settings → Pages after the certificate is issued.

## Secrets (environment `apt-repo-automation`)

### On `abhiksark/unfocus-apt`

| Secret | Purpose |
| --- | --- |
| `APT_SIGNING_KEY` | Armored private key for the APT archive (signs `InRelease`) |
| `APT_SIGNING_KEY_PASSPHRASE` | Optional; only if the private key is passphrase-protected |

The public half is committed as `public-key.asc` and served at
`https://apt.abhik.ai/public-key.asc`.

### On `abhiksark/unfocus`

| Secret | Purpose |
| --- | --- |
| `APT_DISPATCH_TOKEN` | Token with `repo` scope that can create
  `repository_dispatch` events on `unfocus-apt` (PAT or GitHub App installation
  token). Used by `apt-alpha-dispatch.yml` when a prerelease is published. |

## First / recovery publish

```sh
# From this repo, Actions → "Update alpha apt repository" → Run workflow
# with tag e.g. v0.3.0-alpha.1
```

Or rebuild locally with `script/update_alpha.sh` and push `pool/`, `dists/`,
and `public-key.asc` to `main`.

## Install (end users)

```sh
curl -fsSL https://apt.abhik.ai/public-key.asc \
  | sudo gpg --dearmor -o /usr/share/keyrings/unfocus-archive-keyring.gpg
echo 'deb [arch=amd64 signed-by=/usr/share/keyrings/unfocus-archive-keyring.gpg] https://apt.abhik.ai alpha main' \
  | sudo tee /etc/apt/sources.list.d/unfocus-alpha.list
sudo apt update
sudo apt install unfocus
```
