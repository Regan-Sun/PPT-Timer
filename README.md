# PPT 计时器 for macOS

这是 [old9/ppttimer](https://github.com/old9/ppttimer) 的原生 macOS 移植版。Windows 版依赖 AutoHotkey；macOS 版使用 Swift、AppKit 和 SwiftUI 重写，不需要安装 PowerPoint 插件。

## 下载与安装

1. 打开 [GitHub Releases](../../releases/latest)。
2. 下载 `PPTTimer-macOS-universal-v1.0.0.zip` 并解压。
3. 将 `PPTTimer.app` 拖入“应用程序”文件夹。
4. 首次启动时在 Finder 中右键 `PPTTimer.app`，选择“打开”，再确认一次“打开”。

应用要求 macOS 13 或更高版本，同时支持 Apple Silicon 和 Intel Mac。当前 Release 使用临时代码签名，未经过 Apple 公证，因此直接双击可能被 Gatekeeper 拦截；右键“打开”只需执行一次。

## 功能

- 默认在 PowerPoint 或 Mac WPS 进入全屏放映时自动开始，退出放映时自动停止
- 可关闭“仅检测 PowerPoint / WPS”，用于 Keynote、浏览器等其他全屏演示
- 透明置顶的倒计时浮层，可在全屏空间上显示；点击浮层可打开控制菜单
- 提前提醒、结束声音、超时正计时和闪烁提示
- 多显示器显示或移动到下一个显示器
- 计时预设、全局快捷键和原生设置界面
- 配置自动保存在 macOS 用户偏好设置中
- 不需要屏幕录制或辅助功能权限

## 使用

双击应用后不会出现 Dock 图标；计时器和控制入口位于菜单栏下方的右上角。点击计时器浮层可打开开始、停止、重置、设置和退出菜单。

仅打开演示文稿不会开始计时，必须进入幻灯片放映：

- PowerPoint：选择“幻灯片放映 → 从头开始播放”。首次检测时，允许 PPTTimer 控制 Microsoft PowerPoint。
- Mac WPS：进入原生 Mac WPS 的全屏幻灯片放映。
- 窗口化放映或未被识别的演示程序：按 `F12` 手动开始。

退出放映后计时自动停止。计时器浮层会避开菜单栏，并在放映时提升到全屏窗口之上。

## 快捷键

| 操作 | 快捷键 |
|---|---|
| 开始计时 | `F12` |
| 停止计时 | `Control + F12` |
| 暂停/恢复 | `Control + F11` |
| 重置 | `Control + Option + F12` |
| 移至下个显示器 | `Control + Command + M` |
| 在所有显示器显示 | `Control + Command + A` |
| 载入预设 1–6 | `Control + Command + F1–F6` |
| 退出 | `Command + Esc` |

如果 Mac 将功能键设置为亮度、音量等系统控制，需要同时按 `Fn`，或在“系统设置 → 键盘”中启用“将 F1、F2 等键用作标准功能键”。

## 自动检测说明

默认启用“仅检测 PowerPoint / WPS”，只响应 Microsoft PowerPoint 和原生 Mac WPS Office 的幻灯片放映。关闭该选项后，Keynote、浏览器全屏演示等占满显示器的窗口也可以触发计时。

PowerPoint 的窗口化放映不会占满屏幕，无法可靠地与普通编辑窗口区分；这种模式请按 `F12` 手动开始。手动开始后，默认会暂停自动检测，避免窗口状态打断计时。

## 从源码构建

要求 macOS 13 或更高版本，并安装 Xcode Command Line Tools 或 Xcode。

```bash
./scripts/build_app.sh
```

脚本会运行 Release 构建、生成应用图标、复制声音资源、创建临时代码签名，并输出同时支持 Apple Silicon 与 Intel Mac 的通用 `PPTTimer.app`。

运行测试：

```bash
swift test
```

## 项目结构

- `Sources/PPTTimer/`：macOS 原生应用源码
- `Tests/PPTTimerTests/`：计时格式、配置和全屏判定测试
- `scripts/build_app.sh`：通用 `.app` 打包脚本
- `ppttimer_v2.ahk`：原项目的 Windows AutoHotkey 源码
- `beep.mp3`、`applause.mp3`：沿用原项目提示音

## 来源与致谢

- 原始 Windows 项目：[old9/ppttimer](https://github.com/old9/ppttimer)
- 原始 AutoHotkey 源码、提示音和项目思路来自上述项目
- macOS 原生移植、通用二进制构建、测试与发布由 [OpenAI Codex](https://openai.com/codex/) 协助完成
- Fork 中保留原始提交历史，GitHub 会显示与上游项目的来源关系

## License

MIT，见 [LICENSE.txt](LICENSE.txt)。
