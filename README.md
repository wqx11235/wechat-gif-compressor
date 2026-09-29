# 微信动图压缩工具 · WeChat GIF Compressor

把体积过大的动图（GIF / WebP / MP4）一键压到**能直接在微信聊天里发送**的大小（默认 ≤ 9.5 MB），
Windows 下**把文件拖到 `.cmd` 上**即可，不需要任何第三方依赖（只要有 ffmpeg）。

典型效果：**13.5 MB → 5.5 MB（减少约 60%）**，肉眼几乎看不出差别。

```
13.48 MB, 500x500, 33fps  ──►  5.79 MB, 400x400, 25fps    (0.6 秒)
13.35 MB, 500x500, 33fps  ──►  5.47 MB, 400x400, 25fps    (0.4 秒)
```

---

## 为什么需要它

微信聊天发送图片的上限约 **10 MB**，而很多从网页/视频转出来的动图动辄 15~30 MB，
直接发会提示「图片过大」。常规的「调色板优化」对这类动图几乎无效——
它们每帧都是全帧且带大量噪点，GIF 的 LZW 压缩压不动（约 0.7 字节/像素）。

本工具的做法是**先去噪再编码**：噪点一去掉，相邻像素相关性变强、帧间差异变小，
LZW 和帧间差分才真正开始工作，体积随之断崖式下降。

## 特性

- **一键拖拽**：把动图或整个文件夹拖到 `压缩微信表情包.cmd` 上即可，支持批量。
- **推荐版参数**：长边 400px / 25fps / 256 色 / 去噪 / 帧间矩形差分，画质与体积平衡最佳。
- **自动降级**：若按推荐参数仍超目标，自动逐档加强（加强去噪 → 降帧率 → 微缩尺寸 → 减色，共 8 档）直到达标。
- **体积回退保护**：若转换后反而更大、且源文件本身已达标（常见于 mp4 输入），则保留源文件不转换。
- **不动原文件**：结果写到源文件旁边的 `微信版\` 子目录。
- **兼容 Windows PowerShell 5.1**（系统自带，无需安装 PowerShell 7）。

## 快速开始

1. 安装 [ffmpeg](https://ffmpeg.org/download.html) 并加入 `PATH`（或把 `ffmpeg.exe` / `ffprobe.exe` 放到本工具同目录）。
2. 把动图文件**拖到 `压缩微信表情包.cmd` 上**。
3. 结果出现在源文件旁边的 `微信版\` 文件夹里。

命令行用法：

```bat
powershell -ExecutionPolicy Bypass -File wechat-gif-compress.ps1 <文件或文件夹...> [参数]
```

| 参数 | 默认 | 说明 |
| --- | --- | --- |
| `-TargetMB` | `9.5` | 目标体积上限（MB）。微信聊天图片上限约 10 MB |
| `-Size` | `400` | 长边像素上限，**只缩不放**（源图更小则保持原尺寸） |
| `-Fps` | `25` | 帧率上限 |
| `-OutDir` | `微信版` | 输出子目录名 |
| `-Force` | 关 | 默认当「转换后反而更大且源文件已达标」时保留源文件；加此项强制转换 |

示例：

```bat
:: 压到 5MB 以内，用于微信「添加表情」（自定义表情上限约 5MB）
powershell -ExecutionPolicy Bypass -File wechat-gif-compress.ps1 表情.gif -TargetMB 5

:: 保持更高清晰度
powershell -ExecutionPolicy Bypass -File wechat-gif-compress.ps1 表情.gif -Size 500

:: 批量处理整个文件夹
powershell -ExecutionPolicy Bypass -File wechat-gif-compress.ps1 D:\表情包\待处理
```

## 压缩原理

| 步骤 | 作用 |
| --- | --- |
| 去噪 `hqdn3d` | 去掉颗粒噪点，提高空间相关性——**最关键的一步**，让 LZW 真正能压 |
| 降采样到长边 400px | 像素数减少，体积近似平方下降；表情包在手机上完全够看 |
| 降到 25fps | 原始多为 30~33fps，25fps 肉眼几乎无差别 |
| 256 色调色板 + 帧间矩形差分 | 只更新画面中变化的区域，而非每帧重画整幅 |
| 关闭抖动 `dither=none` | 抖动噪声会破坏帧间相似性，反而把体积顶上去 |

对应的 ffmpeg 滤镜链（推荐版）：

```
scale=400:-2:flags=lanczos,
hqdn3d=6:6:18:18,
fps=25,
split[s0][s1];
[s0]palettegen=max_colors=256:stats_mode=diff[p];
[s1]paletteuse=dither=none:diff_mode=rectangle
```

## 依赖

需要 **ffmpeg**（含 ffprobe）。工具按以下顺序自动查找：

1. 系统 `PATH` 里的 `ffmpeg.exe` / `ffprobe.exe`
2. 常见安装位置：`D:\ffmpeg\*`、`C:\ffmpeg\*`、`%ProgramFiles%\ffmpeg`、
   `%LOCALAPPDATA%\ffmpeg`、`%USERPROFILE%\ffmpeg`、scoop / chocolatey 目录
3. 本工具所在目录（把 `ffmpeg.exe` 和 `ffprobe.exe` 直接放这里最省事）

## 支持格式

输入：`.gif` / `.webp`（动图）/ `.mp4` / `.mov` / `.webm` / `.m4v` / `.apng`
输出：统一为 GIF

## 常见问题

**输出还是超过 10MB？**
源动图可能很长或噪点极重。用 `-TargetMB 5` 强制更狠的档位，或先剪短时长，
也可以降低 `-Size`（如 320）和 `-Fps`（如 15）。

**画面变糊了？**
去噪 + 缩图必然损失细节。更看重画质就用 `-Size 500` 并给足 `-TargetMB` 余量。

**提示「保留源文件不转换」？**
源文件（常见于 mp4 / webp）本身就比转成 GIF 更小且已达标，转换只会更大。
直接用源文件即可，微信同样能发送。确实要统一成 GIF 就加 `-Force`。

**想直接加到微信表情里？**
自定义表情上限约 5MB，用 `-TargetMB 5`。

## License

[MIT](LICENSE)
