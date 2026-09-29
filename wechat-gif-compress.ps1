<#
  微信动图 / 视频压缩工具
  ------------------------------------------------------------------
  把动图、视频压到能直接在微信聊天里发送的大小：
    动图（gif/apng/静态 webp） -> 默认目标 <= 9.5 MB，输出 GIF（推荐版格式）
    视频（mp4/mov/m4v/webm/mkv/avi）-> 默认目标 <= 20 MB，**原格式进、原格式出**

  动图默认「推荐版」参数：长边 400px / 25fps / 256 色 / 去噪 + 帧间矩形差分包。
  视频默认按目标体积反算码率（H.264/VP9 + AAC/Opus），长边不超过 1280px，只缩不放。

  用法（把文件或文件夹拖到同目录的「压缩微信表情包.cmd」上即可）：
      powershell -ExecutionPolicy Bypass -File wechat-gif-compress.ps1 a.gif b.mp4
      -TargetMB 5        动图目标体积（默认 9.5；微信「添加表情」上限约 5MB）
      -VideoMB 20        视频目标体积（默认 20；微信聊天视频上限约 25MB）
      -Size 400          动图长边像素上限（默认 400，不会放大）
      -Fps 25            动图帧率上限（默认 25）
      -VideoSize 1280    视频长边像素上限（默认 1280，不会放大）
      -VideoFormat mp4   强制视频输出格式（默认与输入相同）
      -ToGif             视频也转成 GIF（旧行为）
      -OutDir 微信版     输出子目录名（默认「微信版」）

  达标不了的会自动逐档加强（去噪/帧率/分辨率/码率），直到达标或压到最小。

  引擎：只需要 ffmpeg.exe 一个文件（不需要 ffprobe）。
  查找顺序：本脚本同目录的 bin\ -> 本脚本同目录 -> 系统 PATH -> 常见安装位置。
  开箱即用包（内置 ffmpeg，解压即用）:
      https://github.com/wqx11235/wechat-gif-compressor/releases
#>
# --- 参数：手工解析，避开 PS 5.1 的位置绑定 / CmdletBinding 陷阱 ---
$TargetMB    = 9.5
$VideoMB     = 20
$Size        = 400
$Fps         = 25
$VideoSize   = 1280
$VideoFormat = ''
$ToGif       = $false
$OutDir      = '微信版'
$ShowHelp    = $false
$Force       = $false

$Inputs = New-Object System.Collections.ArrayList
$argv = @($args)
for ($i = 0; $i -lt $argv.Count; $i++) {
    $a = [string]$argv[$i]
    if     ($a -eq '-TargetMB'    -and ($i + 1) -lt $argv.Count) { $i++; $TargetMB    = [double]$argv[$i] }
    elseif ($a -eq '-VideoMB'     -and ($i + 1) -lt $argv.Count) { $i++; $VideoMB     = [double]$argv[$i] }
    elseif ($a -eq '-Size'        -and ($i + 1) -lt $argv.Count) { $i++; $Size        = [int]$argv[$i] }
    elseif ($a -eq '-Fps'         -and ($i + 1) -lt $argv.Count) { $i++; $Fps         = [int]$argv[$i] }
    elseif ($a -eq '-VideoSize'   -and ($i + 1) -lt $argv.Count) { $i++; $VideoSize   = [int]$argv[$i] }
    elseif ($a -eq '-VideoFormat' -and ($i + 1) -lt $argv.Count) { $i++; $VideoFormat = ([string]$argv[$i]).TrimStart('.', '-').ToLower() }
    elseif ($a -eq '-OutDir'      -and ($i + 1) -lt $argv.Count) { $i++; $OutDir      = [string]$argv[$i] }
    elseif ($a -eq '-ToGif') { $ToGif = $true }
    elseif ($a -eq '-Force') { $Force = $true }
    elseif ($a -eq '-h' -or $a -eq '-Help' -or $a -eq '--help') { $ShowHelp = $true }
    else   { [void]$Inputs.Add($a) }
}

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
$OutputEncoding = [Text.Encoding]::UTF8

$script:FFmpeg = $null

function Show-Banner {
    Write-Host ''
    Write-Host '============================================================' -ForegroundColor Cyan
    Write-Host '  微信动图 / 视频压缩工具' -ForegroundColor Cyan
    Write-Host '============================================================' -ForegroundColor Cyan
    if ($ToGif) {
        Write-Host ("  动图/视频 : 统一转为 GIF，每个文件 <= {0} MB" -f $TargetMB)
        Write-Host ("  输出规格  : 长边 {0}px / {1}fps / 256 色 / 去噪 / 帧间差分" -f $Size, $Fps)
    } else {
        Write-Host ("  动图      : 每个文件 <= {0} MB（长边 {1}px / {2}fps / 256 色 / 去噪）" -f $TargetMB, $Size, $Fps)
        if ($VideoFormat) {
            Write-Host ("  视频      : 每个文件 <= {0} MB（长边 {1}px / 强制输出 {2}）" -f $VideoMB, $VideoSize, $VideoFormat)
        } else {
            Write-Host ("  视频      : 每个文件 <= {0} MB（长边 {1}px / 原格式进原格式出）" -f $VideoMB, $VideoSize)
        }
    }
    Write-Host ("  输出位置  : 源文件旁边的「{0}」子目录" -f $OutDir)
    Write-Host ''
}

function Show-Usage {
    Show-Banner
    Write-Host '用法：把这个文件（或文件夹）拖到「压缩微信表情包.cmd」上' -ForegroundColor Yellow
    Write-Host '      动图 .gif/.apng/.webp  -> 输出 GIF'
    Write-Host '      视频 .mp4/.mov/.m4v/.webm/.mkv/.avi -> 原格式进、原格式出'
    Write-Host ''
    Write-Host '命令行参数（可选）：'
    Write-Host '  -TargetMB 5      动图目标体积 MB（默认 9.5，微信「添加表情」上限约 5）'
    Write-Host '  -VideoMB 20      视频目标体积 MB（默认 20，微信聊天视频上限约 25）'
    Write-Host '  -Size 400        动图长边像素上限，只缩不放（默认 400）'
    Write-Host '  -Fps 25          动图帧率上限（默认 25）'
    Write-Host '  -VideoSize 1280  视频长边像素上限，只缩不放（默认 1280）'
    Write-Host '  -VideoFormat mp4 强制视频输出格式（默认与输入相同；可填 gif 表示转动图）'
    Write-Host '  -ToGif           视频也转成 GIF（旧行为）'
    Write-Host '  -OutDir 微信版   输出子目录名（默认「微信版」）'
    Write-Host '  -Force           即使转换后体积更大也强制转换（默认自动回退）'
    Write-Host ''
    Write-Host '示例：'
    Write-Host '  powershell -ExecutionPolicy Bypass -File wechat-gif-compress.ps1 表情.gif -TargetMB 5'
    Write-Host '  powershell -ExecutionPolicy Bypass -File wechat-gif-compress.ps1 视频.mp4 -VideoMB 10'
    Write-Host '  powershell -ExecutionPolicy Bypass -File wechat-gif-compress.ps1 视频.mov -VideoFormat mp4'
    Write-Host ''
}

function Find-Tool {
    param([string]$Name)

    # 1) 随工具分发的引擎优先（压缩包里的 bin\ffmpeg.exe），保证谁拿到都是同一版本
    if ($PSScriptRoot) {
        foreach ($rel in @('bin', '')) {
            if ($rel) { $p = Join-Path (Join-Path $PSScriptRoot $rel) ($Name + '.exe') }
            else      { $p = Join-Path $PSScriptRoot ($Name + '.exe') }
            if (Test-Path -LiteralPath $p) { return $p }
        }
    }

    # 2) 系统 PATH
    $cmd = Get-Command ($Name + '.exe') -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    # 3) 常见安装位置
    $roots = @(
        'D:\ffmpeg', 'C:\ffmpeg',
        (Join-Path $env:ProgramFiles 'ffmpeg'),
        (Join-Path ${env:ProgramFiles(x86)} 'ffmpeg'),
        (Join-Path $env:LOCALAPPDATA 'ffmpeg'),
        (Join-Path $env:USERPROFILE 'ffmpeg'),
        (Join-Path $env:USERPROFILE 'scoop\apps\ffmpeg\current'),
        'C:\ProgramData\chocolatey\bin'
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

# 运行 ffmpeg 并把 stderr 原样取回。
# 陷阱：PS 5.1 里原生命令的 stderr 会被包成 ErrorRecord；脚本顶部的
# $ErrorActionPreference='Stop' 会让它升级成终止性 NativeCommandError（实测直接中断脚本，
# 尤其是写成 `& ffmpeg ... 2>&1 | Out-String` 这种管道形式）。
# 做法：临时改成 Continue、用赋值而不是管道收集，取完立刻还原。
function Invoke-FFRaw {
    param([string[]]$FFArgs)

    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $captured = & $script:FFmpeg @FFArgs 2>&1
    } finally {
        $ErrorActionPreference = $old
    }
    return ($captured | Out-String)
}

function Get-MediaInfo {
    param([string]$Path)

    # 只用 ffmpeg 自身探测：-i 会把元信息打到 stderr（不产生输出文件，退出码非 0 属正常）
    $raw = Invoke-FFRaw -FFArgs @('-hide_banner', '-nostdin', '-i', $Path)
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }

    # 注意：ffmpeg 的流信息会在约 119 列处折行（实测 1280x720 的 h264 行被切成两行，
    # 「30 fps」掉到第二行上），所以把 Video: 那一行连同后面几行拼起来再匹配。
    $lines = $raw -split "`r?`n"
    $vi = -1
    $hasAudio = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $l = $lines[$i]
        if ($vi -lt 0 -and $l -match 'Stream #\d+:\d+.*: Video:') { $vi = $i }
        if ($l -match 'Stream #\d+:\d+.*: Audio:') { $hasAudio = $true }
    }

    $vline = ''
    if ($vi -ge 0) {
        $end = [math]::Min($vi + 3, $lines.Count - 1)
        $vline = (($lines[$vi..$end]) -join ' ')
    }

    $w = 0; $h = 0; $fps = 0.0
    if ($vline -match ',\s*(\d{2,5})x(\d{2,5})[\s,]') {
        $w = [int]$Matches[1]; $h = [int]$Matches[2]
    }
    if ($vline -match ',\s*([\d.]+)\s*fps') { $fps = [double]$Matches[1] }

    $dur = 0.0
    if ($raw -match 'Duration:\s*(\d+):(\d+):([\d.]+)') {
        $dur = [double]$Matches[1] * 3600 + [double]$Matches[2] * 60 + [double]$Matches[3]
    }

    # 帧数：-c copy 到 null 只拆包、不解码，13MB/78 帧的 GIF 约 0.1 秒
    $frames = 0
    $stat = Invoke-FFRaw -FFArgs @('-hide_banner', '-nostdin', '-i', $Path, '-c', 'copy', '-f', 'null', '-')
    if ($stat -match 'frame=\s*(\d+)') { $frames = [int]$Matches[1] }

    if ($w -le 0 -and $frames -le 0 -and $dur -le 0) { return $null }

    return @{
        Width    = $w
        Height   = $h
        Fps      = [math]::Round($fps, 2)
        Frames   = $frames
        Dur      = [math]::Round($dur, 2)
        HasAudio = $hasAudio
    }
}

# ============================ 动图（GIF）部分 ============================

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

function Invoke-GifPipeline {
    param([string]$Src, [string]$Dst, $Info, [double]$SrcBytes, [double]$SrcMB)

    $limit = $TargetMB * 1MB
    $ladder = Get-Ladder -BaseSize $Size
    $bestBytes = [double]::MaxValue
    $bestIndex = -1
    $passed = $false
    $lastIndex = $ladder.Count - 1

    for ($i = 0; $i -lt $ladder.Count; $i++) {
        $cfg = $ladder[$i]
        $filter = Build-Filter -W $Info.Width -H $Info.Height -MaxSize $cfg.Size `
                               -FpsValue $cfg.Fps -Denoise $cfg.Dn -Colors $cfg.Colors
        $sw = [Diagnostics.Stopwatch]::StartNew()
        try {
            Invoke-Encode -Src $Src -Dst $Dst -Filter $filter
        } catch {
            Write-Host ("        档{0} 编码失败: {1}" -f ($i + 1), $_.Exception.Message) -ForegroundColor Red
            if (Test-Path -LiteralPath $Dst) { Remove-Item -LiteralPath $Dst -Force -ErrorAction SilentlyContinue }
            return 'fail'
        }
        $sw.Stop()

        $bytes = (Get-Item -LiteralPath $Dst).Length
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
        $cfg = $ladder[$bestIndex]
        $filter = Build-Filter -W $Info.Width -H $Info.Height -MaxSize $cfg.Size `
                               -FpsValue $cfg.Fps -Denoise $cfg.Dn -Colors $cfg.Colors
        Invoke-Encode -Src $Src -Dst $Dst -Filter $filter
    }

    $finalBytes = (Get-Item -LiteralPath $Dst).Length
    $finalMB = [math]::Round($finalBytes / 1MB, 2)

    if (-not $passed -and $bestIndex -ge 0 -and $bestIndex -ne ($ladder.Count - 1)) { $passed = $false }

    return (Complete-Result -Src $Src -Dst $Dst -SrcBytes $SrcBytes -SrcMB $SrcMB `
                            -FinalBytes $finalBytes -FinalMB $finalMB -Passed $passed `
                            -LimitMB $TargetMB -ForceHint '如确实要重新压缩，请加 -Force。')
}

# ============================ 视频部分 ============================

# 输出容器：默认与输入同格式；-VideoFormat 可强制；-ToGif 一律转 GIF
function Get-OutputFormat {
    param([string]$Src)

    if ($ToGif) { return 'gif' }
    if ($VideoFormat) { return $VideoFormat }

    switch ([IO.Path]::GetExtension($Src).TrimStart('.').ToLower()) {
        'mp4'  { return 'mp4' }
        'm4v'  { return 'm4v' }
        'mov'  { return 'mov' }
        'webm' { return 'webm' }
        'mkv'  { return 'mkv' }
        'avi'  { return 'avi' }
        default { return 'gif' }
    }
}

# 按目标体积和时长反算视频码率（bps）；时长未知返回 0（改用 CRF）
function Get-VideoBitrate {
    param([double]$Dur, [double]$LimitBytes, [bool]$HasAudio, [int]$AudioKbps = 96)

    if ($Dur -le 0) { return 0 }

    $usable = $LimitBytes * 8 * 0.95          # 留 5% 容器/封装开销，尽量一次到位
    $audioBits = 0.0
    if ($HasAudio) { $audioBits = $AudioKbps * 1000 * $Dur }

    $vBits = $usable - $audioBits
    if ($vBits -lt 50000 * $Dur) { $vBits = 50000 * $Dur }   # 最低 50 kbps 保底
    $bps = $vBits / $Dur
    if ($bps -gt 12000000) { $bps = 12000000 }

    return [int]([math]::Floor($bps / 1000) * 1000)
}

# 长边不超过 Cap（只缩不放）；W:H 都是偶数；无需缩放返回空串
function Get-VideoScale {
    param([int]$W, [int]$H, [int]$Cap)

    if ($W -le 0 -or $H -le 0) { return '' }

    $target = 0
    if ($Cap -gt 0) { $target = $Cap } else { $target = [math]::Max($W, $H) }
    $long = [math]::Max($W, $H)
    $nw = $W; $nh = $H
    if ($long -gt $target) {
        $ratio = $target / $long
        $nw = [int][math]::Round($W * $ratio)
        $nh = [int][math]::Round($H * $ratio)
    }
    if ($nw % 2 -ne 0) { $nw-- }
    if ($nh % 2 -ne 0) { $nh-- }
    if ($nw -lt 2) { $nw = 2 }
    if ($nh -lt 2) { $nh = 2 }

    if ($nw -eq $W -and $nh -eq $H) { return '' }
    return "${nw}:${nh}"
}

function Get-VideoCodecArgs {
    param([string]$Fmt, [int]$Vbps, [bool]$HasAudio, [int]$CrfStep = 0)

    $v = @(); $au = @(); $mx = @()

    switch ($Fmt) {
        'webm' {
            $v = @('-c:v', 'libvpx-vp9', '-deadline', 'good', '-cpu-used', '4', '-row-mt', '1', '-pix_fmt', 'yuv420p')
            if ($Vbps -gt 0) {
                $v += @('-b:v', "$Vbps", '-maxrate', "$([int]($Vbps * 1.5))", '-bufsize', "$([int]($Vbps * 2))")
            } else {
                $v += @('-crf', "$(32 + 2 * $CrfStep)", '-b:v', '0')
            }
            if ($HasAudio) { $au = @('-c:a', 'libopus', '-b:a', '96k') }
        }
        'avi' {
            $v = @('-c:v', 'libx264', '-preset', 'medium', '-pix_fmt', 'yuv420p')
            if ($Vbps -gt 0) {
                $v += @('-b:v', "$Vbps", '-maxrate', "$([int]($Vbps * 1.5))", '-bufsize', "$([int]($Vbps * 2))")
            } else {
                $v += @('-crf', "$(26 + 2 * $CrfStep)")
            }
            if ($HasAudio) { $au = @('-c:a', 'libmp3lame', '-b:a', '96k') }
        }
        default {   # mp4 / m4v / mov / mkv
            $v = @('-c:v', 'libx264', '-preset', 'medium', '-profile:v', 'high', '-pix_fmt', 'yuv420p')
            if ($Vbps -gt 0) {
                $v += @('-b:v', "$Vbps", '-maxrate', "$([int]($Vbps * 1.5))", '-bufsize', "$([int]($Vbps * 2))")
            } else {
                $v += @('-crf', "$(26 + 2 * $CrfStep)")
            }
            if ($HasAudio) { $au = @('-c:a', 'aac', '-b:a', '96k') }
            if ($Fmt -eq 'mp4' -or $Fmt -eq 'm4v' -or $Fmt -eq 'mov') { $mx = @('-movflags', '+faststart') }
        }
    }

    return @{ Video = $v; Audio = $au; Mux = $mx }
}

# 视频编码：进度行直接透传到控制台（不捕获），失败抛异常
function Invoke-VideoEncode {
    param([string]$Src, [string]$Dst, [string]$Fmt, [string]$Scale, [int]$Vbps, [bool]$HasAudio, [int]$CrfStep = 0)

    $ck = Get-VideoCodecArgs -Fmt $Fmt -Vbps $Vbps -HasAudio $HasAudio -CrfStep $CrfStep

    $a = @('-y', '-hide_banner', '-nostdin', '-loglevel', 'warning', '-stats', '-i', $Src, '-map', '0:v:0')
    if ($HasAudio) { $a += @('-map', '0:a:0') }
    if ($Scale) { $a += @('-vf', "scale=$Scale") }
    $a += $ck.Video
    if ($HasAudio) { $a += $ck.Audio } else { $a += @('-an') }
    $a += $ck.Mux
    $a += $Dst

    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $script:FFmpeg @a
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $old
    }
    if ($code -ne 0) { throw "ffmpeg 退出码 $code" }
}

function Invoke-VideoPipeline {
    param([string]$Src, [string]$Dst, [string]$Fmt, $Info, [double]$SrcBytes, [double]$SrcMB)

    $limit = $VideoMB * 1MB
    $baseBps = Get-VideoBitrate -Dur $Info.Dur -LimitBytes $limit -HasAudio $Info.HasAudio

    if ($baseBps -gt 0) {
        Write-Host ("        目标码率: {0} kbps（时长 {1}s 反算，音轨 {2}）" -f `
            [int]($baseBps / 1000), $Info.Dur, $(if ($Info.HasAudio) { '96 kbps' } else { '无' })) -ForegroundColor DarkGray
        if ($baseBps -lt 300000) {
            Write-Host '        提示: 视频较长，码率会压得比较狠，画面可能偏糊。' -ForegroundColor Yellow
        }
    } else {
        Write-Host '        无法读取时长，改用 CRF 自动码率（体积可能不精确）' -ForegroundColor Yellow
    }

    $ladder = @(
        @{ Cap = $VideoSize; Factor = 1.00; Note = '推荐' },
        @{ Cap = $VideoSize; Factor = 0.85; Note = '码率回调' },
        @{ Cap = 960;        Factor = 0.80; Note = '降分辨率' },
        @{ Cap = 854;        Factor = 0.70; Note = '继续降' },
        @{ Cap = 640;        Factor = 0.60; Note = '强压缩' }
    )

    $bestBytes = [double]::MaxValue
    $bestIndex = -1
    $bestFactor = 1.0
    $passed = $false
    $lastIndex = $ladder.Count - 1
    $prevBytes = 0.0
    $prevFactor = 1.0

    for ($i = 0; $i -lt $ladder.Count; $i++) {
        $cfg = $ladder[$i]

        # 第二档起：按上一档的实测体积反推这次该给多少码率（而不是一刀切再砍 15%），
        # 省下来的余量全都会变成画质。
        $factor = $cfg.Factor
        if ($i -gt 0 -and $baseBps -gt 0 -and $prevBytes -gt 0) {
            $factor = $prevFactor * ($limit / $prevBytes) * 0.97
            if ($factor -ge $prevFactor) { $factor = $prevFactor * 0.9 }
            if ($factor -lt 0.3) { $factor = 0.3 }
        }

        $bps = 0
        if ($baseBps -gt 0) { $bps = [int]($baseBps * $factor) }

        $scale = Get-VideoScale -W $Info.Width -H $Info.Height -Cap $cfg.Cap
        $sw = [Diagnostics.Stopwatch]::StartNew()
        try {
            Invoke-VideoEncode -Src $Src -Dst $Dst -Fmt $Fmt -Scale $scale -Vbps $bps `
                               -HasAudio $Info.HasAudio -CrfStep $i
        } catch {
            Write-Host ("        档{0} 编码失败: {1}" -f ($i + 1), $_.Exception.Message) -ForegroundColor Red
            if (Test-Path -LiteralPath $Dst) { Remove-Item -LiteralPath $Dst -Force -ErrorAction SilentlyContinue }
            return 'fail'
        }
        $sw.Stop()

        $bytes = (Get-Item -LiteralPath $Dst).Length
        $mb = [math]::Round($bytes / 1MB, 2)

        if ($bytes -lt $bestBytes) { $bestBytes = $bytes; $bestIndex = $i; $bestFactor = $factor }
        $prevBytes = $bytes
        $prevFactor = $factor

        $mark = ''
        if ($bytes -le $limit) { $mark = '  <= 达标'; $passed = $true }
        $srctxt = if ($scale) { "${scale}" } else { '原尺寸' }
        $erate = if ($bps -gt 0) { "{0} kbps" -f [int]($bps / 1000) } else { 'CRF' }
        Write-Host ("        档{0} [{1}] {2} {3} -> {4} MB{5}  ({6:N1}s)" -f `
            ($i + 1), $cfg.Note, $srctxt, $erate, $mb, $mark, $sw.Elapsed.TotalSeconds) `
            -ForegroundColor $(if ($passed) { 'Green' } else { 'DarkGray' })

        if ($passed) { break }
    }

    # 所有档都超标：回退到体积最小的那一档
    if (-not $passed -and $bestIndex -ge 0 -and $bestIndex -ne $lastIndex) {
        $cfg = $ladder[$bestIndex]
        $bps = 0
        if ($baseBps -gt 0) { $bps = [int]($baseBps * $bestFactor) }
        $scale = Get-VideoScale -W $Info.Width -H $Info.Height -Cap $cfg.Cap
        Invoke-VideoEncode -Src $Src -Dst $Dst -Fmt $Fmt -Scale $scale -Vbps $bps `
                           -HasAudio $Info.HasAudio -CrfStep $bestIndex
    }

    $finalBytes = (Get-Item -LiteralPath $Dst).Length
    $finalMB = [math]::Round($finalBytes / 1MB, 2)

    return (Complete-Result -Src $Src -Dst $Dst -SrcBytes $SrcBytes -SrcMB $SrcMB `
                            -FinalBytes $finalBytes -FinalMB $finalMB -Passed $passed `
                            -LimitMB $VideoMB -ForceHint '如确实要重新编码，请加 -Force。')
}

# ============================ 收尾（回退保护 + 汇总） ============================

function Complete-Result {
    param([string]$Src, [string]$Dst, [double]$SrcBytes, [double]$SrcMB,
          [double]$FinalBytes, [double]$FinalMB, [bool]$Passed,
          [double]$LimitMB, [string]$ForceHint)

    $cut = [math]::Round((1 - ($FinalBytes / $SrcBytes)) * 100, 0)

    # 体积回退保护：转换后反而更大、且源文件本身已达标，就不做这次无意义的转换
    if (-not $Force -and $FinalBytes -gt $SrcBytes -and $SrcBytes -le ($LimitMB * 1MB)) {
        Remove-Item -LiteralPath $Dst -Force -ErrorAction SilentlyContinue
        Write-Host ("        源文件仅 {0} MB，本身就在 {1} MB 目标内，无需压缩；" -f $SrcMB, $LimitMB) -ForegroundColor Yellow
        Write-Host ("        （重新编码后是 {0} MB，反而更大，已保留源文件）" -f $FinalMB) -ForegroundColor DarkGray
        Write-Host ("        {0}" -f $ForceHint) -ForegroundColor Yellow
        Write-Host ''
        return 'skip'
    }

    if ($Passed) {
        $pct = if ($cut -ge 0) { "减少 $cut%" } else { "增加 " + [math]::Abs($cut) + "%" }
        Write-Host ("        √ 完成: {0} MB (原 {1} MB, {2})" -f $FinalMB, $SrcMB, $pct) -ForegroundColor Green
    } else {
        Write-Host ("        ! 已压到最小 {0} MB，仍超过 {1} MB 目标；建议再降 -TargetMB/-VideoMB 或缩短时长" -f $FinalMB, $LimitMB) -ForegroundColor Yellow
    }
    Write-Host ("        输出: {0}" -f $Dst) -ForegroundColor DarkGray
    Write-Host ''

    if ($Passed) { return 'ok' } else { return 'warn' }
}

function Process-One {
    param([string]$Src, [int]$Index, [int]$Total)

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
        Write-Host '        无法读取（不是有效动图/视频？），跳过。' -ForegroundColor Yellow
        return 'fail'
    }
    if ($info.Width -le 0 -and $info.Frames -le 0) {
        Write-Host ("[{0}/{1}] {2}" -f $Index, $Total, $name) -ForegroundColor Yellow
        Write-Host '        引擎读不出这个格式的画面（常见于动画 WebP），跳过。' -ForegroundColor Yellow
        return 'skip'
    }
    if ($info.Frames -le 1 -and $info.Dur -le 0) {
        Write-Host ("[{0}/{1}] {2}" -f $Index, $Total, $name) -ForegroundColor Yellow
        Write-Host '        这是静态图，不是动图，跳过。' -ForegroundColor Yellow
        return 'skip'
    }

    Write-Host ("[{0}/{1}] {2}" -f $Index, $Total, $name) -ForegroundColor White
    Write-Host ("        原始: {0} MB, {1}x{2}, {3}fps, {4} 帧, {5}s{6}" -f `
        $srcMB, $info.Width, $info.Height, $info.Fps, $info.Frames, $info.Dur,
        $(if ($info.HasAudio) { ', 含音轨' } else { '' })) -ForegroundColor DarkGray

    $leafDir = Split-Path -Leaf $dir
    if ($leafDir -eq $OutDir) { $targetDir = $dir }
    else { $targetDir = Join-Path $dir $OutDir }

    if (-not (Test-Path -LiteralPath $targetDir)) {
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    }

    $fmt = Get-OutputFormat -Src $Src

    if ($fmt -eq 'gif') {
        $dst = Join-Path $targetDir ($base + '.微信版.gif')
        return (Invoke-GifPipeline -Src $Src -Dst $dst -Info $info -SrcBytes $srcBytes -SrcMB $srcMB)
    }

    $dst = Join-Path $targetDir ($base + '.微信版.' + $fmt)
    return (Invoke-VideoPipeline -Src $Src -Dst $dst -Fmt $fmt -Info $info -SrcBytes $srcBytes -SrcMB $srcMB)
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
    Write-Host '请用「开箱即用包」（内含 bin\ffmpeg.exe），或安装 ffmpeg 并加入 PATH，' -ForegroundColor Yellow
    Write-Host '或把 ffmpeg.exe 放到本脚本同目录（或同目录的 bin\ 里）。' -ForegroundColor Yellow
    Write-Host '开箱即用包: https://github.com/wqx11235/wechat-gif-compressor/releases' -ForegroundColor DarkGray
    exit 2
}
Write-Host ("  引擎     : {0}" -f $script:FFmpeg) -ForegroundColor DarkGray
Write-Host ''

$exts = @('.gif', '.webp', '.mp4', '.mov', '.webm', '.m4v', '.apng', '.mkv', '.avi')
$files = New-Object System.Collections.ArrayList

foreach ($p in $Inputs) {
    if ([string]::IsNullOrWhiteSpace($p)) { continue }
    if (Test-Path -LiteralPath $p -PathType Container) {
        $found = Get-ChildItem -LiteralPath $p -Recurse -File -ErrorAction SilentlyContinue |
                 Where-Object { $exts -contains $_.Extension.ToLower() } |
                 Sort-Object FullName
        foreach ($f in $found) { [void]$files.Add($f.FullName) }
        if (-not $found) {
            Write-Host ("目录里没有找到动图/视频: {0}" -f $p) -ForegroundColor Yellow
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

$ok = 0; $warn = 0; $skip = 0; $fail = 0
$idx = 0
foreach ($f in $files) {
    $idx++
    switch (Process-One -Src $f -Index $idx -Total $files.Count) {
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
