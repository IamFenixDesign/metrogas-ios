#!/usr/bin/env bash
# Run on a machine (or this VM) after `gh auth login`.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if ! gh auth status >/dev/null 2>&1; then
  echo "Not logged in. Run: gh auth login"
  echo "Or open https://github.com/login/device with the agent device code."
  exit 1
fi

NAME="${REPO_NAME:-metrogas-ios}"
VIS="${REPO_VISIBILITY:-public}"

if git remote get-url origin >/dev/null 2>&1; then
  echo "Remote origin already set: $(git remote get-url origin)"
  git push -u origin HEAD
else
  gh repo create "$NAME" --"$VIS" --source=. --remote=origin --push
fi

REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
echo "Repo: https://github.com/$REPO"

gh workflow run ios-ipa.yml -R "$REPO"
echo "Waiting for run to appear..."
sleep 6
RUN_ID=$(gh run list -R "$REPO" --workflow=ios-ipa.yml --limit 1 --json databaseId -q '.[0].databaseId')
echo "Run ID: $RUN_ID"
echo "URL: https://github.com/$REPO/actions/runs/$RUN_ID"
gh run watch "$RUN_ID" -R "$REPO" || true

mkdir -p /tmp/metrogas-ipa-dl
gh run download "$RUN_ID" -R "$REPO" -n Metrogas-ipa -D /tmp/metrogas-ipa-dl
find /tmp/metrogas-ipa-dl -name '*.ipa' -print
IPA=$(find /tmp/metrogas-ipa-dl -name '*.ipa' | head -n1)
if [ -n "$IPA" ]; then
  mkdir -p /cursor/stores/self/artifacts/metrogas-ios
  cp "$IPA" /cursor/stores/self/artifacts/metrogas-ios/Metrogas.ipa
  echo "Copied to /cursor/stores/self/artifacts/metrogas-ios/Metrogas.ipa"
fi
