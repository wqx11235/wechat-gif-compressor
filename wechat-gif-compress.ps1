<#
  微信动图压缩工具（推荐版格式）
  ------------------------------------------------------------------
  把动图压到能直接在微信聊天里发送（默认目标 <= 9.5 MB）。
  默认采用「推荐版」参数：长边 400px / 25fps / 256 色 /
  去噪 + 帧间矩形差分包，画质与体积平衡最佳。

  用法（把文件或文件夹拖到同目录的「压缩微信表情包.cmd」上即可）：
      powershell -ExecutionPolicy Bypass -File wechat-gif-compress.ps1 a.gif b.gif
      -TargetMB 5      压到 5MB 以内（微信「添加表情」上限）
      -Size 400        长边像素上限（默认 400，不会放大）
      -Fps 25          帧率上限（默认 25）
      -OutDir 微信版   输出子目录名（默认「微信版」）

  若按推荐参数仍超过目标体积，会自动逐档加强压缩
  （提高去噪 -> 降帧率 -> 降分辨率 -> 减色），直到达标。
#>
# --- 参数：手工解析，避开 PS 5.1 的位置绑定 / CmdletBinding 陷阱 ---
$TargetMB = 9.5
$Size     = 400
$Fps      = 25
$OutDir   = '微信版'
$ShowHelp = $false
$Force    = $false

$Inputs = New-Object System.Collections.ArrayList
$argv = @($args)
for ($i = 0; $i -lt $argv.Count; $i++) {
    $a = [string]$argv[$i]
    if     ($a -eq '-TargetMB' -and ($i + 1) -lt $argv.Count) { $i++; $TargetMB = [double]$argv[$i] }
    elseif ($a -eq '-Size'     -and ($i + 1) -lt $argv.Count) { $i++; $Size     = [int]$argv[$i] }
    elseif ($a -eq '-Fps'      -and ($i + 1) -lt $argv.Count) { $i++; $Fps      = [int]$argv[$i] }
    elseif ($a -eq '-OutDir'   -and ($i + 1) -lt $argv.Count) { $i++; $OutDir   = [string]$argv[$i] }
    elseif ($a -eq '-Force') { $Force = $true }
    elseif ($a -eq '-h' -or $a -eq '-Help' -or $a -eq '--help') { $ShowHelp = $true }
    else   { [void]$Inputs.Add($a) }
}

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
$OutputEncoding = [Text.Encoding]::UTF8

$script:FFmpeg = $null
$script:FFprobe = $null

function Show-Banner {
    Write-Host ''
    Write-Host '============================================================' -ForegroundColor Cyan
    Write-Host '  微信动图压缩工具  ·  推荐版格式' -ForegroundColor Cyan
    Write-Host '============================================================' -ForegroundColor Cyan
    Write-Host ("  目标体积 : 每个文件 <= {0} MB" -f $TargetMB)
    Write-Host ("  输出规格 : 长边 {0}px / {1}fps / 256 色 / 去噪 / 帧间差分" -f $Size, $Fps)
    Write-Host ("  输出位置 : 源文件旁边的「{0}」子目录" -f $OutDir)
    Write-Host ''
}

function Show-Usage {
    Show-Banner
    Write-Host '用法：把这个动图文件（或文件夹）拖到「压缩微信表情包.cmd」上' -ForegroundColor Yellow
    Write-Host '      支持 .gif / .webp / .mp4 / .mov / .webm 作为输入，统一输出 GIF'
    Write-Host ''
    Write-Host '命令行参数（可选）：'
    Write-Host '  -TargetMB 5      压到 5MB 以内，用于微信「添加表情」（默认 9.5）'
    Write-Host '  -Size 400        长边像素上限，只缩不放（默认 400）'
    Write-Host '  -Fps 25          帧率上限（默认 25）'
    Write-Host '  -OutDir 微信版   输出子目录名（默认「微信版」）'
    Write-Host '  -Force           即使转换后体积更大也强制转换（默认自动回退）'
    Write-Host ''
    Write-Host '示例：'
    Write-Host '  powershell -ExecutionPolicy Bypass -File wechat-gif-compress.ps1 表情.gif -TargetMB 5'
    Write-Host ''
}

function Find-Tool {
    param([string]$Name)

    $cmd = Get-Command ($Name + '.exe') -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $roots = @(
        'D:\ffmpeg', 'C:\ffmpeg',
        (Join-Path $env:ProgramFiles 'ffmpeg'),
        (Join-Path ${env:ProgramFiles(x86)} 'ffmpeg'),
        (Join-Path $env:LOCALAPPDATA 'ffmpeg'),
        (Join-Path $env:USERPROFILE 'ffmpeg'),
        (Join-Path $env:USERPROFILE 'scoop\apps\ffmpeg\current'),
        'C:\ProgramData\chocolatey\bin',
        $PSScriptRoot
    )
    foreach ($r in $roots) {
        if ($r -and (Test-Path -LiteralPath $r)) {
            $direct = Join-Path $r ($Name + '.exe')
            if (Test-Path -LiteralPath $direct) { return $direct }
            $direct = Join-Path (Join-Path $r 'bin') ($Name + '.exe')
            if (Test-Path -LiteralPath $direct) { return $direct }
            $hit = Get-ChildItem -LiteralPath $r -Recurse -Filter ($Name + '.exe') -ErrorAction SilentlyContinue |
                   Sort-Object FullName -Descending | Select-Object -First 1
            if ($hit) { return $hit.FullName }
        }
    }
    return $null
}

function Get-MediaInfo {
    param([string]$Path)

    $raw = & $script:FFprobe -v error -select_streams v:0 `
        -show_entries stream=width,height,avg_frame_rate,nb_frames `
        -show_entries format=duration -of json $Path 2>$null
    if (-not $raw) { return $null }
    try { $obj = ($raw | Out-String) | ConvertFrom-Json } catch { return $null }
    $s = $obj.streams | Select-Object -First 1
    if (-not $s) { return $null }

    $fps = 0.0
    if ($s.avg_frame_rate -match '^(\d+)/(\d+)$') {
        $num = [double]$Matches[1]; $den = [double]$Matches[2]
        if ($den -gt 0) { $fps = $num / $den }
    }
    $dur = 0.0
    if ($obj.format -and $obj.format.duration) { $dur = [double]$obj.format.duration }
    else { $dur = 0.0 }

    return @{
        Width  = [int]$s.width
        Height = [int]$s.height
        Fps    = [math]::Round($fps, 2)
        Frames = [int]$s.nb_frames
        Dur    = [math]::Round($dur, 2)
    }
}

function Build-Filter {
    param([int]$W, [int]$H, [int]$MaxSize, [int]$FpsValue, [string]$Denoise, [int]$Colors)

    $chain = New-Object System.Collections.ArrayList

    $long = [math]::Max($W, $H)
    if ($long -gt $MaxSize) {
        if ($W -ge $H) { [void]$chain.Add("scale=${MaxSize}:-2:flags=lanczos") }
        else           { [void]$chain.Add("scale=-2:${MaxSize}:flags=lanczos") }
    }
    [void]$chain.Add("hqdn3d=$Denoise")
    [void]$chain.Add("fps=$FpsValue")

    $base = ($chain -join ',')
    return $base + ",split[s0][s1];[s0]palettegen=max_colors=${Colors}:stats_mode=diff[p];[s1][p]paletteuse=dither=none:diff_mode=rectangle"
}

function Invoke-Encode {
    param([string]$Src, [string]$Dst, [string]$Filter)

    $a = @('-y', '-v', 'error', '-nostdin', '-i', $Src, '-vf', $Filter, '-loop', '0', $Dst)
    $out = & $script:FFmpeg @a 2>&1
    if ($LASTEXITCODE -ne 0) {
        $msg = ($out | Out-String).Trim()
        if (-not $msg) { $msg = "ffmpeg 退出码 $LASTEXITCODE" }
        throw $msg
    }
}

function Get-Ladder {
    param([int]$BaseSize)

    $s1 = $BaseSize
    $s2 = [math]::Max(240, $BaseSize - 40)
    $s3 = [math]::Max(220, $BaseSize - 80)
    $s4 = [math]::Max(200, $BaseSize - 100)
    $s5 = [math]::Max(180, $BaseSize - 120)

    return @(
        @{ Size = $s1; Fps = 25; Dn = '6:6:18:18';   Colors = 256; Note = '推荐版' },
        @{ Size = $s1; Fps = 25; Dn = '8:8:20:20';   Colors = 256; Note = '加强去噪' },
        @{ Size = $s1; Fps = 22; Dn = '10:10:24:24'; Colors = 256; Note = '降帧率' },
        @{ Size = $s2; Fps = 25; Dn = '8:8:20:20';   Colors = 256; Note = '略缩尺寸' },
        @{ Size = $s2; Fps = 20; Dn = '10:10:24:24'; Colors = 192; Note = '缩尺寸+减色' },
        @{ Size = $s3; Fps = 20; Dn = '12:12:28:28'; Colors = 192; Note = '继续缩小' },
        @{ Size = $s4; Fps = 18; Dn = '12:12:28:28'; Colors = 128; Note = '强压缩' },
        @{ Size = $s5; Fps = 15; Dn = '14:14:30:30'; Colors = 128; Note = '极限压缩' }
    )
}

function Process-One {
    param([string]$Src, [int]$Index, [int]$Total, [array]$Ladder)

    $name = Split-Path -Leaf $Src
    $dir = Split-Path -Parent $Src
    $base = [IO.Path]::GetFileNameWithoutExtension($Src)

    if ($base -like '*.微信版') {
        Write-Host ("[{0}/{1}] {2}" -f $Index, $Total, $name) -ForegroundColor DarkGray
        Write-Host '        已是本工具的输出文件，跳过。' -ForegroundColor DarkGray
        return 'skip'
    }

    $srcBytes = (Get-Item -LiteralPath $Src).Length
    $srcMB = [math]::Round($srcBytes / 1MB, 2)

    $info = Get-MediaInfo -Path $Src
    if (-not $info) {
        Write-Host ("[{0}/{1}] {2}" -f $Index, $Total, $name) -ForegroundColor Yellow
        Write-Host '        无法读取（不是有效动图？），跳过。' -ForegroundColor Yellow
        return 'fail'
    }
    if ($info.Frames -le 1 -and $info.Dur -le 0) {
        Write-Host ("[{0}/{1}] {2}" -f $Index, $Total, $name) -ForegroundColor Yellow
        Write-Host '        这是静态图，不是动图，跳过。' -ForegroundColor Yellow
        return 'skip'
    }

    Write-Host ("[{0}/{1}] {2}" -f $Index, $Total, $name) -ForegroundColor White
    Write-Host ("        原始: {0} MB, {1}x{2}, {3}fps, {4} 帧, {5}s" -f $srcMB, $info.Width, $info.Height, $info.Fps, $info.Frames, $info.Dur) -ForegroundColor DarkGray

    $leafDir = Split-Path -Leaf $dir
    if ($leafDir -eq $OutDir) { $targetDir = $dir }
    else { $targetDir = Join-Path $dir $OutDir }

    if (-not (Test-Path -LiteralPath $targetDir)) {
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    }
    $dst = Join-Path $targetDir ($base + '.微信版.gif')

    $limit = $TargetMB * 1MB
    $bestBytes = [double]::MaxValue
    $bestIndex = -1
    $passed = $false
    $lastIndex = $Ladder.Count - 1

    for ($i = 0; $i -lt $Ladder.Count; $i++) {
        $cfg = $Ladder[$i]
        $filter = Build-Filter -W $info.Width -H $info.Height -MaxSize $cfg.Size `
                               -FpsValue $cfg.Fps -Denoise $cfg.Dn -Colors $cfg.Colors
        $sw = [Diagnostics.Stopwatch]::StartNew()
        try {
            Invoke-Encode -Src $Src -Dst $dst -Filter $filter
        } catch {
            Write-Host ("        档{0} 编码失败: {1}" -f ($i + 1), $_.Exception.Message) -ForegroundColor Red
            if (Test-Path -LiteralPath $dst) { Remove-Item -LiteralPath $dst -Force -ErrorAction SilentlyContinue }
            return 'fail'
        }
        $sw.Stop()

        $bytes = (Get-Item -LiteralPath $dst).Length
        $mb = [math]::Round($bytes / 1MB, 2)

        if ($bytes -lt $bestBytes) { $bestBytes = $bytes; $bestIndex = $i }

        $mark = ''
        if ($bytes -le $limit) { $mark = '  <= 达标'; $passed = $true }
        Write-Host ("        档{0} [{1}] {2}px @{3}fps 去噪{4} {5}色 -> {6} MB{7}  ({8:N1}s)" -f `
            ($i + 1), $cfg.Note, $cfg.Size, $cfg.Fps, $cfg.Dn, $cfg.Colors, $mb, $mark, $sw.Elapsed.TotalSeconds) `
            -ForegroundColor $(if ($passed) { 'Green' } else { 'DarkGray' })

        if ($passed) { break }
    }

    # 所有档都超标：回退到体积最小的那一档
    if (-not $passed -and $bestIndex -ge 0 -and $bestIndex -ne $lastIndex) {
        $cfg = $Ladder[$bestIndex]
        $filter = Build-Filter -W $info.Width -H $info.Height -MaxSize $cfg.Size `
                               -FpsValue $cfg.Fps -Denoise $cfg.Dn -Colors $cfg.Colors
        Invoke-Encode -Src $Src -Dst $dst -Filter $filter
    }

    $finalBytes = (Get-Item -LiteralPath $dst).Length
    $finalMB = [math]::Round($finalBytes / 1MB, 2)
    $cut = [math]::Round((1 - ($finalBytes / $srcBytes)) * 100, 0)

    # 体积回退保护：转换后反而更大、且源文件本身已达标，就不做这次无意义的转换
    if (-not $Force -and $finalBytes -gt $srcBytes -and $srcBytes -le $limit) {
        Remove-Item -LiteralPath $dst -Force -ErrorAction SilentlyContinue
        Write-Host ("        源文件仅 {0} MB（已达标），转换后会变成 {1} MB，故保留源文件不转换；" -f $srcMB, $finalMB) -ForegroundColor Yellow
        Write-Host '        如确实要统一转成 GIF，请加 -Force。' -ForegroundColor Yellow
        Write-Host ''
        return 'skip'
    }

    if ($passed) {
        $pct = if ($cut -ge 0) { "减少 $cut%" } else { "增加 " + [math]::Abs($cut) + "%" }
        Write-Host ("        √ 完成: {0} MB (原 {1} MB, {2})" -f $finalMB, $srcMB, $pct) -ForegroundColor Green
    } else {
        Write-Host ("        ! 已压到最小 {0} MB，仍超过 {1} MB 目标；建议再降 -TargetMB 或缩短时长" -f $finalMB, $TargetMB) -ForegroundColor Yellow
    }
    Write-Host ("        输出: {0}" -f $dst) -ForegroundColor DarkGray
    Write-Host ''

    if ($passed) { return 'ok' } else { return 'warn' }
}

# ============================ 主流程 ============================

if ($ShowHelp -or $Inputs.Count -eq 0) {
    Show-Usage
    exit 0
}

Show-Banner

$script:FFmpeg = Find-Tool -Name 'ffmpeg'
if (-not $script:FFmpeg) {
    Write-Host '找不到 ffmpeg.exe。' -ForegroundColor Red
    Write-Host '请安装 ffmpeg 并把它加入 PATH，或把 ffmpeg.exe / ffprobe.exe 放到本脚本同一目录。' -ForegroundColor Yellow
    exit 2
}
$ffDir = Split-Path -Parent $script:FFmpeg
$script:FFprobe = Join-Path $ffDir 'ffprobe.exe'
if (-not (Test-Path -LiteralPath $script:FFprobe)) {
    $script:FFprobe = Find-Tool -Name 'ffprobe'
}
if (-not $script:FFprobe) {
    Write-Host '找不到 ffprobe.exe（ffmpeg 同目录下应有）。' -ForegroundColor Red
    exit 2
}
Write-Host ("  引擎     : {0}" -f $script:FFmpeg) -ForegroundColor DarkGray
Write-Host ''

$exts = @('.gif', '.webp', '.mp4', '.mov', '.webm', '.m4v', '.apng')
$files = New-Object System.Collections.ArrayList

foreach ($p in $Inputs) {
    if ([string]::IsNullOrWhiteSpace($p)) { continue }
    if (Test-Path -LiteralPath $p -PathType Container) {
        $found = Get-ChildItem -LiteralPath $p -Recurse -File -ErrorAction SilentlyContinue |
                 Where-Object { $exts -contains $_.Extension.ToLower() } |
                 Sort-Object FullName
        foreach ($f in $found) { [void]$files.Add($f.FullName) }
        if (-not $found) {
            Write-Host ("目录里没有找到动图: {0}" -f $p) -ForegroundColor Yellow
        }
    } elseif (Test-Path -LiteralPath $p -PathType Leaf) {
        [void]$files.Add((Resolve-Path -LiteralPath $p).Path)
    } else {
        Write-Host ("找不到: {0}" -f $p) -ForegroundColor Yellow
    }
}

$files = $files | Select-Object -Unique
if (-not $files -or $files.Count -eq 0) {
    Write-Host '没有可处理的文件。' -ForegroundColor Yellow
    exit 1
}

$ladder = Get-Ladder -BaseSize $Size
$ok = 0; $warn = 0; $skip = 0; $fail = 0
$idx = 0
foreach ($f in $files) {
    $idx++
    switch (Process-One -Src $f -Index $idx -Total $files.Count -Ladder $ladder) {
        'ok'   { $ok++ }
        'warn' { $warn++ }
        'skip' { $skip++ }
        default { $fail++ }
    }
}

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ("  完成: 达标 {0} 个, 存疑 {1} 个, 跳过 {2} 个, 失败 {3} 个" -f $ok, $warn, $skip, $fail) -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ''

if ($fail -gt 0) { exit 1 }
exit 0
