#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${SCRIPT_DIR}"
TARGET_DIR="/Users/cusgadmin/.lunarclient/profiles/modrinth/imaginefun/versions/0.0.6/mods/fabric-1.21.11"

JAR_NAME="monkeycraft-1.0.0.jar"
SOURCE_JAR="${PROJECT_DIR}/build/libs/${JAR_NAME}"
TARGET_JAR="${TARGET_DIR}/${JAR_NAME}"

echo "Building Monkeycraft mod..."
cd "${PROJECT_DIR}"
./gradlew spotlessApply
./gradlew clean build

if [ ! -f "${SOURCE_JAR}" ]; then
    echo "Error: Build artifact not found at ${SOURCE_JAR}"
    exit 1
fi

echo "Creating target directory if it doesn't exist..."
mkdir -p "${TARGET_DIR}"

echo "Copying jar to ${TARGET_DIR}..."
cp -f "${SOURCE_JAR}" "${TARGET_JAR}"

echo "Build and deployment complete!"
echo "Jar copied to: ${TARGET_JAR}"
