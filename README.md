# ropen

**Remote open.** Run a command on a remote SSH session and have the file pop open on your local Windows machine with its default app — no manual download, no double-click.

```
remote (Linux)                         local (Windows)
--------------                         ---------------
$ o report.csv                         ~/Downloads/ropen/  <-- watch folder
   │
   ├─ tsz -y report.csv ──(trzsz/tssh)──▶  report.csv  (fully written & closed)
   │
   └─ tsz -y ropen-*.sig ─(trzsz/tssh)──▶  ropen-*.sig  ← watcher triggers here
                                                │
                                          reads filenames from signal
                                          deletes signal file
                                                │
                                          Start-Process report.csv
                                                │
                                          opens in default app (Excel, etc.)
```

## How it works

Two halves talk over a [trzsz](https://trzsz.github.io/) (`tssh`) session:

- **Remote** — the `o()` shell function ([`remote/o.sh`](remote/o.sh)) calls `tsz -y <file>`, which streams the file down through the SSH session.
- **Local** — the `tssh` client writes the received files and a tiny `*.sig` signal into the watch folder. [`ropen-watch.ps1`](ropen-watch.ps1) uses `FileSystemWatcher` and only reacts to `*.sig` arrivals. Because `o()` sends the signal only after `tsz` has returned, all data files are guaranteed fully closed by the time the signal lands — no polling, no file-lock guessing.

Events and errors are logged to `%TEMP%\ropen.log`.

## Setup

### Local (Windows)

1. Install `tssh` (the trzsz SSH client) and make sure it's on `PATH`. `tssh` is a **separate project** from trzsz-go — it ships from [trzsz-ssh](https://github.com/trzsz/trzsz-ssh), not in the `trzsz_windows_*.zip` (which only contains `trz`/`tsz`/`trzsz`). On Windows install it with `scoop install tssh`, or download `tssh.exe` from the [trzsz-ssh releases](https://github.com/trzsz/trzsz-ssh/releases) and put it on `PATH`.
2. Point trzsz's download location at the watch folder so received files land there. In `~/.tssh.conf`:
   ```
   DefaultDownloadPath = C:\Users\<you>\Downloads\ropen
   ```
3. Start the watcher (it creates the folder if missing):
   ```powershell
   pwsh -File ropen-watch.ps1
   ```
   To use a custom folder, pass `-WatchDir` or set `$env:ROPEN_DIR` before launching:
   ```powershell
   pwsh -File ropen-watch.ps1 -WatchDir D:\ropen
   # or
   $env:ROPEN_DIR = "D:\ropen"; pwsh -File ropen-watch.ps1
   ```
   To run it automatically at login, drop a shortcut to that command into `shell:startup`, or register a Scheduled Task triggered "At log on".

   Logs are written to `%TEMP%\ropen.log`.

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
o report.csv                  # single file
o report.csv summary.xlsx     # multiple files
```

## The `-y` gotcha

`o()` sends with `tsz -y` (`--overwrite`) on purpose. Without `-y`, trzsz refuses to overwrite an existing file and instead appends a counter to the **entire** filename — `report.csv` becomes `report.csv.0`. The real extension is now buried, so Windows has no association for `.0` and shows the "How do you want to open this file?" dialog instead of just opening it.

With `-y`, the file is overwritten in place, the `.csv` extension is preserved, and the new write time makes the watcher re-open the refreshed copy.

**Caveat:** overwrite fails if the previous copy is still locked open (e.g. a CSV held by Excel). Close it before re-sending.
