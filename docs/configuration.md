# 配置说明

## 运行模式

### 默认模式

```powershell
flutter run -d windows
```

### 集成模式

```powershell
$env:WHATIF_BACKEND_MODE="integrated"
flutter run -d windows
```

## Android SDK 与 Flutter SDK

`android/local.properties` 通常应包含：

```properties
sdk.dir=D:\\path\\to\\android_sdk
flutter.sdk=D:\\path\\to\\flutter
```

## Java 环境

Android 构建建议使用 JDK 17：

```powershell
$env:JAVA_HOME='D:\path\to\jdk17'
$env:Path = 'D:\path\to\jdk17\bin;' + $env:Path
```

## 本地运行时数据

以下内容通常不应提交到 Git：

- `*.log`
- `output/*`
- `logs/**/*.jsonl`
- `saves/*`
- `build/`

## 更多参考

- [环境配置与打包教程](./SETUP_AND_BUILD_GUIDE.md)
- [`.wpkg` 生成、持久化与平板优化说明](./WPKG_GENERATION_AND_PERSISTENCE.md)
