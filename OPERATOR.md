# Operator setup for unfocus-apt


## Custom domain (apt.abhik.ai)

GitHub Pages is configured for **`apt.abhik.ai`**. At your DNS host (Porkbun for
`abhik.ai`), add:

| Type | Host | Answer |
| --- | --- | --- |
| CNAME | `apt` | `abhiksark.github.io` |

Do **not** point `apt` at Vercel. The APT tree is served by GitHub Pages so
binary packages and signed `InRelease` files stay static and correctly typed.

After DNS propagates, in the GitHub repo: Settings → Pages → verify the domain
and enable **Enforce HTTPS**.

Confirm:

```sh
curl -fsSL https://apt.abhik.ai/ | head
curl -fsSLI https://apt.abhik.ai/dists/alpha/InRelease
```

## 1. Archive GPG key

Generate a dedicated APT archive key (do not reuse a personal key):

```sh
gpg --quick-generate-key "Unfocus APT Archive <apt@unfocus.example>" ed25519 sign 0
# export
gpg --armor --export "Unfocus APT Archive" > public-key.asc
gpg --armor --export-secret-keys "Unfocus APT Archive" > apt-signing-key.asc
```

Store `apt-signing-key.asc` contents as environment secret `APT_SIGNING_KEY` on
this repository’s `apt-repo-automation` environment. If the key has a
passphrase, store it as `APT_SIGNING_KEY_PASSPHRASE`. Commit `public-key.asc`
on the first successful package update (the updater writes it).

## 2. GitHub App

Create or install a GitHub App on **only** `abhiksark/unfocus-apt` with
Contents and Pull Requests read/write. Put `APT_APP_ID` and
`APT_APP_PRIVATE_KEY` in the same `apt-repo-automation` environment.

On `abhiksark/unfocus`, store the same App credentials as `APT_APP_ID` and
`APT_APP_PRIVATE_KEY` in environment `apt-repo-automation` so the source repo
can dispatch repository events (Contents write is scoped to unfocus-apt only
when minting the token).

## 3. GitHub Pages

Settings → Pages → Build and deployment → Deploy from branch **main** / **/**.

After the first merged package PR, confirm:

`https://apt.abhik.ai/dists/alpha/InRelease`

## 4. First publish

From `abhiksark/unfocus`, run workflow **Dispatch APT alpha update** with a
published prerelease tag (for example `v0.3.0-alpha.1`), or publish a new
prerelease. Merge the automation PR in this repository, then smoke-test:

```sh
# on Ubuntu/Debian
curl -fsSL https://apt.abhik.ai/public-key.asc \
  | sudo gpg --dearmor -o /usr/share/keyrings/unfocus-archive-keyring.gpg
# … add source list, apt update, apt install unfocus
```


## 5. Install the update workflow

The initial push may omit `.github/workflows/` if the local token lacks the
`workflow` OAuth scope. After granting that scope (or using SSH with an admin
key), install the workflow:

```sh
mkdir -p .github/workflows
cp templates/github-update-alpha.yml .github/workflows/update-alpha.yml
git add .github/workflows/update-alpha.yml
git commit -m "Add alpha apt update workflow"
git push
```
