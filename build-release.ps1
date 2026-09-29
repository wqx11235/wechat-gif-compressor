# =====================================================================
#  打包脚本：生成「开箱即用」发行包（内含 ffmpeg.exe）
#  ------------------------------------------------------------------
#  用法（在仓库根目录执行）：
#      powershell -ExecutionPolicy Bypass -File build-release.ps1
#      powershell -ExecutionPolicy Bypass -File build-release.ps1 -FfmpegDir 'D:\ffmpeg\ffmpeg-8.1.1-essentials_build\bin'
#
#  产物：..\_publish\wechat-gif-compressor-<版本>-win64.zip
#       （即一个解压即用的文件夹：脚本 + cmd + 说明 + bin\ffmpeg.exe）
#
#  说明：ffmpeg.exe 只作为 GitHub Release 附件分发，不进 git 仓库。
# =====================================================================

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$Version   = '1.0.1'
$FfmpegDir = 'D:\ffmpeg\ffmpeg-8.1.1-essentials_build\bin'

# 允许命令行覆盖
for ($i = 0; $i -lt $args.Count; $i++) {
    if ($args[$i] -eq '-Version' -and ($i + 1) -lt $args.Count)   { $Version   = [string]$args[$i + 1] }
    if ($args[$i] -eq '-FfmpegDir' -and ($i + 1) -lt $args.Count) { $FfmpegDir = [string]$args[$i + 1] }
}

$Root    = $PSScriptRoot
$Name    = "wechat-gif-compressor-$Version-win64"
$OutRoot = Join-Path (Split-Path -Parent $Root) '_publish'
$PkgDir  = Join-Path $OutRoot $Name
$ZipPath = Join-Path $OutRoot "$Name.zip"

Write-Host "打包 $Name" -ForegroundColor Cyan
Write-Host "  源目录: $Root"
Write-Host "  输出  : $ZipPath"

# --- 校验源文件 ---
$need = @('wechat-gif-compress.ps1', '压缩微信表情包.cmd', '使用说明.md', 'README.md', 'CHANGELOG.md', 'LICENSE', '第三方组件说明.txt')
foreach ($f in $need) {
    if (-not (Test-Path -LiteralPath (Join-Path $Root $f))) { throw "缺少文件: $f" }
}
$ffmpeg = Join-Path $FfmpegDir 'ffmpeg.exe'
if (-not (Test-Path -LiteralPath $ffmpeg)) { throw "找不到 ffmpeg.exe: $ffmpeg（用 -FfmpegDir 指定）" }

# --- 组装 ---
if (Test-Path -LiteralPath $PkgDir) { Remove-Item -LiteralPath $PkgDir -Recurse -Force }
New-Item -ItemType Directory -Path (Join-Path $PkgDir 'bin') -Force | Out-Null
foreach ($f in $need) { Copy-Item -LiteralPath (Join-Path $Root $f) -Destination $PkgDir -Force }
Copy-Item -LiteralPath $ffmpeg -Destination (Join-Path $PkgDir 'bin\ffmpeg.exe') -Force

# ffmpeg 的 GPLv3 全文（合规分发要求）
$lic = Join-Path (Split-Path -Parent $FfmpegDir) 'LICENSE'
if (Test-Path -LiteralPath $lic) {
    Copy-Item -LiteralPath $lic -Destination (Join-Path $PkgDir 'bin\LICENSE-ffmpeg-GPLv3.txt') -Force
}

# --- 打包（.NET ZipArchive，比 Compress-Archive 快得多）---
if (Test-Path -LiteralPath $ZipPath) { Remove-Item -LiteralPath $ZipPath -Force }
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory(
    $PkgDir, $ZipPath, [System.IO.Compression.CompressionLevel]::Optimal, $true)

$zipMB = [math]::Round((Get-Item -LiteralPath $ZipPath).Length / 1MB, 1)
Write-Host "完成: $ZipPath  ($zipMB MB)" -ForegroundColor Green
