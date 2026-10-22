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
    git diff --name-only -z -- '*.swift' > "$tmp"
    git diff --cached --name-only -z -- '*.swift' >> "$tmp"
    git ls-files --others --exclude-standard -z -- '*.swift' >> "$tmp"
    # macOS標準のBashでも扱える配列で重複を除去します。
    # 空文字の初期値は、set -uで空配列を参照する際のエラーを防ぎます。
    processed=("")
    while IFS= read -r -d '' file; do
      [[ -f "$file" ]] || continue
      for processed_file in "${processed[@]}"; do
        [[ "$file" != "$processed_file" ]] || continue 2
      done
      processed+=("$file")
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
