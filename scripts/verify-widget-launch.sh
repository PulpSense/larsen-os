#!/bin/zsh

set -euo pipefail

app_path=${1:?"usage: verify-widget-launch.sh /path/to/Digital Wall.app [url-scheme]"}
url_scheme=${2:-digitalwall2}
app_name=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$app_path/Contents/Info.plist")
lsregister='/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'

cleanup() {
    pkill -x "$app_name" 2>/dev/null || true
}
trap cleanup EXIT

"$lsregister" -f -R -trusted "$app_path"
cleanup
sleep 0.7
open "$url_scheme://show-board"
sleep 2

APP_OWNER="$app_name" swift - <<'SWIFT'
import CoreGraphics
import Foundation

let owner = ProcessInfo.processInfo.environment["APP_OWNER"]!
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
    as? [[String: Any]] ?? []
let boardIsVisible = windows.contains { window in
    let isOwnedByApp = window[kCGWindowOwnerName as String] as? String == owner
    let isUntitled = (window[kCGWindowName as String] as? String ?? "").isEmpty
    let isElevated = (window[kCGWindowLayer as String] as? Int ?? 0) > 0
    return isOwnedByApp && isUntitled && isElevated
}

guard boardIsVisible else {
    fputs("FAIL: widget URL did not leave the vision-board panel visible\n", stderr)
    exit(1)
}

print("PASS: widget URL left the vision-board panel visible")
SWIFT
