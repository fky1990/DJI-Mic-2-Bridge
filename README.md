# DJI Mic 2 Bridge for macOS

[English](#english) | [中文](#中文)

## 中文

一个轻量级 macOS 菜单栏工具，让单独的 DJI Mic 2 发射器通过蓝牙成为 Mac
的系统麦克风。它使用 macOS 公开的 `IOBluetooth` HFP Audio Gateway API 建立
SCO 音频链路，不修改设备固件，也不安装内核或虚拟音频驱动。

> 本项目是独立的社区项目，与 DJI 无隶属、授权或背书关系。DJI 和 DJI Mic
> 是其各自权利人的商标。

### 功能

- 自动发现已配对并处于蓝灯模式的 DJI Mic 2 发射器。
- 将发射器注册为 Core Audio 输入设备。
- 可一键设为 macOS 默认输入。
- 连接时保留当前默认扬声器，防止输出被切到没有扬声器的 DJI 发射器。
- 菜单栏使用“麦克风 + D”图标，与系统麦克风图标区分。
- 菜单栏显示发射器电量及预计剩余使用时间。
- 低延迟保活：持续保持音频输入流，避免 SCO 休眠造成开口后数秒才有声音。
- 不录音、不保存音频、不联网，也不收集遥测数据。

### 系统要求

- macOS 13 或更高版本。
- Apple Silicon 或 Intel Mac。
- DJI Mic 2 发射器（已在 `DJI-MIC2-*` 型号上验证）。

### 安装与使用

1. 从 [Releases](https://github.com/fky1990/DJI-Mic-2-Bridge/releases) 下载最新版。
2. 将 DJI Mic 2 发射器切换到蓝牙模式（蓝灯）。
3. 在“系统设置 → 蓝牙”中完成配对。
4. 打开 App，首次启动低延迟模式时允许麦克风权限。
5. 点击菜单栏的“麦克风 + D”图标，需要时选择“设为系统默认输入”。

未经过 Apple 公证的社区构建可能被 Gatekeeper 拦截。请在 Finder 中右键 App，
选择“打开”，并确认运行；或者自行从源码构建。

### 音质、延迟与续航

蓝牙直连使用 HFP/SCO 语音链路，当前实测为 **16 kHz、单声道**。它适合会议、
语音识别和直播，但不等同于 DJI 接收器经 USB-C 输出的全带宽音质。

低延迟模式会持续打开输入流，因此发射器会更接近连续传输状态，耗电高于待机。
MacBook 端的额外功耗很低。退出 App 或选择“断开音频链路”会停止保活。

预计剩余时间初始按约 6 小时满电续航计算，之后会根据本机实际掉电速度在本地
逐步校准。估算数据只保存在 macOS 用户偏好中，不会上传。

电量来自 macOS 已读取的蓝牙设备电池字段。由于 Apple 没有把该读取接口列入
公开 SDK，未来 macOS 若移除该字段，App 会安全降级为“暂时无法读取”，不影响收音。

如果音频已经能立即进入 Mac，但文字仍固定延迟数秒，延迟通常来自识别软件自身
的语音分段或静音判断。

### 从源码构建

需要 Xcode Command Line Tools：

```sh
git clone https://github.com/fky1990/DJI-Mic-2-Bridge.git
cd DJI-Mic-2-Bridge
./build.sh
open "build/DJI Mic 2 Bridge.app"
```

构建脚本生成 Apple Silicon/Intel 通用 App，并进行 ad-hoc 签名。

### 隐私

低延迟模式需要麦克风权限，仅用于启动并丢弃 Core Audio 输入缓冲区，以保持蓝牙
链路活跃。程序没有录音文件写入、网络请求或分析 SDK。源码集中在
[`AppDelegate.m`](AppDelegate.m)，可直接审计。

### 参与贡献

欢迎提交 Issue 和 Pull Request。请在报告兼容性问题时提供 macOS 版本、Mac
型号、DJI Mic 2 固件版本，以及菜单栏显示的错误信息；不要公开设备序列号。

## English

DJI Mic 2 Bridge is a small macOS menu bar utility that exposes a standalone
DJI Mic 2 transmitter as a system microphone over Bluetooth. It uses Apple's
public `IOBluetooth` HFP Audio Gateway API to establish an SCO audio link. It
does not modify firmware or install a kernel/virtual-audio driver.

> This is an independent community project. It is not affiliated with,
> authorized by, or endorsed by DJI. Product names are trademarks of their
> respective owners.

### Features

- Finds a paired DJI Mic 2 transmitter in Bluetooth mode.
- Exposes it as a Core Audio input and can make it the default input.
- Preserves the current default speaker when macOS creates the DJI output endpoint.
- Distinct “microphone + D” menu bar icon.
- Transmitter battery percentage and estimated remaining runtime.
- Low-latency keep-alive prevents the SCO link from sleeping between utterances.
- No recording, saved audio, network access, analytics, or telemetry.

### Requirements and usage

macOS 13+, on Apple Silicon or Intel. Pair the transmitter in System Settings,
launch the app, grant microphone permission for low-latency mode, then use the
menu bar icon to connect or select it as the default input.

Direct Bluetooth audio uses the HFP/SCO voice path and has been observed as
**16 kHz mono**. Continuous keep-alive reduces wake latency but consumes more
transmitter battery than idle Bluetooth. Quit or disconnect to stop it.

Build locally with `./build.sh`. Contributions are welcome through Issues and
Pull Requests.

## License

[MIT](LICENSE)
