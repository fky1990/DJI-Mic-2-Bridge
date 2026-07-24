#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
build_dir="$script_dir/build"
app_dir="$build_dir/DJI Mic 2 Bridge.app"
contents_dir="$app_dir/Contents"

mkdir -p "$contents_dir/MacOS" "$contents_dir/Resources"
clang -fobjc-arc -O2 -mmacosx-version-min=13.0 -arch arm64 -arch x86_64 \
  -framework AppKit -framework AVFoundation -framework CoreAudio -framework IOBluetooth \
  "$script_dir/AppDelegate.m" -o "$contents_dir/MacOS/DJIMicBridge"
cp "$script_dir/Info.plist" "$contents_dir/Info.plist"
codesign --force --sign - "$app_dir"
echo "$app_dir"
