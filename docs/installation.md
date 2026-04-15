# 安装指南

## 基础依赖

建议准备：

- Flutter 3.41.x
- Dart 3.11.x
- Git

检查命令：

```powershell
flutter --version
dart --version
git --version
```

## 项目依赖安装

```powershell
flutter pub get
```

## Windows

```powershell
flutter doctor -v
flutter run -d windows
```

## Web

```powershell
flutter run -d chrome
```

## Android

Android 打包时推荐使用 JDK 17。

```powershell
$env:JAVA_HOME='D:\path\to\jdk17'
$env:Path = 'D:\path\to\jdk17\bin;' + $env:Path
flutter build apk --release
```

## macOS

当前仓库未自带 `macos/` Runner。请在 Mac 上执行：

```bash
flutter create . --platforms=macos
flutter pub get
flutter run -d macos
```
