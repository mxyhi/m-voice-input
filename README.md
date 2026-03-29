# MVoiceInput

`MVoiceInput` 是一个基于 Swift Package Manager 构建的 macOS 菜单栏语音输入应用。它支持按住 `Fn` 录音、实时语音转文字、可选 LLM 保守纠错，以及将文本稳定注入到当前聚焦输入框，适合在聊天、文档、浏览器和 IDE 中快速输入中文或多语言内容。

## 项目定位

如果你想找的是这类工具，这个仓库就是：

- macOS 语音输入工具
- 菜单栏语音转文字应用
- 按住 `Fn` 说话、松开即输入
- 支持中文、英文、日语、韩语的语音输入
- 支持 OpenAI-compatible API 的语音识别纠错
- 不依赖 Xcode 工程，直接用 SwiftPM 构建 `.app`

## 核心特性

- 菜单栏常驻：`LSUIElement` 运行，无 Dock 图标，适合常驻后台。
- `Fn` 按住说话：按下开始录音，松开结束转写，尽量减少打断感。
- 实时转写反馈：录音时显示底部胶囊悬浮窗，动态展示实时文本和波形。
- 多语言支持：内置英语、简体中文、繁体中文、日语、韩语。
- 可选 LLM 保守纠错：只修复明显识别错误，不做润色、扩写或改写。
- 稳定文本注入：通过剪贴板加 `Cmd+V` 注入文本，并尽量恢复原剪贴板与输入法状态。
- 权限中心：集中展示麦克风、语音识别、辅助功能、输入监控、事件注入等权限状态。
- SwiftPM 构建：可直接 `make build`、`make install` 生成并安装 `.app`。

## 适用场景

- 在 macOS 上做中文语音输入
- 用语音快速回复 IM、邮件、文档或工单
- 需要菜单栏常驻、轻量、低打扰的语音输入方案
- 希望在本地实时转写基础上，再接一个保守型 LLM 纠错层
- 想参考一个基于 AppKit + SwiftPM 的 macOS 菜单栏应用实现

## 系统要求

- macOS 14+
- Apple Command Line Tools 或完整 Xcode
- 麦克风权限
- 语音识别权限
- 辅助功能权限
- 输入监控权限
- 事件注入权限

## 快速开始

### 1. 构建

```bash
make build
```

构建完成后，产物位于：

```bash
dist/MVoiceInput.app
```

### 2. 安装

```bash
make install
```

默认会安装到：

```bash
~/Applications/MVoiceInput.app
```

### 3. 运行

```bash
open ~/Applications/MVoiceInput.app
```

首次启动后，如果权限未完整授予，应用会自动弹出权限中心引导配置。

## 使用方式

1. 启动应用并授予必要权限。
2. 在菜单栏中确认当前识别语言。
3. 把输入焦点切到目标应用的文本框。
4. 按住 `Fn` 开始录音。
5. 说话时会看到底部悬浮窗显示实时转写和波形。
6. 松开 `Fn` 后应用会结束识别，并把最终文本注入到当前输入位置。

## LLM 保守纠错

项目支持可选的 OpenAI-compatible `/chat/completions` 接口，用于在本地转写结果基础上做非常保守的纠错。

特点：

- 只修复明显语音识别错误
- 不做润色、不重写、不总结
- 输入基本正确时原样返回
- 兼容常见 OpenAI-compatible 服务

可在设置窗口中配置：

- `API Base URL`
- `API Key`
- `Model`
- `Test`
- `Save`

## 常用命令

```bash
make test
make build
make run
make install
make clean
make reset-permissions
```

说明：

- `make test`：运行核心逻辑自定义测试器
- `make build`：构建并组装 `.app`
- `make run`：构建后直接启动应用
- `make install`：安装到 `~/Applications`
- `make reset-permissions`：重置该应用的系统 TCC 权限记录

## 项目结构

```text
Sources/
  VoiceInputCore/                纯逻辑模块：语言、设置、波形、LLM 协议
  VoiceInputCoreTestRunner/      自定义测试执行器
  VoiceInputMenuBar/
    App/                         应用协调、权限协调、主菜单
    MenuBar/                     菜单栏状态项
    Overlay/                     悬浮窗与波形视图
    Permissions/                 权限中心窗口与视图
    Services/                    Fn 监听、语音识别、文本注入、LLM refine
    Settings/                    设置窗口与表单
Support/
  Info.plist                     App bundle 元信息
Makefile                         构建、安装、测试脚本
```

## 技术实现摘要

- `AppKit`：菜单栏应用、窗口与系统集成
- `SwiftUI`：设置页与权限中心界面
- `AVAudioEngine`：录音输入
- `Speech`：实时语音识别
- `CoreGraphics Event Tap`：全局 `Fn` 监听与拦截
- `Carbon TIS`：输入法切换与恢复
- `Swift Package Manager`：工程组织与构建

## 权限说明

为了实现“按住说话并把文本注入当前输入框”，应用需要多个系统权限协同工作：

- 麦克风：采集语音
- 语音识别：实时转文字
- 输入监控：更稳定地监听全局 `Fn`
- 辅助功能：允许跨应用交互
- 事件注入：发送 `Cmd+V` 完成文本注入

如果任何一项权限缺失，应用会在启动或录音前引导你补齐。

## 已知限制

- 当前只支持 macOS 14 及以上版本。
- 该仓库主要面向 Apple Silicon 本机构建流程，构建产物路径默认使用 SwiftPM 当前输出布局。
- 文本注入依赖系统权限和前台应用状态，受目标应用安全策略影响。
- `Fn` 监听在不同硬件、输入法和系统设置组合下，系统行为可能存在差异，项目已做多层兜底但无法承诺所有环境完全一致。

## SEO 关键词

为了方便 GitHub、搜索引擎和站内检索，这个项目重点覆盖以下关键词：

- macOS 语音输入
- macOS 语音转文字
- macOS 菜单栏应用
- Fn 语音输入
- Swift 菜单栏应用
- SwiftPM macOS app
- OpenAI-compatible speech refinement
- 中文语音输入工具

## 许可证

当前仓库未附带单独 LICENSE 文件。如需开源分发，建议补充明确许可证。
