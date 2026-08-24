# Operator setup for unfocus-apt

## Custom domain (apt.abhik.ai)

GitHub Pages serves **`https://apt.abhik.ai`**. DNS CNAME:

| Type | Host | Answer |
| --- | --- | --- |
| CNAME | `apt` | `abhiksark.github.io` |

Enforce HTTPS in Settings → Pages after the certificate is issued.

## Channels and paths

| Channel | Dispatch | Package pool | Suite metadata |
| --- | --- | --- | --- |
| Alpha (frozen) | `unfocus-alpha-published` | `pool/main/u/unfocus` | `dists/alpha` |
| Beta | `unfocus-beta-published` | `pool/beta/u/unfocus` | `dists/beta` |

Both update workflows use the `update-unfocus-apt` concurrency group with
`cancel-in-progress: false`. Keep that group shared so their direct pushes to
`main` cannot race.

## Secrets (environment `apt-repo-automation`)

### On `abhiksark/unfocus-apt`

| Secret | Purpose |
| --- | --- |
| `APT_SIGNING_KEY` | Armored private key for the APT archive |
| `APT_SIGNING_KEY_PASSPHRASE` | Optional; only if the private key is passphrase-protected |

The same key signs both suites and their detached package signatures. The
public half is committed as `public-key.asc` and served at
`https://apt.abhik.ai/public-key.asc`.

### On `abhiksark/unfocus`

| Secret | Purpose |
| --- | --- |
| `APT_DISPATCH_TOKEN` | Token limited to creating `repository_dispatch` events on `unfocus-apt` |

The source repository uses this token in its alpha and beta APT dispatch
workflows. No new secret is required for beta.

## First or recovery publish

Use the workflow matching the release channel:

```text
Actions → Update alpha apt repository → Run workflow → vX.Y.Z-alpha.N
Actions → Update beta apt repository  → Run workflow → vX.Y.Z-beta.N
```

The release must already be a published, non-draft prerelease with the exact
channel tag and a matching Debian version (`X.Y.Z~alpha.N-1` or
`X.Y.Z~beta.N-1`). A manual redispatch of identical immutable artifacts is a
no-op.

For local recovery, invoke either `script/update_repo.sh --channel alpha` or
`script/update_repo.sh --channel beta` with the same inputs used by the
workflow, then review and push only that channel's pool, suite metadata, and
`public-key.asc`.

## Install beta (end users)

```sh
curl -fsSL https://apt.abhik.ai/public-key.asc \
  | sudo gpg --dearmor -o /usr/share/keyrings/unfocus-archive-keyring.gpg
echo 'deb [arch=amd64 signed-by=/usr/share/keyrings/unfocus-archive-keyring.gpg] https://apt.abhik.ai beta main' \
  | sudo tee /etc/apt/sources.list.d/unfocus-beta.list
sudo apt update
sudo apt install unfocus
```

## Migrate alpha users to beta

```sh
sudo rm -f /etc/apt/sources.list.d/unfocus-alpha.list
echo 'deb [arch=amd64 signed-by=/usr/share/keyrings/unfocus-archive-keyring.gpg] https://apt.abhik.ai beta main' \
  | sudo tee /etc/apt/sources.list.d/unfocus-beta.list
sudo apt update
sudo apt install --only-upgrade unfocus
```
