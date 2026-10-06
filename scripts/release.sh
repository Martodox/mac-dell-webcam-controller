#!/bin/bash
# Builds, signs (Developer ID), notarizes and staples a release DMG, then commits it to dist/.
# Pushing that commit to main makes .github/workflows/release.yml publish it as a GitHub release.
#
# Usage: scripts/release.sh <version>       e.g. scripts/release.sh 1.0.0
#
# One-time setup: a "Developer ID Application" certificate in the login keychain, and
#   xcrun notarytool store-credentials dell-camera-notary --apple-id <id> --team-id RM9V8M9NAZ
set -euo pipefail

VERSION="${1:-}"
TEAM_ID="RM9V8M9NAZ"
SIGN_ID="${SIGN_ID:-Developer ID Application: Bartosz Jakubowiak (${TEAM_ID})}"
NOTARY_PROFILE="${NOTARY_PROFILE:-dell-camera-notary}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${ROOT}/build/release"
DIST="${ROOT}/dist"
PANE_NAME="Dell camera.prefPane"
DMG_NAME="Dell-camera.dmg"

step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
fail() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

cd "${ROOT}"

step "Preflight"
[[ "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "usage: scripts/release.sh <major.minor.patch>"
[ -z "$(git status --porcelain)" ] || fail "working tree is not clean"
[ "$(git branch --show-current)" = "main" ] || fail "releases are cut from main"
CURRENT="0.0.0"
[ -f "${DIST}/VERSION" ] && CURRENT="$(tr -d '[:space:]' < "${DIST}/VERSION")"
if [ "${CURRENT}" = "${VERSION}" ] || [ "$(printf '%s\n%s\n' "${CURRENT}" "${VERSION}" | sort -V | tail -1)" != "${VERSION}" ]; then
  fail "version ${VERSION} must be greater than the last release ${CURRENT}"
fi
identities="$(security find-identity -v -p codesigning)"
grep -qF "${SIGN_ID}" <<< "${identities}" || fail "signing identity not found: ${SIGN_ID}"
xcrun notarytool history --keychain-profile "${NOTARY_PROFILE}" >/dev/null \
  || fail "notarytool profile '${NOTARY_PROFILE}' is missing or invalid"
BUILD_NUMBER="$(git rev-list --count HEAD)"
echo "Releasing ${VERSION} (build ${BUILD_NUMBER}), previous ${CURRENT}"

step "Tests"
swift test --package-path CameraKit

step "Build"
rm -rf "${BUILD}"
mkdir -p "${BUILD}"
LOG="${BUILD}/xcodebuild.log"
if ! xcodebuild -project "Dell Camera Configurator.xcodeproj" -scheme "Dell Camera Configurator" \
  -configuration Release -derivedDataPath "${BUILD}/DerivedData" \
  MARKETING_VERSION="${VERSION}" CURRENT_PROJECT_VERSION="${BUILD_NUMBER}" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="${SIGN_ID}" DEVELOPMENT_TEAM="${TEAM_ID}" \
  OTHER_CODE_SIGN_FLAGS=--timestamp ONLY_ACTIVE_ARCH=NO \
  clean build > "${LOG}" 2>&1; then
  grep -E "error:|BUILD FAILED" "${LOG}" | tail -20 >&2
  fail "xcodebuild failed, full log: ${LOG}"
fi
PANE="${BUILD}/DerivedData/Build/Products/Release/${PANE_NAME}"
AGENT="${PANE}/Contents/Resources/Dell Camera Agent.app"

step "Verify signatures"
codesign --verify --deep --strict --verbose=2 "${PANE}"
for bundle in "${PANE}" "${AGENT}"; do
  # Capture first: piping into grep -q would SIGPIPE codesign and trip pipefail.
  info="$(codesign -dvv "${bundle}" 2>&1)"
  grep -qF "Authority=${SIGN_ID}" <<< "${info}" || fail "${bundle##*/} is not signed by ${SIGN_ID}"
  grep -q "^Timestamp=" <<< "${info}" || fail "${bundle##*/} has no secure timestamp"
done
for binary in "${PANE}/Contents/MacOS/Dell camera" "${AGENT}/Contents/MacOS/DellCameraAgent"; do
  archs="$(lipo -archs "${binary}")"
  [[ "${archs}" == *arm64* && "${archs}" == *x86_64* ]] || fail "${binary##*/} is not universal (${archs})"
done

step "Create DMG"
STAGING="${BUILD}/dmg"
DMG="${BUILD}/${DMG_NAME}"
mkdir -p "${STAGING}"
ditto "${PANE}" "${STAGING}/${PANE_NAME}"
cat > "${STAGING}/Install.txt" <<EOF
Dell camera ${VERSION}

Double-click "Dell camera.prefPane" to add it to System Settings.
It appears at the bottom of the System Settings sidebar.
EOF
hdiutil create -volname "Dell camera" -srcfolder "${STAGING}" -fs HFS+ -format UDZO -ov "${DMG}"
codesign --force --timestamp --sign "${SIGN_ID}" "${DMG}"

step "Notarize"
RESULT="$(xcrun notarytool submit "${DMG}" --keychain-profile "${NOTARY_PROFILE}" --wait --output-format json)"
echo "${RESULT}"
STATUS="$(plutil -extract status raw - <<< "${RESULT}")"
if [ "${STATUS}" != "Accepted" ]; then
  xcrun notarytool log "$(plutil -extract id raw - <<< "${RESULT}")" --keychain-profile "${NOTARY_PROFILE}" || true
  fail "notarization finished with status ${STATUS}"
fi

step "Staple and assess"
xcrun stapler staple "${DMG}"
xcrun stapler validate "${DMG}"
spctl --assess --type open --context context:primary-signature --verbose=2 "${DMG}"

step "Update dist/"
git fetch --tags --quiet 2>/dev/null || true
PREVIOUS_TAG="$(git describe --tags --abbrev=0 2>/dev/null || true)"
mkdir -p "${DIST}"
cp -f "${DMG}" "${DIST}/${DMG_NAME}"
(cd "${DIST}" && shasum -a 256 "${DMG_NAME}" > "${DMG_NAME}.sha256")
echo "${VERSION}" > "${DIST}/VERSION"
{
  echo "## Install"
  echo
  echo "Open the DMG and double-click **Dell camera.prefPane**. Requires macOS 14 or later."
  echo
  echo "## Changes"
  echo
  git log --no-merges --format='- %s' ${PREVIOUS_TAG:+"${PREVIOUS_TAG}..HEAD"} -- . ':!dist' \
    | grep -v '^- release: ' || echo "- Initial release"
} > "${DIST}/RELEASE_NOTES.md"

git add "${DIST}"
git commit --quiet -m "release: v${VERSION}"
step "Committed release v${VERSION}. Push main to publish it: git push origin main"
