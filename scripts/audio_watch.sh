#!/bin/bash
# Run by launchd whenever a Cinco backup changes in iCloud Drive (see install_audio_watch.sh).
# Records new words, removes recordings for words that are gone, and pushes the audio so the phone gets it.
# Only audio/ is committed, so unrelated work in progress in the repo is never swept into these commits.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
PY=/opt/anaconda3/bin/python3
GIT=/opt/homebrew/bin/git
cd "$REPO" || exit 1
echo "--- $(date '+%Y-%m-%d %H:%M:%S') backup changed"

# iCloud writes the backup in pieces; give it a moment to finish before reading it.
sleep "${CINCO_SETTLE:-20}"

"$PY" scripts/make_audio.py || { echo "make_audio failed"; exit 1; }

if [ -z "$("$GIT" status --porcelain -- audio)" ]; then
  echo "no new audio"
  exit 0
fi
"$GIT" add -A -- audio
"$GIT" commit -q -m "Audio from phone backup" -- audio || exit 1
"$GIT" pull -q --rebase --autostash || { echo "pull failed, will push next time"; exit 1; }
"$GIT" push -q && echo "pushed $("$GIT" log --oneline -1)"
