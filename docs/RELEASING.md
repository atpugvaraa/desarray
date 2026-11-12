# Releasing desarray.

Every `v*` tag runs [`.github/workflows/release.yml`](../.github/workflows/release.yml):

1. unit tests → Release build signed with **Developer ID** + Hardened Runtime
2. **notarized** by Apple and stapled
3. `desarray-<version>.zip` published as a GitHub Release
4. `Casks/desarray.rb` bumped in [`atpugvaraa/homebrew-atpugvaraa`](https://github.com/atpugvaraa/homebrew-atpugvaraa)

Tags with a suffix (`v0.2.0-beta.1`) publish a GitHub **pre-release** and leave the cask alone.
**Actions › Release › Run workflow** is a dry run: unsigned build + tests, zip as an artifact, nothing published.

## Cut a release

```bash
git tag v0.1.0
git push origin v0.1.0
```

Then users install with:

```bash
brew install --cask atpugvaraa/atpugvaraa/desarray
```

## One-time setup: secrets

These hold your signing key and Apple/GitHub credentials, so you create them yourself. Never commit any of these files, and delete the local copies once they're stored as secrets.

### 1. Developer ID certificate → `DEVELOPER_ID_P12_BASE64`, `DEVELOPER_ID_P12_PASSWORD`

1. Open **Keychain Access › login › My Certificates**.
2. Right-click **Developer ID Application: Aarav Gupta (3YK32DPS3W)** › **Export…** › save as `devid.p12` with a strong password.
3. Store both:

```bash
base64 -i devid.p12 | gh secret set DEVELOPER_ID_P12_BASE64 -R atpugvaraa/desarray
gh secret set DEVELOPER_ID_P12_PASSWORD -R atpugvaraa/desarray   # paste the password when prompted
rm devid.p12
```

### 2. Notarization key → `NOTARY_KEY_P8_BASE64`, `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID`

1. [App Store Connect › Users and Access › Integrations › Team Keys](https://appstoreconnect.apple.com/access/integrations/api) › **+**, role **Developer**.
2. Download the `.p8` (only downloadable once). Note the **Key ID** and the **Issuer ID** at the top of the page.

```bash
base64 -i AuthKey_XXXXXXXXXX.p8 | gh secret set NOTARY_KEY_P8_BASE64 -R atpugvaraa/desarray
gh secret set NOTARY_KEY_ID -R atpugvaraa/desarray      # e.g. XXXXXXXXXX
gh secret set NOTARY_ISSUER_ID -R atpugvaraa/desarray   # a UUID
```

Keep the `.p8` somewhere safe (a password manager), not in the repo.

### 3. Tap token → `HOMEBREW_TAP_TOKEN`

1. [GitHub › Settings › Developer settings › Fine-grained tokens](https://github.com/settings/personal-access-tokens/new)
2. **Repository access:** only `atpugvaraa/homebrew-atpugvaraa`. **Permissions:** Contents › Read and write. Set an expiry and note it in your calendar.

```bash
gh secret set HOMEBREW_TAP_TOKEN -R atpugvaraa/desarray   # paste the token
```

Check all six are there:

```bash
gh secret list -R atpugvaraa/desarray
```

## When something fails

| Step | Usual cause |
|---|---|
| Check release secrets | A secret is missing; the error names it |
| Import Developer ID certificate | Wrong `.p12` password, or the export didn't include the private key (export from **My Certificates**, not **Certificates**) |
| Notarize and staple | The log is printed in the job; often a missing Hardened Runtime or an unsigned nested binary |
| Bump Homebrew cask | Expired `HOMEBREW_TAP_TOKEN`, or the token doesn't cover the tap repo |

A failed tag run can be retried from the Actions tab; the cask step skips itself if the cask is already at that version. To redo a release, delete the GitHub Release + tag, fix, and push the tag again.
