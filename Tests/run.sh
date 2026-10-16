#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_build_dir=$(mktemp -d "${TMPDIR:-/tmp}/wechattweak-tests.XXXXXX")
trap 'rm -rf "$test_build_dir"' EXIT
swiftc -swift-version 6 -module-cache-path "$test_build_dir/cache" \
  "$project_dir/Sources/WeChatTweak/Config.swift" \
  "$project_dir/Sources/WeChatTweak/Patcher.swift" \
  "$project_dir/Sources/WeChatTweak/Command.swift" \
  "$project_dir/Sources/WeChatTweak/Resigner.swift" \
  "$project_dir/Tests/main.swift" -o "$test_build_dir/patcher-tests"
"$test_build_dir/patcher-tests" "$project_dir"

swiftc -swift-version 6 -parse-as-library -module-cache-path "$test_build_dir/cache" \
  "$project_dir/Sources/WeChatTweak/Resigner.swift" \
  "$project_dir/Tests/ResignerChecks.swift" -o "$test_build_dir/resigner-tests"
"$test_build_dir/resigner-tests"
