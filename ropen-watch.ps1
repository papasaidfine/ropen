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

$opened = @{}

# 启动基线：把已存在的文件标记为"已见过"，避免启动时把整个文件夹的存量文件全打开
Get-ChildItem $WatchDir -File -ErrorAction SilentlyContinue | ForEach-Object {
    $key = "$($_.FullName)|$($_.LastWriteTimeUtc.Ticks)|$($_.Length)"
    $opened[$key] = $true
}

Write-Log "Watching $WatchDir  (log: $logFile)"

# 事件驱动：用 FileSystemWatcher + 线程安全队列替代定时轮询
$queue = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()

$watcher = New-Object System.IO.FileSystemWatcher $WatchDir
$watcher.NotifyFilter = [System.IO.NotifyFilters]::FileName -bor [System.IO.NotifyFilters]::LastWrite -bor [System.IO.NotifyFilters]::Size
$watcher.IncludeSubdirectories = $false
$watcher.EnableRaisingEvents = $true

$action = { $Event.MessageData.Enqueue($Event.SourceEventArgs.FullPath) }
Register-ObjectEvent $watcher Created -Action $action -MessageData $queue | Out-Null
Register-ObjectEvent $watcher Changed -Action $action -MessageData $queue | Out-Null

try {
    while ($true) {
        $path = $null
        while ($queue.TryDequeue([ref]$path)) {
            if (-not (Test-Path $path -PathType Leaf)) { continue }

            $file = Get-Item $path -ErrorAction SilentlyContinue
            if (-not $file) { continue }

            $key = "$path|$($file.LastWriteTimeUtc.Ticks)|$($file.Length)"
            if ($opened.ContainsKey($key)) { continue }

            try {
                # 等文件写完（独占读锁）
                $stream = [System.IO.File]::Open($path, 'Open', 'Read', 'None')
                $stream.Close()
                $opened[$key] = $true
                Start-Process $path
                Write-Log "Opened $path"
            } catch {
                # 文件还在写，下一个 Changed 事件时自动重试
                Write-Log "Still writing: $path" "WARN"
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
