#!/usr/bin/env bash
# 全体または変更済み・未追跡のSwiftファイルを整形し、lintを実行します。

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 {all|modified}" >&2
  exit 2
fi

case "$1" in
  all)
    root=$(git rev-parse --show-toplevel)
    cd "$root"
    xcrun swift-format format --in-place --recursive .
    xcrun swift-format lint --strict --recursive .
    ;;
  modified)
    root=$(git rev-parse --show-toplevel)
    cd "$root"
    tmp=$(mktemp)
    trap 'rm -f "$tmp"' EXIT
    git ls-files -m -o --exclude-standard -z -- '*.swift' > "$tmp"
    while IFS= read -r -d '' file; do
      [[ -f "$file" ]] || continue
      if ! xcrun swift-format format --in-place "$file"; then
        echo "Formatting failed: $file" >&2
        exit 2
      fi
      if ! xcrun swift-format lint --strict "$file"; then
        echo "Lint failed: $file" >&2
        exit 2
      fi
    done < "$tmp"
    ;;
  *)
    echo "Usage: $0 {all|modified}" >&2
    exit 2
    ;;
esac
