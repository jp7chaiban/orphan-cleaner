#!/usr/bin/env bash
# orphan-cleaner - find (and optionally kill) orphaned dev processes on macOS and Linux (incl. WSL).
#
# On Unix, a process whose parent exits is re-parented to PID 1 (init/launchd) or to a "subreaper"
# such as `systemd --user`. This script lists processes that were re-parented that way, belong to
# you, are on a known dev-tool list, and are older than a minimum age. Killing one kills its whole tree.
#
# Works with the stock tools on macOS (bash 3.2, BSD ps) and Linux (procps). lsof is optional
# (used to show listening ports).

set -u

usage() {
  cat <<'EOF'
Usage: orphan-cleaner [options]

  (no options)             report orphaned helpers older than 30 min; kills nothing
  -r, --include-runtimes   also report node/python/bash/... orphans (may be dev servers)
  -m, --min-age N          only orphans older than N minutes (default 30)
  -i, --interactive        choose what to kill from a numbered list
  -k, --kill               kill everything listed (asks once)
  -y, --yes                with --kill: don't ask
  -j, --json               print one JSON object per orphan (for scripts and coding agents)
  -h, --help               show this help

Tiers:  helper    leftover grep/tail/sleep/... pipe filters - safe to kill
        pipeline  an orphaned shell running only helpers, e.g. `tail -f log | grep x`
        runtime   node/python/bash/... (only with -r) - may be a server you still use
EOF
}

INCLUDE_RUNTIMES=0; MIN_AGE=30; KILL=0; YES=0; JSON=0; INTERACTIVE=0
while [ $# -gt 0 ]; do
  case "$1" in
    -r|--include-runtimes) INCLUDE_RUNTIMES=1 ;;
    -m|--min-age) shift; MIN_AGE="${1:-}" ;;
    --min-age=*) MIN_AGE="${1#*=}" ;;
    -i|--interactive) INTERACTIVE=1 ;;
    -k|--kill) KILL=1 ;;
    -y|--yes) YES=1 ;;
    -j|--json) JSON=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "orphan-cleaner: unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done
case "$MIN_AGE" in ''|*[!0-9]*) echo "orphan-cleaner: --min-age needs a whole number of minutes" >&2; exit 2 ;; esac

HELPERS="grep egrep fgrep rg tail head sed awk gawk mawk cat tee less more sort uniq wc xargs find sleep timeout watch"
RUNTIMES="node npx npm python pytest bash sh dash zsh fish deno bun uvicorn java ruby perl"
SHELLS="bash sh dash zsh fish"
# A tree containing any of these is a live interactive session and is never listed.
PROTECTED="claude code code-insiders cursor windsurf zed tmux screen sshd login Terminal iTerm2 gnome-terminal-server konsole alacritty kitty wezterm-gui ghostty idea pycharm webstorm"
# Parents that adopt orphans.
SUBREAPERS="systemd launchd init"

SEP=$(printf '\037')
tmp=$(mktemp -d "${TMPDIR:-/tmp}/orphan-cleaner.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT INT TERM

# -ww: never truncate command lines (BSD ps on macOS does by default).
if ! ps -A -ww -o pid=,ppid=,uid=,etime=,args= > "$tmp/ps" 2>/dev/null; then
  echo "orphan-cleaner: 'ps' failed" >&2; exit 1
fi
: > "$tmp/ports"
if command -v lsof >/dev/null 2>&1; then
  lsof -nP -iTCP -sTCP:LISTEN -Fpn > "$tmp/ports" 2>/dev/null || true
fi

# Output fields, separated by ASCII 0x1F (not tab: `read` collapses empty tab-separated fields):
# pid, name, tier, ageMinutes, treeCount, treePids, ports, args
awk -v self="$$" -v myuid="$(id -u)" -v minage="$MIN_AGE" -v incr="$INCLUDE_RUNTIMES" \
    -v helpers="$HELPERS" -v runtimes="$RUNTIMES" -v shells="$SHELLS" \
    -v protected="$PROTECTED" -v subreapers="$SUBREAPERS" '
function toset(list, arr,   n, i, a) { n = split(list, a, " "); for (i = 1; i <= n; i++) arr[a[i]] = 1 }
function base(s,   n, a) { sub(/^-/, "", s); n = split(s, a, "/"); s = a[n]; sub(/:$/, "", s); sub(/[0-9.]+$/, "", s); return s }
function secs(e,   d, n, a) {
  d = 0
  if (index(e, "-")) { split(e, a, "-"); d = a[1] + 0; e = a[2] }
  n = split(e, a, ":")
  if (n == 3) return d * 86400 + a[1] * 3600 + a[2] * 60 + a[3]
  if (n == 2) return d * 86400 + a[1] * 60 + a[2]
  return d * 86400 + a[1]
}
BEGIN { toset(helpers, H); toset(runtimes, R); toset(shells, SH); toset(protected, P); toset(subreapers, SR) }
FILENAME ~ /ports$/ {
  if ($0 ~ /^p/) cur = substr($0, 2)
  else if ($0 ~ /^n/) { port = $0; sub(/.*:/, "", port); if (index("," ports[cur] ",", "," port ",") == 0) ports[cur] = (ports[cur] == "" ? port : ports[cur] "," port) }
  next
}
{
  pid = $1; line = $0
  sub(/^[ \t]*[0-9]+[ \t]+[0-9]+[ \t]+[0-9]+[ \t]+[^ \t]+[ \t]*/, "", line); sub(/[ \t]+$/, "", line)
  split(line, w, " ")
  ppid_[pid] = $2; uid_[pid] = $3; age_[pid] = secs($4); args_[pid] = line; name_[pid] = base(w[1])
  kids[$2] = kids[$2] " " pid
}
END {
  # Never touch this script or its ancestors.
  p = self
  while ((p in ppid_) && !(p in prot)) { prot[p] = 1; p = ppid_[p] }

  for (pid in ppid_) {
    if (uid_[pid] != myuid || (pid in prot)) continue
    nm = name_[pid]
    if (!(nm in H) && !(nm in R)) continue
    pp = ppid_[pid]
    if (!(pp <= 1 || !(pp in ppid_) || (name_[pp] in SR))) continue
    if (age_[pid] < minage * 60) continue

    # Collect the tree breadth-first.
    split("", q); qn = 1; q[1] = pid; qi = 1
    while (qi <= qn) {
      cur = q[qi++]; nk = split(kids[cur], ks, " ")
      for (k = 1; k <= nk; k++) q[++qn] = ks[k]
    }
    hasProt = 0; onlyHelpers = 1; tree = ""; tports = ""
    for (k = 1; k <= qn; k++) {
      t = q[k]; tree = tree (k > 1 ? " " : "") t
      if (name_[t] in P) hasProt = 1
      if (!(name_[t] in H) && !(name_[t] in SH)) onlyHelpers = 0
      if (t in ports) tports = (tports == "" ? ports[t] : tports "," ports[t])
    }
    if (hasProt) continue

    if (nm in H) tier = "helper"
    else if ((nm in SH) && onlyHelpers && qn > 1) tier = "pipeline"
    else if (incr == 1) tier = "runtime"
    else continue

    printf "%s\037%s\037%s\037%d\037%d\037%s\037%s\037%s\n", pid, nm, tier, age_[pid] / 60, qn, tree, tports, args_[pid]
  }
}' "$tmp/ports" "$tmp/ps" | sort -t "$SEP" -k4,4nr > "$tmp/orphans"

count=$(wc -l < "$tmp/orphans" | tr -d ' ')

if [ "$JSON" = 1 ]; then
  awk -F "$SEP" '
  function esc(s) { gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s); gsub(/\t/, "\\t", s); return s }
  { tree = $6; gsub(/ /, ",", tree)
    printf "{\"pid\":%s,\"name\":\"%s\",\"tier\":\"%s\",\"age_minutes\":%s,\"processes\":%s,\"tree\":[%s],\"ports\":[%s],\"command\":\"%s\"}\n",
      $1, esc($2), $3, $4, $5, tree, $7, esc($8) }' "$tmp/orphans"
  exit 0
fi

if [ "$count" = 0 ]; then
  if [ "$INCLUDE_RUNTIMES" = 1 ]; then scope=""; else scope=", helpers only - add -r for node/python/bash"; fi
  echo "No orphaned processes found (older than $MIN_AGE min$scope)."
  exit 0
fi

fmt_age() { # minutes -> human
  if [ "$1" -ge 1440 ]; then awk -v m="$1" 'BEGIN { printf "%.1fd", m / 1440 }'
  elif [ "$1" -ge 60 ]; then awk -v m="$1" 'BEGIN { printf "%.1fh", m / 60 }'
  else printf '%sm' "$1"; fi
}

printf '%3s  %-7s %-9s %-8s %6s %5s  %-11s %s\n' '#' 'PID' 'NAME' 'TIER' 'AGE' 'PROCS' 'PORTS' 'COMMAND'
n=0
while IFS="$SEP" read -r pid name tier age procs tree ports args; do
  n=$((n + 1))
  printf '%3s  %-7s %-9s %-8s %6s %5s  %-11s %.90s\n' "$n" "$pid" "$name" "$tier" "$(fmt_age "$age")" "$procs" "${ports:--}" "$args"
done < "$tmp/orphans"
echo
echo "$count orphan(s). Rows with PORTS are servers still listening - check before killing."

# kill_entry LINE_NUMBER -> kills that orphan and its tree; prints what happened.
kill_entry() {
  IFS="$SEP" read -r pid name tier age procs tree ports args <<EOF
$(sed -n "${1}p" "$tmp/orphans")
EOF
  # Guard against PID reuse since the scan.
  now=$(ps -ww -o args= -p "$pid" 2>/dev/null | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
  if [ "$now" != "$args" ]; then echo "skipped $pid ($name): process changed or already gone"; return; fi
  rev=""; for p in $tree; do rev="$p $rev"; done   # deepest first
  for p in $rev; do kill -TERM "$p" 2>/dev/null; done
  sleep 1
  for p in $rev; do kill -0 "$p" 2>/dev/null && kill -KILL "$p" 2>/dev/null; done
  left=""; for p in $tree; do kill -0 "$p" 2>/dev/null && left="$left $p"; done
  if [ -z "$left" ]; then echo "killed  $pid ($name) and $((procs - 1)) child process(es)"
  else echo "partly killed $pid ($name); still running:$left"; fi
}

if [ "$INTERACTIVE" = 1 ]; then
  [ -r /dev/tty ] || { echo "orphan-cleaner: --interactive needs a terminal" >&2; exit 2; }
  printf 'Kill which? Numbers (e.g. 1 3 4), s = all helper/pipeline rows without ports, a = all, Enter = none: '
  read -r answer < /dev/tty
  case "$answer" in
    ''|q|Q) echo "Nothing killed."; exit 0 ;;
    a|A) picks=$(seq 1 "$count") ;;
    s|S) picks=$(awk -F "$SEP" '($3 == "helper" || $3 == "pipeline") && $7 == "" { print NR }' "$tmp/orphans") ;;
    *) picks=$answer ;;
  esac
  for i in $picks; do
    case "$i" in *[!0-9]*|'') echo "ignored '$i'"; continue ;; esac
    if [ "$i" -ge 1 ] && [ "$i" -le "$count" ]; then kill_entry "$i"; else echo "ignored '$i' (no such row)"; fi
  done
  exit 0
fi

if [ "$KILL" = 1 ]; then
  if [ "$YES" != 1 ]; then
    [ -r /dev/tty ] || { echo "orphan-cleaner: refusing to kill without a terminal to confirm; add --yes" >&2; exit 2; }
    printf 'Kill these %s orphan(s) and their child processes? [y/N] ' "$count"
    read -r answer < /dev/tty
    case "$answer" in y|Y|yes|YES) ;; *) echo "Cancelled."; exit 0 ;; esac
  fi
  i=1; while [ "$i" -le "$count" ]; do kill_entry "$i"; i=$((i + 1)); done
  exit 0
fi

echo "Report only. Use -i to pick what to kill, or -k to kill all listed."
