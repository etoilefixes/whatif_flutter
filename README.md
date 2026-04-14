# 叙境 WhatIf — Flutter 客户端

叙境 WhatIf 是一个本地优先的互动叙事桌面项目。本仓库是迁移后的 Flutter 桌面客户端，也是当前的主客户端工程。它承担两类职责：

- Flutter 桌面 UI
- 可选的集成式 Dart 运行时

> 原始仓库：[ypcypc/WhatIf](https://github.com/ypcypc/WhatIf)

---

## 文档导航

| 文档 | 内容 |
|------|------|
| [总体架构说明](docs/ARCHITECTURE.md) | 迁移后的技术结构、两条运行路径的设计 |
| [集成运行时说明](docs/INTEGRATED_RUNTIME.md) | `integrated` 模式下 Dart 本地运行时的内部细节 |
| [迁移项目报告](docs/PROJECT_REPORT.md) | 从 React/Electron 到 Flutter 的完整迁移记录 |
| [贡献指南](docs/CONTRIBUTING.md) | 分支规范、提交格式、PR 流程 |

---

## 项目定位

本子项目是叙境 WhatIf 的桌面客户端核心，已从旧 React/Electron 前端完全迁移至 Flutter。它不再是一个单纯的界面壳，而是包含以下能力：

- 桌面页面与交互
- sidecar 模式下的本地后端管理
- integrated 模式下的 Dart 本地后端
- 本地 APK 构建脚本与项目内 Android 工具链

## 当前完成状态

- Flutter 桌面端 UI 已取代 React/Electron 成为主客户端
- 集成运行时已支持：世界包加载、本地构建、剧情三阶段推进、存档/读档、偏离分析、记忆压缩与召回、桥接规划、场景适配、TTS 旁白、轻量预取
- Android APK 已支持项目内本地导出，不依赖全局 Android SDK 安装

## 桌面运行模式

### 1. 默认模式：sidecar

Flutter 桌面端会自动启动并管理 Python sidecar（需要原仓库 [ypcypc/WhatIf](https://github.com/ypcypc/WhatIf) 的 `backend/`）。

适合想要贴近旧运行时行为、优先保证功能完整性的场景。

### 2. 集成模式：integrated

```powershell
$env:WHATIF_BACKEND_MODE="integrated"
flutter run -d windows
```

这个模式下，游戏主链路通过 Dart 本地服务执行，不再依赖运行时 HTTP sidecar。详见 [集成运行时说明](docs/INTEGRATED_RUNTIME.md)。

## 快速开始

### 1. 安装依赖

```powershell
flutter pub get
```

### 2. 配置模型 Key（如需 LLM 增强）

如果你同时拥有原仓库的 `backend/`，复制后端环境模板并填写 Key：

```powershell
Copy-Item ..\whatif-original\backend\.env.example ..\whatif-original\backend\.env
```

```env
DASHSCOPE_API_KEY=your_key_here
OPENAI_API_KEY=your_key_here
```

### 3. 启动桌面应用

```powershell
# sidecar 模式（默认）
flutter run -d windows

# integrated 模式
$env:WHATIF_BACKEND_MODE="integrated"
flutter run -d windows
```

## 世界包与内容构建

Flutter Library 页面可以：

- 导入现有 `.wpkg`
- 从 `.txt` / `.md` 本地构建世界包

## Android APK 本地导出

```powershell
.\tool\build_apk_local.ps1 -Mode debug    # 调试包
.\tool\build_apk_local.ps1 -Mode release  # 发布包
```

项目内本地工具链目录（已 `.gitignore`）：

- `.android-sdk/`
- `.jdk/`
- `.flutter-maven/`

APK 输出：`build/app/outputs/flutter-apk/`

## 常用开发命令

```powershell
flutter pub get       # 安装依赖
flutter run -d windows  # 桌面运行
flutter analyze       # 静态分析
flutter test          # 运行测试
```

## 目录结构

```text
lib/src/pages/        页面层
lib/src/services/     运行时服务与本地后端实现
lib/src/l10n/         国际化字符串
lib/src/              控制器、模型等
test/                 Flutter 与运行时测试
tool/                 本地 Android 工具链脚本
windows/              Windows Runner
android/              Android Runner
web/                  Web Runner
assets/fonts/         字体资源
docs/                 中文文档、技术说明、项目报告
```

## 开源协议

[MIT License](LICENSE)

## 注意事项

- 不要在这里重新引入 React 或 Electron 思路
- integrated 模式的能力扩展优先继续落在 `lib/src/services/`
- 与启动、打包、后端模式相关的改动，请同步更新 `README.md` 和 `docs/`
