#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${SCRIPT_DIR}"
TARGET_DIR="/Users/cusgadmin/Library/Application Support/ModrinthApp/profiles/Fabric 1.19.2/mods/"

MOD_VERSION=$(grep '^mod_version=' "${PROJECT_DIR}/gradle.properties" | cut -d'=' -f2)
JAR_NAME="monkeycraft-${MOD_VERSION}.jar"
SOURCE_JAR="${PROJECT_DIR}/build/libs/${JAR_NAME}"
TARGET_JAR="${TARGET_DIR}/${JAR_NAME}"

echo "Building Monkeycraft mod (1.19.2)..."
cd "${PROJECT_DIR}"
./gradlew --no-daemon spotlessApply
./gradlew --no-daemon clean build

if [ ! -f "${SOURCE_JAR}" ]; then
    echo "Error: Build artifact not found at ${SOURCE_JAR}"
    exit 1
fi

echo "Creating target directory if it doesn't exist..."
mkdir -p "${TARGET_DIR}"

echo "Copying jar to ${TARGET_DIR}..."
cp -f "${SOURCE_JAR}" "${TARGET_JAR}"

echo "Verifying copied jar integrity..."
if ! unzip -t "${TARGET_JAR}" > /dev/null 2>&1; then
    echo "Error: Copied jar is corrupted!"
    rm -f "${TARGET_JAR}"
    exit 1
fi

echo "Build and deployment complete!"
echo "Jar copied to: ${TARGET_JAR}"
