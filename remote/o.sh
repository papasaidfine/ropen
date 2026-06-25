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
# o() sends the data files and a tiny ropen-*.sig signal listing their basenames
# in a SINGLE tsz call, with the signal as the last argument. trzsz transfers
# files serially in argument order, so the signal only lands after every data
# file is fully written locally. The watcher reacts to ropen-*.sig arrivals
# only, so it never touches a data file mid-write. Sending everything in one
# call (rather than a separate signal transfer) also removes the window where
# the data could arrive but an independent signal send fails on its own.

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

  # Build the completion signal first, then send data files + signal in one tsz
  # call (signal last). See the header comment for why this is a single call.
  local sig rc
  sig=$(mktemp /tmp/ropen-XXXXXX.sig) || return 1
  for f in "$@"; do printf '%s\n' "$(basename -- "$f")"; done > "$sig"

  tsz -y "$@" "$sig"
  rc=$?
  rm -f "$sig"

  if [ "$rc" -ne 0 ]; then
    echo "o: transfer failed (tsz exit $rc); local side will not auto-open" >&2
    return "$rc"
  fi
}
