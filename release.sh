#!/bin/zsh
# Cuts a release: sets the version, builds, packages zip + dmg, tags, pushes,
# and publishes a GitHub release. Usage: ./release.sh 1.2.0 ["release notes"]
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:?usage: ./release.sh <version> [notes]}"
NOTES="${2:-JustEnter v$VERSION}"

if [[ -n "$(git status --porcelain)" ]]; then
    echo "✗ Working tree not clean — commit your changes first."
    exit 1
fi

echo "→ setting version $VERSION"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" Resources/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(git rev-list --count HEAD)" Resources/Info.plist

./build.sh

echo "→ packaging"
rm -rf dist && mkdir dist
ditto -ck --keepParent /Applications/JustEnter.app dist/JustEnter.zip

STAGE="$(mktemp -d)/JustEnter"
mkdir -p "$STAGE"
cp -R /Applications/JustEnter.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "JustEnter" -srcfolder "$STAGE" -ov -format UDZO dist/JustEnter.dmg -quiet

echo "→ committing, tagging, pushing"
git add Resources/Info.plist
git commit -m "Release v$VERSION

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
git tag "v$VERSION"
git push && git push --tags

echo "→ publishing GitHub release"
gh release create "v$VERSION" dist/JustEnter.zip dist/JustEnter.dmg \
    --title "JustEnter v$VERSION" \
    --notes "$NOTES"

echo "✓ Released v$VERSION — the app's update checker will pick it up."
