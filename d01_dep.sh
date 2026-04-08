#!/bin/sh
# d01_dep.sh collect depends + clean naming + arch filtering

pkg="$1"; pathdep="$2";
[ -n "$pkg" ] || { echo "usage: $0 <package>"; exit 1; }

get_deps() {
    local pkg="$1"

    # Get Depends, Pre-Depends, Recommends from package metadata
    apt-cache show "$pkg" 2>/dev/null | grep -E "^(Depends|Pre-Depends|Recommends):" \
      | cut -d: -f2- \
      | tr ',' '\n' \
      | awk '
      {
          # trim leading/trailing whitespace
          gsub(/^[[:space:]]+|[[:space:]]+$/, "");
          # keep only the package name part (before any version constraint or arch)
          sub(/[[:space:]<>=|()].*/,"");
          # remove architecture qualifier (e.g., :any, :amd64)
          sub(/:[a-zA-Z0-9]+$/, "");
          if ($0 != "") print $0
      }
      ' \
      | sort -u
}

seen_tmp=$(mktemp)
cur=$(mktemp)
nxt=$(mktemp)
trap 'rm -f "$cur" "$nxt" "$seen_tmp"' EXIT

printf '%s\n' "$pkg" >"$seen_tmp"
printf '%s\n' "$pkg" >"$cur"

depth=0
while :; do
  >"$nxt"
  while read -r p; do
    get_deps "$p" | while read -r d; do
      [ -z "$d" ] && continue
      if ! grep -xqF "$d" "$seen_tmp"; then
        printf '%s\n' "$d" >>"$nxt"
        printf '%s\n' "$d" >>"$seen_tmp"
      fi
    done
  done <"$cur"

  nxt_count=$(wc -l <"$nxt" | tr -d ' ')
  total_count=$(wc -l <"$seen_tmp" | tr -d ' ')
  printf 'depth %d: new=%s total=%s\n' "$depth" "$nxt_count" "$total_count"

  [ "$nxt_count" -eq 0 ] && break

  mv "$nxt" "$cur"
  nxt=$(mktemp)
  depth=$((depth + 1))
done

out_file="${pathdep}/${pkg}.depends"
sort -u "$seen_tmp" >"$out_file"
echo "Total packages collected: $(wc -l <"$out_file" | tr -d ' ')"
echo "Saved list to $out_file"
