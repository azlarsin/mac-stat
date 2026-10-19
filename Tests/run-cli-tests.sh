#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d /tmp/macstat-cli-test-build.XXXXXX)
trap 'rm -rf "$test_dir"' EXIT

swiftc -parse-as-library -emit-library -emit-module -enable-testing -module-name MacStat \
    MacStat/MacStat/*.swift \
    -emit-module-path "$test_dir/MacStat.swiftmodule" -o "$test_dir/libMacStat.dylib"
swiftc -parse-as-library Tests/SettingsCLITests.swift \
    -I "$test_dir" -L "$test_dir" -lMacStat \
    -Xlinker -rpath -Xlinker "$test_dir" -o "$test_dir/cli-tests"
"$test_dir/cli-tests"
