# ropen — remote side
# Source this from your shell rc on the remote host, e.g. add to ~/.bashrc:
#     source ~/path/to/o.sh
# or just paste the function below.
#
# Usage: o <file>
# Sends <file> down to the local machine via trzsz (tsz). The local tssh client
# drops it into the ropen watch folder, where ropen-watch.ps1 auto-opens it.
#
# The -y (--overwrite) flag is important: without it, trzsz never overwrites and
# instead appends a counter to the *whole* filename on a name collision
# (name.csv -> name.csv.0), which destroys the extension so Windows can't pick a
# default app to open it.

o() {
  if [ $# -eq 0 ]; then
    echo "usage: o <file>"
    return 1
  fi
  tsz -y "$1"
}
