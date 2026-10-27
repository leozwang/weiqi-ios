#!/bin/zsh
# Full pre-release test run for Weiqi. Run this before every App Store release.
#
#   scripts/run_tests.sh                         # iPhone 17 + iPad mini (A17 Pro), iOS 26.2
#   scripts/run_tests.sh "iPhone 17 Pro"         # pick other simulators by name
#   OS=26.0 scripts/run_tests.sh                 # use another simulator iOS version
#   CONFIG=Premium scripts/run_tests.sh          # one test-plan configuration (default: both)
#   SKIP_DEVICE_BUILD=1 scripts/run_tests.sh     # skip the Release build for real devices
#
# For every simulator the whole suite (WeiqiTests + WeiqiUITests) runs in both configurations of
# Weiqi.xctestplan: "Free" (Unlock Elite Levels not bought: Advanced/Pro locked) and "Premium"
# (bought: Advanced/Pro playable). Then the Release configuration is built for generic iOS devices
# (what App Store archives use). Results: build/TestResults/.
#
# The iOS 27.0 *simulator* cannot run the Metal (GPU) backend: Apple's simulator Metal driver
# asserts inside MPSGraph (MTLSimDevice newHeapWithDescriptor:) and the app aborts. Real
# devices are not affected. Hence the 26.2 default.
set -u
cd "${0:A:h}/.."
# Keep the Mac and display awake for the whole run: macOS idle/display sleep freezes the
# simulator mid-test and causes XCUITest event synthesis timeouts.
caffeinate -dimsu -w $$ &

devices=("$@")
(( ${#devices} )) || devices=("iPhone 17" "iPad mini (A17 Pro)")
os=${OS:-26.2}
case ${CONFIG:-both} in
  both) configs=(Free Premium) ;;
  Free|Premium) configs=($CONFIG) ;;
  *) echo "CONFIG must be Free, Premium or both"; exit 2 ;;
esac
out=build/TestResults
mkdir -p "$out"
failed=()

echo "==> xcodegen generate"
xcodegen generate --quiet || exit 1

# Simulator UDID for a device name and iOS version ("latest" = newest runtime).
simulator_udid() {
  xcrun simctl list devices available -j | python3 -c '
import json, sys
name, os_ver = sys.argv[1], sys.argv[2]
runtimes = sorted(json.load(sys.stdin)["devices"].items(), reverse=True)
for runtime, devs in runtimes:
    if "iOS" not in runtime or (os_ver != "latest" and not runtime.endswith("iOS-" + os_ver.replace(".", "-"))):
        continue
    for d in devs:
        if d["name"] == name:
            print(d["udid"]); sys.exit()
' "$1" "$2"
}

for dev in "${devices[@]}"; do
  udid=$(simulator_udid "$dev" "$os")
  if [[ -z "$udid" ]]; then
    echo "==> No simulator named '$dev' with iOS $os"; failed+=("$dev (no simulator)"); continue
  fi
  # Boot first: launching tests on a simulator that is still booting fails with
  # "Application failed preflight checks".
  xcrun simctl boot "$udid" 2>/dev/null
  xcrun simctl bootstatus "$udid" -b > /dev/null 2>&1
  for config in "${configs[@]}"; do
    # Clean install for every run: when xcodebuild reinstalls over the app of the previous run,
    # the simulator's StoreKit test service can keep pointing at the replaced bundle and fail
    # every purchase ("Unable to Complete Request"). It also starts each run as a new user.
    xcrun simctl terminate "$udid" com.cwave.weiqi > /dev/null 2>&1
    xcrun simctl uninstall "$udid" com.cwave.weiqi > /dev/null 2>&1
    slug=${dev//[^A-Za-z0-9]/_}_$config
    rm -rf "$out/$slug.xcresult"
    echo "==> Testing on $dev (iOS $os), test plan configuration $config"
    # -collect-test-diagnostics never: otherwise xcodebuild may run `simctl diagnose` for up to
    # 10 minutes after the tests finish.
    xcodebuild test -project Weiqi.xcodeproj -scheme Weiqi -testPlan Weiqi -only-test-configuration "$config" \
      -destination "id=$udid" \
      -collect-test-diagnostics never \
      -resultBundlePath "$out/$slug.xcresult" > "$out/$slug.log" 2>&1
    code=$?
    grep -E "Test Case .*(passed|failed|skipped)|: error: " "$out/$slug.log" \
      | sed -E "s/^.*Test Case '-\[([A-Za-z]+)\.([A-Za-z]+) ([A-Za-z0-9_]+)\]' (passed|failed|skipped).*/  \4  \2.\3/; s/^.*\/([A-Za-z]+\.swift:[0-9]+: error: )/  \1/" \
      | sort -u
    grep -E "Executed [0-9]+ tests" "$out/$slug.log" | tail -1 | sed 's/^[[:space:]]*/  /'
    if (( code == 0 )); then
      echo "  PASS: $dev, $config"
    else
      echo "  FAIL: $dev, $config (log: $out/$slug.log)"
      failed+=("$dev/$config")
    fi
  done
done

if [[ -z "${SKIP_DEVICE_BUILD:-}" ]]; then
  echo "==> Release build for generic iOS devices"
  if xcodebuild build -project Weiqi.xcodeproj -scheme Weiqi -configuration Release \
       -destination "generic/platform=iOS" CODE_SIGNING_ALLOWED=NO > "$out/release-device-build.log" 2>&1; then
    echo "  PASS: Release device build"
    # The built app: its version must be the one in project.yml, and the Debug-only test hooks
    # (purchase pin, reset, engine status) must not be in it.
    app_dir=$(xcodebuild -project Weiqi.xcodeproj -scheme Weiqi -configuration Release -destination "generic/platform=iOS" \
      -showBuildSettings 2>/dev/null | awk -F' = ' '$1 ~ / TARGET_BUILD_DIR$/ {print $2; exit}')/Weiqi.app
    yml_version() { awk -v key="$1:" '$1 == key {gsub(/"/, "", $2); print $2; exit}' project.yml; }
    want="$(yml_version MARKETING_VERSION) ($(yml_version CURRENT_PROJECT_VERSION))"
    built="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_dir/Info.plist" 2>/dev/null) ($(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app_dir/Info.plist" 2>/dev/null))"
    if [[ "$built" == "$want" ]]; then
      echo "  PASS: Release version $built (project.yml)"
    else
      echo "  FAIL: Release version '$built', project.yml says '$want'"; failed+=("Release version")
    fi
    hooks=$(strings "$app_dir/Weiqi" 2>/dev/null | grep -E "WEIQI_UITEST_(PURCHASED|RESET)|refused=" | sort -u)
    if [[ -f "$app_dir/Weiqi" && -z "$hooks" ]]; then
      echo "  PASS: no Debug test hooks in the Release binary"
    else
      echo "  FAIL: Release binary missing or contains Debug test hooks: ${hooks:-no binary at $app_dir}"; failed+=("Release test hooks")
    fi
  else
    grep -E ": error: " "$out/release-device-build.log" | head -5
    echo "  FAIL: Release device build (log: $out/release-device-build.log)"; failed+=("Release device build")
  fi
fi

if (( ${#failed} )); then
  echo "==> FAILED: ${(j:, :)failed}"
  exit 1
fi
echo "==> ALL PASSED"
