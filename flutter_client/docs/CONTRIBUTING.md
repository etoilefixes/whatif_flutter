# 贡献指南

感谢你参与叙境 WhatIf。

当前项目的主方向已经不是旧 React/Electron 桌面项目，而是迁移后的新结构：

- Flutter 桌面客户端与集成式 Dart 运行时
- Python sidecar（可选）与旧提取/运行时能力（来自原仓库 [ypcypc/WhatIf](https://github.com/ypcypc/WhatIf)）

## 一、开发前提

建议的本地环境：

- Windows 10 或 Windows 11
- Flutter SDK，且已启用 Windows desktop
- Python 3.10+（如果你需要 sidecar 模式）
- 至少一个可用的 LLM API Key（如果你要验证模型增强能力）

## 二、初始化环境

```powershell
git clone https://github.com/etoilefixes/whatif_flutter.git
cd whatif_flutter

flutter pub get
```

如果你需要启用 sidecar 模式，还需要原仓库的 `backend/`：

```powershell
git clone https://github.com/ypcypc/WhatIf.git whatif-original
cd whatif-original
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r backend/requirements.txt
python -m spacy download zh_core_web_sm
```

如果你需要启用提供商 Key：

```powershell
Copy-Item backend\.env.example backend\.env
```

## 三、本地开发方式

### 1. 推荐：集成式 Dart 后端模式

```powershell
cd whatif_flutter
$env:WHATIF_BACKEND_MODE="integrated"
flutter run -d windows
```

### 2. 默认：sidecar 模式

需要同时启动 Python sidecar 和 Flutter 桌面端。

### 3. 仅启动 Python sidecar

```powershell
cd whatif-original/backend
uvicorn api.app:app --reload --port 8000
```

## 四、改动范围约定

### Flutter / Dart 改动

优先放在：

- `lib/src/pages/`
- `lib/src/services/`
- `lib/src/l10n/`

原则：

- 优先复用现有服务而不是另起一套平行实现
- 集成运行时逻辑尽量继续收敛在 `services/` 下
- 同时考虑 sidecar 模式和 integrated 模式是否会受影响

## 五、提交前最小验证

至少运行：

```powershell
flutter analyze
flutter test
```

如果你修改了集成运行时，建议至少补一轮手动流程验证：

- 从 `.txt` / `.md` 构建世界包
- 进入游戏并推进多个阶段
- 执行动作并观察 Delta / 场景变化
- 执行一次存档与读档

如果你修改了 Android 本地导出链路，额外验证：

```powershell
.\tool\build_apk_local.ps1 -Mode debug
```

## 六、文档同步要求

出现以下情况时，请同步更新文档：

- 启动方式发生变化
- 目录职责发生变化
- packaging / APK 导出方式发生变化
- 集成运行时能力边界发生变化
- 开发者工作流发生变化

主要需要关注的文档：

- `README.md`
- `docs/ARCHITECTURE.md`
- `docs/INTEGRATED_RUNTIME.md`
- `docs/PROJECT_REPORT.md`
- `docs/CONTRIBUTING.md`

## 七、Commit 与 PR 建议

推荐使用 Conventional Commits：

- `feat: add integrated runtime tts playback`
- `fix: restore local game engine prefetch state`
- `docs: rewrite project architecture guide in chinese`

一个好的 PR 建议包含：

- 为什么要改
- 改了哪些部分
- 是否影响 sidecar 模式 / integrated 模式
- 跑了哪些验证命令
- 如果有 UI 变化，附截图

## 八、不要提交的内容

不要提交：

- `.env`
- API Key 或其他密钥
- 生成的 `output/*.wpkg`
- `saves/`
- `logs/sessions/*.jsonl`
- 本地 Android SDK / JDK / Maven 镜像目录

## 九、调试入口

常用调试位置：

- Flutter 运行时入口：
  - `lib/src/services/local_backend_api.dart`
  - `lib/src/services/local_game_engine.dart`
- Android 本地构建脚本：
  - `tool/prepare_local_android.ps1`
  - `tool/build_apk_local.ps1`

---

> 原始仓库：[ypcypc/WhatIf](https://github.com/ypcypc/WhatIf)
