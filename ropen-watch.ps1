$dir = "$env:USERPROFILE\Downloads\ropen"
New-Item -ItemType Directory -Force -Path $dir | Out-Null

$opened = @{}

# 启动基线：把已存在的文件标记为"已见过"，避免启动时把整个文件夹的存量文件全打开
Get-ChildItem $dir -File -ErrorAction SilentlyContinue | ForEach-Object {
    $key = "$($_.FullName)|$($_.LastWriteTimeUtc.Ticks)|$($_.Length)"
    $opened[$key] = $true
}

Write-Host "Watching $dir"

while ($true) {
    Get-ChildItem $dir -File -ErrorAction SilentlyContinue | ForEach-Object {
        $path = $_.FullName
        $key = "$path|$($_.LastWriteTimeUtc.Ticks)|$($_.Length)"

        if (-not $opened.ContainsKey($key)) {
            try {
                # 等文件写完
                $stream = [System.IO.File]::Open($path, 'Open', 'Read', 'None')
                $stream.Close()

                $opened[$key] = $true
                Start-Process $path
                Write-Host "Opened $path"
            } catch {
                # 文件还在写，下一轮再试
            }
        }
    }

    Start-Sleep -Milliseconds 500
}

