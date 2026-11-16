#!/bin/sh
# What of our 0.2.x fork is still in the tree being ported, and what is not.
# usage: sh audit-port.sh <our-old-tree> <the-new-upstream-tree>
# Each line is: feature <tab> marker <tab> file it lives in (or - for any).
set -e
OLD=${1:?old tree}
NEW=${2:?new tree}
TABLE=$(dirname "$0")/audit-markers.tsv
hit=0; miss=0; part=0
while IFS="$(printf '\t')" read -r feature marker file; do
    [ -z "$feature" ] && continue
    case "$feature" in \#*) continue ;; esac
    if [ "$file" = "-" ]; then scope="$NEW"; else scope="$NEW/$file"; fi
    if [ -e "$scope" ] && grep -rqF -- "$marker" $scope 2>/dev/null; then
        printf "有   %-28s %s\n" "$feature" "$marker"; hit=$((hit+1))
    elif [ -e "$NEW/$file" ] 2>/dev/null; then
        printf "改   %-28s 文件在，标记不在：%s\n" "$feature" "$marker"; part=$((part+1))
    else
        printf "缺   %-28s %s\n" "$feature" "${file:-$marker}"; miss=$((miss+1))
    fi
done < "$TABLE"
echo "---- 有 $hit · 需人工核 $part · 缺 $miss"
