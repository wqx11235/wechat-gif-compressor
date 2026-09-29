# 微信动图 / 视频压缩工具 · WeChat GIF & Video Compressor

把体积过大的**动图**和**视频**一键压到能直接在微信聊天里发送的大小——
动图默认 ≤ **9.5 MB**，视频默认 ≤ **20 MB**（**原格式进、原格式出**）。
Windows 下**把文件拖到 `.cmd` 上**即可，**压缩包内已自带 ffmpeg，解压即用**。

典型效果：

```
动图  13.48 MB, 500x500, 33fps  ──►  5.79 MB, 400x400, 25fps     (0.6 秒)
视频  195.41 MB, 1920x1080      ──►  19.05 MB, 1280x720          (7.4 秒，默认 20MB 目标)
视频  15.44 MB, 1280x720        ──►  2.82 MB, 1280x720           (-VideoMB 3)
```

---

## 下载即用（推荐）

1. 打开 [**Releases**](https://github.com/wqx11235/wechat-gif-compressor/releases) 页面
2. 下载 `wechat-gif-compressor-*-win64.zip`（约 35 MB，**已内置 ffmpeg.exe**）
3. 解压到任意文件夹（建议路径不要有中文以外的怪符号，放桌面即可）
4. 把要压的动图/视频**拖到 `压缩微信表情包.cmd` 上** —— 完事

> 压缩包里的 `bin\ffmpeg.exe` 就是引擎，不需要另外安装 ffmpeg、也不需要装 Python 或任何运行库。
> 系统自带 Windows PowerShell 即可运行。

## 为什么需要它

**动图**：微信聊天发送图片的上限约 **10 MB**，而很多从网页/视频转出来的动图动辄 15~30 MB，
直接发会提示「图片过大」。常规的「调色板优化」对这类动图几乎无效——
它们每帧都是全帧且带大量噪点，GIF 的 LZW 压缩压不动（约 0.7 字节/像素）。
本工具的做法是**先去噪再编码**：噪点一去掉，相邻像素相关性变强、帧间差异变小，
LZW 和帧间差分才真正开始工作，体积随之断崖式下降。

**视频**：微信聊天发送视频的上限约 **25 MB**，手机随手拍的视频常常几百 MB。
本工具按目标体积**反算码率**重编码，一次压到目标以内，并保留音轨、保持原容器格式。

## 特性

- **一键拖拽**：把文件或整个文件夹拖到 `压缩微信表情包.cmd` 上即可，支持批量、动图与视频混放。
- **自带引擎**：Release 包内含 `ffmpeg.exe`，没有系统 ffmpeg 也能跑。
- **动图**：长边 400px / 25fps / 256 色 / 去噪 / 帧间矩形差分，画质与体积平衡最佳。
- **视频**：原格式进原格式出（mp4→mp4、mov→mov、webm→webm…），也可用 `-VideoFormat mp4` 强制转换；
  音轨保留（aac / opus / mp3 按容器自动选），mp4/mov 自动加 `+faststart` 便于边下边播。
- **自动降级**：动图 8 档（加强去噪 → 降帧率 → 微缩尺寸 → 减色）；视频 5 档
  （按上一档实测体积反推下一档码率，必要时降到 960 / 854 / 640 长边）直到达标。
- **体积回退保护**：若转换后反而更大、且源文件本身已达标，则保留源文件不转换（需 `-Force` 才强制）。
- **不动原文件**：结果写到源文件旁边的 `微信版\` 子目录。
- **兼容 Windows PowerShell 5.1**（系统自带，无需安装 PowerShell 7）。

## 命令行用法（可选）

```bat
powershell -ExecutionPolicy Bypass -File wechat-gif-compress.ps1 <文件或文件夹...> [参数]
```

| 参数 | 默认 | 说明 |
| --- | --- | --- |
| `-TargetMB` | `9.5` | **动图**目标体积上限（MB）。微信聊天图片上限约 10 MB |
| `-Size` | `400` | 动图长边像素上限，**只缩不放**（源图更小则保持原尺寸） |
| `-Fps` | `25` | 动图帧率上限 |
| `-VideoMB` | `20` | **视频**目标体积上限（MB）。微信聊天视频上限约 25 MB |
| `-VideoSize` | `1280` | 视频长边像素上限，**只缩不放** |
| `-VideoFormat` | 跟随源格式 | 强制视频输出容器，如 `-VideoFormat mp4`（mov/webm/mkv 都能转 mp4） |
| `-ToGif` | 关 | 视频也按动图流程转成 GIF（旧版行为），此时用 `-TargetMB` 判定 |
| `-OutDir` | `微信版` | 输出子目录名 |
| `-Force` | 关 | 默认当「转换后反而更大且源文件已达标」时保留源文件；加此项强制转换 |

示例：

```bat
:: 动图压到 5MB 以内，用于微信「添加表情」（自定义表情上限约 5MB）
powershell -ExecutionPolicy Bypass -File wechat-gif-compress.ps1 表情.gif -TargetMB 5

:: 视频压到 10MB 以内（微信发视频更稳）
powershell -ExecutionPolicy Bypass -File wechat-gif-compress.ps1 录像.mov -VideoMB 10

:: 统一转成 mp4，长边不超过 960
powershell -ExecutionPolicy Bypass -File wechat-gif-compress.ps1 素材 -VideoFormat mp4 -VideoSize 960

:: 把视频转成动图表情
powershell -ExecutionPolicy Bypass -File wechat-gif-compress.ps1 片段.mp4 -ToGif -TargetMB 5

:: 批量处理整个文件夹（动图 + 视频混放）
powershell -ExecutionPolicy Bypass -File wechat-gif-compress.ps1 D:\待处理
```

详细图文说明见 [使用说明.md](使用说明.md)。

## 压缩原理

### 动图

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
[s1][p]paletteuse=dither=none:diff_mode=rectangle
```

### 视频

| 步骤 | 作用 |
| --- | --- |
| 目标码率反算 | `目标体积 × 8 ÷ 时长`，再留 5% 容器开销；有音轨再扣掉 96 kbps 音频预算 |
| 一次到位 | 实测大视频（195 MB / 90 秒）一次编码就落在目标内，不用反复试 |
| 画质优先的编码参数 | x264 `-preset medium -profile:v high -pix_fmt yuv420p` + 码率模式 `-b:v N -maxrate 1.5N -bufsize 2N` |
| 音轨保留 | mp4/mov/mkv → `aac 96k`；webm → `libopus 96k`；avi → `libmp3lame 96k` |
| 边下边播 | mp4/m4v/mov 自动加 `-movflags +faststart` |
| 自适应降级 | 万一超了，按**上一档实测体积**反推下一档码率（而非固定硬砍），最多 5 档，必要时把长边降到 960 / 854 / 640 |
| 时长读不到时 | 退化为 CRF 模式（x264 `26+2×档位`，VP9 `32+2×档位`） |

webm 用 VP9（`libvpx-vp9`，较慢但同体积画质更好），其余用 x264。

## 引擎查找顺序

**只需要 `ffmpeg.exe` 一个文件（不需要 ffprobe）**。脚本按以下顺序查找：

1. **本脚本同目录的 `bin\`**（发行包的位置，`bin\ffmpeg.exe`）
2. 本脚本同目录（`ffmpeg.exe` 直接放旁边）
3. 系统 `PATH`
4. 常见安装位置：`D:\ffmpeg\*`、`C:\ffmpeg\*`、`%ProgramFiles%\ffmpeg`、
   `%LOCALAPPDATA%\ffmpeg`、`%USERPROFILE%\ffmpeg`、scoop / chocolatey 目录

## 支持格式

| 输入 | 输出 |
| --- | --- |
| 动图 `.gif` / `.png` / `.apng` / `.webp`（静态） | GIF |
| 视频 `.mp4` / `.m4v` / `.mov` / `.webm` / `.mkv` / `.avi` | **同格式**（或 `-VideoFormat` 指定；加 `-ToGif` 则转 GIF） |

- ⚠️ **动画 WebP**：ffmpeg 官方构建目前无法解码动画 WebP（解复用器只认静态图），
  遇到这类文件工具会明确提示并跳过；请先用浏览器/在线工具另存为 GIF 或 MP4 再压缩。

## 常见问题

**动图输出还是超过 10MB？**
源动图可能很长或噪点极重。用 `-TargetMB 5` 强制更狠的档位，或先剪短时长，
也可以降低 `-Size`（如 320）和 `-Fps`（如 15）。

**画面变糊了？**
去噪 + 缩图/压码率必然损失细节。动图更看重画质就用 `-Size 500`，视频用 `-VideoMB 30`
并给足余量，程序会尽量少降级。

**视频压完没声音了？**
不会。只要源视频有音轨就会保留（96 kbps）；源视频本身没有音轨，输出也没有。

**我的视频只有 15 MB，为什么没被压缩？**
它已经比你设定的 20 MB 目标小了，工具不会做无意义的重新编码（重编码只会掉画质）。
想再小一点就用 `-VideoMB 10`；确实要强制重编码可加 `-Force`。

**提示「保留源文件不转换」？**
源文件本身就比重新编码后更小且已达标，转换只会更大。
直接用源文件即可，微信同样能发送。确实要转换就加 `-Force`。

**想直接加到微信表情里？**
自定义表情上限约 5MB，用 `-TargetMB 5`。

**webm 压得有点慢？**
VP9 编码本身就比 x264 慢。不介意换格式的话加 `-VideoFormat mp4` 会快很多。

## 仓库结构

```
wechat-gif-compress.ps1   主脚本（唯一逻辑，纯 PowerShell 5.1）
压缩微信表情包.cmd          拖拽入口（纯 ASCII，避免编码问题）
使用说明.md                详细说明（随发行包一起分发）
build-release.ps1         一键打包：生成带 ffmpeg 的发行 zip
```

## License

脚本本体：[MIT](LICENSE)

发行包内附带的 `bin/ffmpeg.exe` 来自 [FFmpeg](https://ffmpeg.org/)，
为 GPLv3 授权的第三方程序（构建来源 [gyan.dev](https://www.gyan.dev/ffmpeg/builds/)），
其许可与源码获取方式见发行包内 `第三方组件说明.txt`。
