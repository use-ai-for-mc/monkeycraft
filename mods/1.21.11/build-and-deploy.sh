#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${SCRIPT_DIR}"
TARGET_DIR="/Users/cusgadmin/Library/Application Support/PrismLauncher/instances/ImagineFun/.minecraft/mods/"

MOD_VERSION=$(grep '^mod_version=' "${PROJECT_DIR}/gradle.properties" | cut -d'=' -f2)
JAR_NAME="monkeycraft-${MOD_VERSION}.jar"
SOURCE_JAR="${PROJECT_DIR}/build/libs/${JAR_NAME}"
TARGET_JAR="${TARGET_DIR}/${JAR_NAME}"
STAGING_JAR="${TARGET_JAR}.new"

FLUTTER="${FLUTTER:-/Users/cusgadmin/if-local/flutter/bin/flutter}"

MONKEYCRAFT_PAGES_PROVENANCE=0 FLUTTER_BIN="${FLUTTER}" \
    "${SCRIPT_DIR}/../../flutter/monkeycraft/tool/build_web_release.sh" / build/web

"${SCRIPT_DIR}/../../native/tailscale-helper/scripts/build-all.sh"

echo "Building Monkeycraft mod (1.21.11)..."
cd "${PROJECT_DIR}"
./gradlew --no-daemon spotlessApply
./gradlew --no-daemon clean build

if [ ! -f "${SOURCE_JAR}" ]; then
    echo "Error: Build artifact not found at ${SOURCE_JAR}"
    exit 1
fi

INSTANCE_DIR="$(dirname "$(dirname "${TARGET_DIR%/}")")"
if [ ! -f "${INSTANCE_DIR}/mmc-pack.json" ]; then
    echo "Error: ${INSTANCE_DIR} is not a PrismLauncher instance (mmc-pack.json missing)."
    echo "Refusing to deploy — check TARGET_DIR in this script."
    exit 1
fi

# Atomic deploy: stage as <target>.new on the same filesystem, verify, retry on
# failure, then rename(2) into place. The rename preserves the old inode for
# any running JVM that already opened the target jar via ZipFile, so we never
# corrupt a live game.
MAX_ATTEMPTS=3
attempt=1
while true; do
    echo "Staging jar at ${STAGING_JAR} (attempt ${attempt}/${MAX_ATTEMPTS})..."
    cp -f "${SOURCE_JAR}" "${STAGING_JAR}"

    if unzip -tq "${STAGING_JAR}" > /dev/null 2>&1; then
        break
    fi

    if [ "${attempt}" -ge "${MAX_ATTEMPTS}" ]; then
        echo "Error: Staged jar failed integrity check ${MAX_ATTEMPTS}× — aborting; existing target untouched"
        rm -f "${STAGING_JAR}"
        exit 1
    fi
    echo "Integrity check failed; retrying..."
    attempt=$((attempt + 1))
done

echo "Atomically replacing ${TARGET_JAR}..."
mv -f "${STAGING_JAR}" "${TARGET_JAR}"

echo "Build and deployment complete!"
echo "Jar deployed to: ${TARGET_JAR}"
