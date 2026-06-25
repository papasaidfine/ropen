# ropen — remote side
# Source this from your shell rc on the remote host, e.g. add to ~/.bashrc:
#     source ~/path/to/o.sh
# or just paste the function below.
#
# Usage: o <file> [file...]
# Sends files down to the local machine via trzsz (tsz). The local tssh client
# drops them into the ropen watch folder, where ropen-watch.ps1 auto-opens them.
#
# The -y (--overwrite) flag is important: without it, trzsz never overwrites and
# instead appends a counter to the *whole* filename on a name collision
# (name.csv -> name.csv.0), which destroys the extension so Windows can't pick a
# default app to open it.
#
# After the data transfer completes, o() sends a tiny *.sig signal file listing
# the transferred basenames. The watcher only reacts to *.sig arrivals, so it
# never touches a data file mid-write — by the time the signal lands, tsz has
# already returned and all data files are fully closed on the local side.

o() {
  if [ $# -eq 0 ]; then
    echo "usage: o <file> [file...]"
    return 1
  fi
  if ! command -v tsz >/dev/null 2>&1; then
    echo "o: tsz not found; install trzsz-go: https://github.com/trzsz/trzsz-go" >&2
    return 1
  fi
  for f in "$@"; do
    if [ ! -e "$f" ]; then
      echo "o: not found: $f" >&2
      return 1
    fi
  done

  tsz -y "$@" || return 1

  local sig
  sig=$(mktemp /tmp/ropen-XXXXXX.sig) || return 1
  for f in "$@"; do printf '%s\n' "$(basename -- "$f")"; done > "$sig"
  tsz -y "$sig"
  rm -f "$sig"
}
