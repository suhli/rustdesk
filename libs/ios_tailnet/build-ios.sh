#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
out="../../flutter/ios/IosEnhancements"
sdk="$(xcrun --sdk iphoneos --show-sdk-path)"
export GOOS=ios GOARCH=arm64 CGO_ENABLED=1
export CC="$(xcrun --sdk iphoneos --find clang)"
export CGO_CFLAGS="-isysroot $sdk -arch arm64 -miphoneos-version-min=13.0"
export CGO_LDFLAGS="$CGO_CFLAGS -framework Security -framework CoreFoundation -framework SystemConfiguration -lresolv"
go build -mod=readonly -trimpath -buildmode=c-archive -o "$out/libEmbeddedTailnet.a" ./cmd/ios
test -s "$out/libEmbeddedTailnet.a"
python3 ../../scripts/ios_licenses.py "$out/THIRD-PARTY-NOTICES.txt"
