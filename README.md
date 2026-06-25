# ropen

**Remote open.** Run a command on a remote SSH session and have the file pop open on your local Windows machine with its default app — no manual download, no double-click.

```
remote (r5)                          local (Windows)
-----------                          ---------------
$ o report.csv                       ~/Downloads/ropen/  <-- watch folder
   |                                        |
   tsz -y report.csv  ──(trzsz/tssh)──▶  report.csv written
                                            |
                                      ropen-watch.ps1 sees it
                                            |
                                      Start-Process report.csv
                                            |
                                      opens in default app (Excel, etc.)
```

## How it works

Two halves talk over a [trzsz](https://trzsz.github.io/) (`tssh`) session:

- **Remote** — the `o()` shell function ([`remote/o.sh`](remote/o.sh)) calls `tsz -y <file>`, which streams the file down through the SSH session.
- **Local** — the `tssh` client writes the received file into the watch folder (`%USERPROFILE%\Downloads\ropen`). [`ropen-watch.ps1`](ropen-watch.ps1) polls that folder every 500 ms and `Start-Process`-opens anything new, so Windows launches it with the default associated program.

The watcher dedups on `path | LastWriteTimeUtc | Length`, and skips files that are still being written (it waits for an exclusive read lock first).

## Setup

### Local (Windows)

1. Install trzsz's `tssh` and make sure it's on `PATH`. The Go build ([trzsz-go](https://github.com/trzsz/trzsz-go)) ships a standalone Windows binary — grab the `trzsz_windows_*.zip` from its releases and put `tssh.exe` on `PATH`.
2. Point trzsz's download location at the watch folder so received files land there. In `~/.tssh.conf`:
   ```
   DefaultDownloadPath = C:\Users\<you>\Downloads\ropen
   ```
3. Start the watcher (it creates the folder if missing):
   ```powershell
   pwsh -File ropen-watch.ps1
   ```
   To run it automatically at login, drop a shortcut to that command into `shell:startup`, or register a Scheduled Task triggered "At log on".

### Remote

1. Install trzsz so the `tsz` command is available. Use the Go build ([trzsz-go](https://github.com/trzsz/trzsz-go)) — it ships standalone binaries with no runtime deps. Grab the release for the remote's OS/arch, then put `tsz` (and `trz`) on `PATH`:
   ```sh
   # example: Linux x86_64
   curl -sSL -o trzsz.tar.gz https://github.com/trzsz/trzsz-go/releases/latest/download/trzsz_linux_x86_64.tar.gz
   tar xzf trzsz.tar.gz
   sudo install trzsz_*/tsz trzsz_*/trz /usr/local/bin/
   ```
   (Or `go install github.com/trzsz/trzsz-go/cmd/...@latest`, or your package manager.)
2. Add the open command to your shell rc (e.g. `~/.bashrc`):
   ```sh
   source ~/path/to/o.sh     # or paste the o() function directly
   ```

Then connect with `tssh`, and:

```sh
o report.csv
```

## The `-y` gotcha

`o()` sends with `tsz -y` (`--overwrite`) on purpose. Without `-y`, trzsz refuses to overwrite an existing file and instead appends a counter to the **entire** filename — `report.csv` becomes `report.csv.0`. The real extension is now buried, so Windows has no association for `.0` and shows the "How do you want to open this file?" dialog instead of just opening it.

With `-y`, the file is overwritten in place, the `.csv` extension is preserved, and the new write time makes the watcher re-open the refreshed copy.

**Caveat:** overwrite fails if the previous copy is still locked open (e.g. a CSV held by Excel). Close it before re-sending.
