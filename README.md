# WhatIf Flutter Client

WhatIf Flutter Client 是一个本地优先的互动叙事客户端，当前仓库同时包含：

- Flutter 客户端界面
- 本地集成运行时
- Windows 桌面运行入口
- Android APK 打包入口

## 文档导航

- [环境配置与打包教程](./docs/SETUP_AND_BUILD_GUIDE.md)
- [`.wpkg` 生成、持久化与平板优化说明](./docs/WPKG_GENERATION_AND_PERSISTENCE.md)
- [项目架构说明](./docs/ARCHITECTURE.md)
- [集成运行时说明](./docs/INTEGRATED_RUNTIME.md)
- [贡献指南](./docs/CONTRIBUTING.md)

## 快速开始

### 1. 安装依赖

```powershell
flutter pub get
```

### 2. Windows 桌面运行

```powershell
flutter run -d windows
```

### 3. 启用本地集成模式

```powershell
$env:WHATIF_BACKEND_MODE="integrated"
flutter run -d windows
```

### 4. 打包 Android APK

```powershell
flutter build apk --release
```

产物默认位于：

```text
build/app/outputs/flutter-apk/app-release.apk
```

## 当前平台状态

- Windows：已启用，可直接运行
- Web：已启用，可直接运行
- Android：已启用，可直接打包 APK
- macOS：当前仓库未初始化 `macos/` Runner，如需构建请先参考教程中的 macOS 章节

## 常用命令

```powershell
flutter pub get
flutter analyze
flutter test
flutter run -d windows
flutter build apk --release
```
