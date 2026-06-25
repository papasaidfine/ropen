param(
    [string]$WatchDir = $(if ($env:ROPEN_DIR) { $env:ROPEN_DIR } else { "$env:USERPROFILE\Downloads\ropen" })
)

New-Item -ItemType Directory -Force -Path $WatchDir | Out-Null

$logFile = Join-Path $env:TEMP "ropen.log"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] [$Level] $Message"
    Write-Host $line
    Add-Content -Path $logFile -Value $line -ErrorAction SilentlyContinue
}

# Remove stale signal files left by a previously crashed watcher
Get-ChildItem $WatchDir -Filter "*.sig" -File -ErrorAction SilentlyContinue |
    Remove-Item -Force -ErrorAction SilentlyContinue

Write-Log "Watching $WatchDir  (log: $logFile)"

# Only watch for *.sig completion signals — never touch data files mid-write.
# o() on the remote sends the signal only after tsz has returned, so all data
# files are guaranteed fully closed before the signal arrives.
$queue = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()

$watcher = New-Object System.IO.FileSystemWatcher $WatchDir
$watcher.Filter = "*.sig"
$watcher.NotifyFilter = [System.IO.NotifyFilters]::FileName -bor [System.IO.NotifyFilters]::LastWrite
$watcher.IncludeSubdirectories = $false
$watcher.EnableRaisingEvents = $true

$action = { $Event.MessageData.Enqueue($Event.SourceEventArgs.FullPath) }
Register-ObjectEvent $watcher Created -Action $action -MessageData $queue | Out-Null
Register-ObjectEvent $watcher Changed -Action $action -MessageData $queue | Out-Null

function Wait-Readable {
    param([string]$Path)
    for ($i = 0; $i -lt 20; $i++) {
        try {
            $s = [System.IO.File]::Open($Path, 'Open', 'Read', 'None')
            $s.Close()
            return $true
        } catch {
            Start-Sleep -Milliseconds 100
        }
    }
    return $false
}

try {
    while ($true) {
        $sigPath = $null
        while ($queue.TryDequeue([ref]$sigPath)) {
            if (-not (Test-Path $sigPath -PathType Leaf)) { continue }

            if (-not (Wait-Readable $sigPath)) {
                Write-Log "Timed out reading signal: $sigPath" "WARN"
                continue
            }

            $names = Get-Content $sigPath -ErrorAction SilentlyContinue
            Remove-Item $sigPath -Force -ErrorAction SilentlyContinue

            foreach ($name in $names) {
                $target = Join-Path $WatchDir $name
                if (Test-Path $target -PathType Leaf) {
                    Start-Process $target
                    Write-Log "Opened $target"
                } else {
                    Write-Log "File not found after signal: $target" "WARN"
                }
            }
        }
        Start-Sleep -Milliseconds 50
    }
} finally {
    $watcher.EnableRaisingEvents = $false
    $watcher.Dispose()
    Get-EventSubscriber -ErrorAction SilentlyContinue | ForEach-Object {
        Unregister-Event -SubscriptionId $_.SubscriptionId -ErrorAction SilentlyContinue
    }
    Write-Log "Watcher stopped"
}
