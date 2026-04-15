# WhatIf Flutter Client

![Version](https://img.shields.io/badge/version-1.0.1%2B2-2f6feb)
![Flutter](https://img.shields.io/badge/Flutter-3.41.x-02569B?logo=flutter)
![License](https://img.shields.io/github/license/etoilefixes/whatif_flutter)

WhatIf Flutter Client 是一个本地优先的互动叙事客户端，面向 Windows 桌面、Web 和 Android APK 场景。项目把 Flutter 界面、本地集成运行时、`.wpkg` 内容包、`sqflite` 持久化和多模型配置能力整合在一个仓库中，适合继续演进成可交付的本地应用。

本项目的世界观、玩法思路和部分运行时演进路线，来源于原始项目 [ypcypc/WhatIf](https://github.com/ypcypc/WhatIf.git)。当前仓库是在此基础上的 Flutter 客户端与本地运行时延展版本。

## 功能特性

- ✨ 支持 `.wpkg` 世界包导入、扫描、封面展示和从文本生成内容包
- 🚀 支持本地集成运行时、Windows 桌面运行、Web 调试和 Android APK 打包
- 🔧 支持模型提供商管理、SQLite 持久化、存档迁移和大屏平板体验优化

## 演示

当前仓库未附带演示 GIF。推荐优先通过以下方式体验：

- Windows：`flutter run -d windows`
- Web：`flutter run -d chrome`
- Android：`flutter build apk --release`

APK 构建产物默认位于：

```text
build/app/outputs/flutter-apk/app-release.apk
```

## 快速开始

### 环境要求

- Flutter 3.41.x 或兼容版本
- Dart 3.11.x 或兼容版本
- Git
- Android 打包时建议使用 JDK 17

### 安装

```bash
git clone https://github.com/etoilefixes/whatif_flutter.git
cd whatif_flutter
flutter pub get
```

### 运行

Windows 桌面：

```powershell
flutter run -d windows
```

Web：

```powershell
flutter run -d chrome
```

本地集成模式：

```powershell
$env:WHATIF_BACKEND_MODE="integrated"
flutter run -d windows
```

## 使用示例

### 1. 启动本地集成模式

```powershell
$env:WHATIF_BACKEND_MODE="integrated"
flutter run -d windows
```

### 2. 构建 Android Release APK

```powershell
$env:JAVA_HOME='D:\path\to\jdk17'
$env:Path = 'D:\path\to\jdk17\bin;' + $env:Path
flutter build apk --release
```

### 3. 运行基础检查

```powershell
flutter analyze
flutter test
```

## 配置

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `WHATIF_BACKEND_MODE` | `string` | 空 | 设为 `integrated` 时强制使用本地 Dart 集成运行时 |
| `JAVA_HOME` | `string` | 系统默认 | Android 构建时建议显式指向 JDK 17 |
| `android/local.properties -> sdk.dir` | `string` | 无 | Android SDK 路径 |
| `android/local.properties -> flutter.sdk` | `string` | 无 | Flutter SDK 路径 |

## 项目结构

```text
├── android/
├── assets/
│   └── fonts/
├── docs/
├── lib/
│   └── src/
│       ├── l10n/
│       ├── pages/
│       ├── services/
│       ├── theme/
│       └── widgets/
├── test/
├── tool/
├── web/
├── windows/
├── pubspec.yaml
└── README.md
```

## API 文档

项目不是一个 npm 包，而是一个 Flutter 应用工程，所以这里的“API”主要是内部运行时能力入口。

### `createBackendApi({required ConfigStore store})`

- 位置：`lib/src/services/backend_api_io.dart`
- 作用：根据当前平台和模式选择实际后端实现

### `LocalBackendApi.create(...)`

- 位置：`lib/src/services/local_backend_api.dart`
- 作用：创建本地集成后端，负责世界包、存档、语音、游戏推进等能力

### `ConfigStore.open(...)`

- 位置：`lib/src/services/config_store.dart`
- 作用：初始化配置与持久化后端，支持迁移旧配置到 SQLite

更完整说明见 [API 文档](./docs/api.md)。

## 常见问题

<details>
<summary>Android 构建时报 <code>What went wrong: 26</code> 怎么办？</summary>

这通常是因为构建时使用了 JDK 26。当前项目的 Android 构建应切到 JDK 17，再重新执行 `flutter build apk --release`。
</details>

<details>
<summary>为什么仓库里没有 <code>macos/</code> 目录？</summary>

当前仓库还没有初始化 macOS Runner。如果你需要在 Mac 上构建桌面版，请先执行 `flutter create . --platforms=macos`，再运行 `flutter build macos --release`。
</details>

## 文档

- [快速开始](./docs/getting-started.md)
- [安装指南](./docs/installation.md)
- [配置说明](./docs/configuration.md)
- [API 文档](./docs/api.md)
- [常见问题](./docs/faq.md)
- [贡献指南](./docs/CONTRIBUTING.md)
- [更新日志](./CHANGELOG.md)
- [环境配置与打包教程](./docs/SETUP_AND_BUILD_GUIDE.md)
- [`.wpkg` 生成、持久化与平板优化说明](./docs/WPKG_GENERATION_AND_PERSISTENCE.md)
- [项目架构说明](./docs/ARCHITECTURE.md)
- [集成运行时说明](./docs/INTEGRATED_RUNTIME.md)

## 贡献指南

1. Fork 本仓库
2. 创建分支：`git checkout -b feature/xxx`
3. 提交更改：`git commit -m "Add xxx"`
4. 推送分支：`git push origin feature/xxx`
5. 提交 Pull Request

详细说明见 [贡献指南](./docs/CONTRIBUTING.md)。

## 更新日志

### v1.0.1

- 增加模型提供商管理 UI 和 Web 后端支持
- 增加 `sqflite` 持久化、包索引缓存和存档迁移
- 增加 Windows / Android / macOS 环境配置与打包教程

完整记录见 [CHANGELOG.md](./CHANGELOG.md)。

## 致谢

- [Flutter](https://github.com/flutter/flutter)
- [sqflite](https://github.com/tekartik/sqflite)
- [ypcypc/WhatIf](https://github.com/ypcypc/WhatIf.git)

特别感谢原始项目 `ypcypc/WhatIf` 提供的叙事设定、后端能力和演进参考。当前仓库的 Flutter 化、桌面化、APK 化和本地持久化工作，都是在这个基础上继续推进的。

## 许可证

[MIT](./LICENSE)

## 联系方式

- 作者：etoilefixes
- Email：etoilefixes@outlook.com
- GitHub：[@etoilefixes](https://github.com/etoilefixes)
