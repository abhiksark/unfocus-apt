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
| Stable | `unfocus-stable-published` | `pool/stable/u/unfocus` | `dists/stable` |

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

The source repository uses this token in its alpha, beta, and stable APT
dispatch workflows. No new secret is required for stable.

## First or recovery publish

On `abhiksark/unfocus`, use the workflow matching the release channel. These
guarded source workflows verify the tag and source commit before dispatching
the downstream update:

```text
Actions → Dispatch APT alpha update → Run workflow → vX.Y.Z-alpha.N
Actions → Dispatch APT beta update  → Run workflow → vX.Y.Z-beta.N
Actions → Dispatch APT stable update → Run workflow → vX.Y.Z
```

The release must already be published, immutable, and non-draft with the exact
channel state and matching Debian version (`X.Y.Z~alpha.N-1`,
`X.Y.Z~beta.N-1`, or stable `X.Y.Z-1`). The downstream APT workflows do not accept manual runs. A
source-workflow redispatch of identical immutable artifacts is a no-op.

For local recovery, invoke `script/update_repo.sh` with `--channel alpha`,
`--channel beta`, or `--channel stable` and the same inputs used by the
workflow as a separately reviewed operator action, then review and push only
that channel's pool, suite metadata, and `public-key.asc`.

## Install beta (end users)

Stable commands remain pending until the first stable release and receiver
updates are published. Then disable the beta source without purging Unfocus,
add the `stable` suite as `unfocus-stable.list`, and run `apt update` followed
by `apt install unfocus`; local application data remains in place.

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
