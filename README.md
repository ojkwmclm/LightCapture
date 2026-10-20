# 轻截 LightCapture

<p align="center"><img src="Assets/LightCapture.png" width="112" alt="LightCapture"></p>

使用 Swift / AppKit 编写的 Mac 截图、标注与录屏工具，支持中文和英文界面。

[English](README.en.md) · [下载 v0.6.21](https://github.com/ojkwmclm/LightCapture/releases/tag/v0.6.21)

## 功能

- 紧凑置顶捕获栏：剪贴板导入、窗口／矩形区域／全屏截图、录屏、打开图片和编辑器。
- 窗口截图左键单击确认，区域截图左键拖选并松开确认；右键或 Esc 取消。
- 箭头、矩形、椭圆、画笔、高亮、文字、序号与实心遮挡；支持选中、移动、箭头端点调整、图形角点缩放、颜色／粗细、删除及撤销重做。
- PNG／JPEG／PDF 保存、图片复制、裁剪、缩放、置顶贴图和手动纵向拼接。
- Vision 本机中英文文字识别。
- 区域／窗口／全屏 MP4 录屏，可选电脑声音、麦克风、两者同时或无声。
- 有图片时才启用剪贴板导入；编辑器「复制」右侧提供「粘贴」。
- 打开编辑器时隐藏捕获栏，关闭后恢复；录屏时可从 Dock 唤回停止控制。

## 下载与运行

要求 **Apple Silicon（arm64）、macOS 15 或更新版本**，暂未提供或验证 Intel 构建。

从 [Releases](https://github.com/ojkwmclm/LightCapture/releases) 下载 `LightCapture-v0.6.21-macOS-arm64.zip`，解压并将「轻截 LightCapture.app」放入应用程序目录。

当前发行包采用临时签名，尚未经过 Developer ID 签名或 Apple 公证，macOS 可能提示无法验证开发者。截图和录屏需要在「系统设置 → 隐私与安全 → 录屏与系统录音」允许轻截；麦克风录音还需麦克风权限。更新临时签名版本后可能需要重新登记授权。

开始录屏前先选择目标和 MP4 保存路径。开始后捕获栏收起，可从 Dock 唤回并点击停止，或使用菜单栏停止录屏。

## 快捷键

| 操作 | 快捷键 |
| --- | --- |
| 打开图片 | ⌘O |
| 剪贴板图片导入 | ⌥⌘V |
| 区域截图 | ⌥⌘2 |
| 全屏截图（主显示器） | ⌥⌘3 |
| 窗口截图 | ⌥⌘4 |
| 保存图片 | ⌘S |
| 复制标注图片 | ⇧⌘C |
| 撤销／重做 | ⌘Z／⇧⌘Z |

语言可在齿轮菜单或应用菜单中切换，系统文件选择器和权限弹窗跟随 macOS 语言。

## 构建与自检

安装 Xcode Command Line Tools，在仓库目录运行：

```sh
chmod +x build.sh
./build.sh
```

脚本生成「轻截 LightCapture.app」，默认目标 `arm64-apple-macos15.0`。依赖 AppKit、Vision、ScreenCaptureKit、AVFoundation、Carbon 系统框架。

在具有桌面会话的 Mac 上运行自检，生成测试图片与 JSON 报告：

```sh
LIGHTCAPTURE_TEST_OUTPUT=/tmp/lightcapture-selftest.png "./轻截 LightCapture.app/Contents/MacOS/LightCapture" --self-test --test-exit
```

剪贴板自检使用独立命名剪贴板，不写入系统剪贴板。真实鼠标、系统权限和录屏音频需单独验收，见 [验证范围](docs/VALIDATION.md)。

## 当前边界

- 0.x 迭代版本；尚无自动滚动截图，手动拼接保留重叠内容。
- 导出和裁剪会合并标注，尚无可编辑工程保存；裁剪可撤销。
- 窗口截图包含目标范围内可见的遮挡内容，全屏截图当前使用主显示器。
- 尚无录屏暂停、摄像头叠加或视频剪辑。

LightCapture 借鉴 FastStone Capture 的紧凑工作流程，为独立实现的 Mac 工具，与 FastStone 无隶属关系。仓库不包含 FastStone 程序、资源或反编译产物。
