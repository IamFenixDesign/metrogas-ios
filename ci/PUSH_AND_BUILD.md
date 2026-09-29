# Push Metrogas iOS to GitHub and build IPA

The CI workflow is already in the tree:
`.github/workflows/ios-ipa.yml`

## One-shot (machine with `gh` authenticated)

```bash
cd /path/to/Metrogas   # or extract artifacts/metrogas-ios.tar.gz
gh auth login          # if needed
gh repo create metrogas-ios --public --source=. --remote=origin --push
gh workflow run ios-ipa.yml
gh run watch
gh run list --workflow=ios-ipa.yml
# then:
gh run download <RUN_ID> -n Metrogas-ipa
```

## GitHub website (no CLI)

1. Create a new empty repo (e.g. `metrogas-ios`) on github.com.
2. Upload / push this project (or use GitHub’s “uploading an existing file” / Codespaces).
3. Open **Actions** → enable workflows if prompted → **Build Metrogas IPA** → **Run workflow**.
4. Download artifact **Metrogas-ipa**.

## Device login started by the agent

If a cloud agent printed a one-time device code, open:
https://github.com/login/device
and enter the code to authorize `gh` on that VM, then re-run the push/workflow steps.
