import argparse
import hashlib
import json
import os
from pathlib import Path
import shlex
import subprocess


IOS = Path(__file__).resolve().parents[1]
APP = IOS.parent
PRODUCT = IOS / "third_party/libtailscale/out/libtailscale_ios.a"
DIAGNOSTIC = IOS / "tailscale_diagnostics/out/libtailscale_ios_diagnostic.a"
PRODUCT_SHA256 = "ead2e2938edba8eb9ef55aa7bd8027bd25cd2901c2df9da0e6a6c603a2e8beb9"
BUNDLE_ID = "com.chenweikeng.monkeycraft"


def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def all_settings(command):
    result = subprocess.run(
        command + ["-showBuildSettings", "-json"],
        cwd=APP,
        check=True,
        capture_output=True,
        text=True,
    )
    return json.loads(result.stdout)


def runner_settings(command):
    return next(
        item["buildSettings"]
        for item in all_settings(command)
        if item["target"] == "Runner"
    )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check-only", action="store_true")
    parser.add_argument("--skip-flutter-config", action="store_true")
    options = parser.parse_args()
    if digest(PRODUCT) != PRODUCT_SHA256:
        raise RuntimeError("Original product archive has changed")
    if not DIAGNOSTIC.is_file():
        raise RuntimeError("Build the separate diagnostic archive first")
    subprocess.run(
        ["bash", str(IOS / "third_party/libtailscale/build.sh"), "link-config"],
        check=True,
    )
    output = APP / "build/ios-tailscale-diagnostics"
    output.mkdir(parents=True, exist_ok=True)
    flutter = Path(os.environ.get(
        "MONKEYCRAFT_FLUTTER", str(APP.parents[2] / "flutter/bin/flutter")
    ))
    if not options.skip_flutter_config:
        subprocess.run(
            [str(flutter), "build", "ios", "--release", "--config-only"],
            cwd=APP,
            check=True,
        )
    base = [
        "xcodebuild", "-workspace", "ios/Runner.xcworkspace", "-scheme", "Runner",
        "-configuration", "Release", "-sdk", "iphoneos",
        "-destination", "generic/platform=iOS", "-derivedDataPath", str(output),
    ]
    settings = runner_settings(base)
    if settings["PRODUCT_BUNDLE_IDENTIFIER"] != BUNDLE_ID:
        raise RuntimeError("Unexpected bundle identifier")
    flags = shlex.split(settings["OTHER_LDFLAGS"])
    if flags.count(str(PRODUCT)) != 1:
        raise RuntimeError("Expected exactly one original archive in linker flags")
    expected_flags = flags.copy()
    expected_flags[expected_flags.index(str(PRODUCT))] = str(DIAGNOSTIC)
    conditions = shlex.split(settings.get("SWIFT_ACTIVE_COMPILATION_CONDITIONS", ""))
    for condition in ["MONKEYCRAFT_TAILSCALE_TIMING", "MONKEYCRAFT_TAILSCALE_DIAGNOSTIC_ARCHIVE"]:
        if condition not in conditions:
            conditions.append(condition)
    definitions = shlex.split(settings.get("GCC_PREPROCESSOR_DEFINITIONS", ""))
    definitions.append("MONKEYCRAFT_TAILSCALE_DIAGNOSTIC_ARCHIVE=1")
    overrides = [
        "MONKEYCRAFT_LIBTAILSCALE_IOS_ARCHIVE=" + str(DIAGNOSTIC),
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS=" + " ".join(conditions),
        "GCC_PREPROCESSOR_DEFINITIONS=" + " ".join(definitions),
    ]
    effective = runner_settings(base + overrides)
    effective_flags = shlex.split(effective["OTHER_LDFLAGS"])
    if effective_flags != expected_flags:
        raise RuntimeError("Diagnostic build would link the wrong archive")
    if effective["PRODUCT_BUNDLE_IDENTIFIER"] != BUNDLE_ID:
        raise RuntimeError("Diagnostic build would change the bundle identifier")
    pods = all_settings([
        "xcodebuild", "-project", "ios/Pods/Pods.xcodeproj", "-alltargets",
        "-configuration", "Release", "-sdk", "iphoneos",
    ] + overrides)
    for pod in pods:
        pod_flags = shlex.split(pod["buildSettings"].get("OTHER_LDFLAGS", ""))
        if str(PRODUCT) in pod_flags or str(DIAGNOSTIC) in pod_flags:
            raise RuntimeError("Go archive unexpectedly linked into " + pod["target"])
    (output / "diagnostic-build-settings.json").write_text(json.dumps({
        "configuration": effective["CONFIGURATION"],
        "bundleIdentifier": effective["PRODUCT_BUNDLE_IDENTIFIER"],
        "productArchiveSHA256": digest(PRODUCT),
        "diagnosticArchiveSHA256": digest(DIAGNOSTIC),
        "linkerFlags": effective_flags,
        "swiftConditions": effective["SWIFT_ACTIVE_COMPILATION_CONDITIONS"],
        "podTargetsWithoutGoArchive": len(pods),
    }, indent=2) + "\n")
    if options.check_only:
        print("Verified Release configuration with only the diagnostic archive")
        return
    subprocess.run(base + overrides + ["clean", "build"], cwd=APP, check=True)
    if digest(PRODUCT) != PRODUCT_SHA256:
        raise RuntimeError("Original product archive changed during build")
    package = Path(effective["CONFIGURATION_BUILD_DIR"]) / "Runner.app"
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(package)], check=True)
    print(f"Signed diagnostic Release: {package}")


if __name__ == "__main__":
    main()
