# 叙境 WhatIf 总体架构说明

## 文档目标

这份文档用于说明迁移后的项目技术结构。它关注的是"当前上传到 GitHub 的新项目形态"，也就是 Flutter 桌面端为主、Python sidecar 为兼容路径、Dart 集成运行时持续扩展的架构。

如果你只想知道怎么运行项目，请先看根目录 [README](../README.md)。如果你要理解集成运行时的内部细节，请继续看 [INTEGRATED_RUNTIME](./INTEGRATED_RUNTIME.md)。

## 一、总体设计目标

迁移后的架构围绕四个目标展开：

1. 桌面端主界面统一收敛到 Flutter
2. 运行方式保持本地优先，而不是依赖远程服务
3. 允许旧 Python 运行时继续作为兼容路径存在
4. 为后续"后端进一步迁移到 Dart"保留清晰演进空间

## 二、双运行时架构

### 1. Sidecar 模式

这是当前最稳妥的默认桌面模式。

```text
Flutter UI
  -> AppController
  -> BackendRuntime
  -> Python sidecar
  -> FastAPI / SSE
  -> Python runtime agents
```

职责边界：

- Flutter 负责界面、配置、桌面启动入口、音频与交互
- Python sidecar 负责旧运行时、旧 agent 编排、HTTP / SSE 输出
- 两者通过本地端口通信

优点：

- 与旧系统保持高度兼容
- 回归风险更小
- 更适合保守发布

### 2. 集成式 Dart 模式

这是重构迁移后的关键成果之一。

```text
Flutter UI
  -> AppController
  -> LocalBackendApi
  -> LocalGameEngine
  -> Local services
```

其中 Local services 主要包括：

- 世界包加载与构建
- 本地叙事生成
- 偏离分析
- Delta 状态管理
- 记忆压缩与召回
- 桥接规划
- 场景适配
- 本地 TTS
- 轻量预取

优点：

- 运行时不再依赖 HTTP sidecar
- 桌面应用真正具备前后端一体化能力
- 后续迁移路径更清晰

当前限制：

- 还没有完全复刻 Python 运行时的所有高级编排分支
- 某些 prompt 和异常恢复链路仍有差异

## 三、客户端分层

Flutter 客户端主要由以下几层组成。

### 1. 页面层

位于 `lib/src/pages/`。

作用：

- 展示起始页、设置页、游戏页、资源库页
- 管理界面交互、按钮状态、文本输入、语音输入
- 不直接承载复杂业务逻辑

### 2. 控制器层

核心入口：

- `lib/src/app_controller.dart`

职责：

- 管理当前页面状态
- 管理语言、世界包、后端可达性、运行模式
- 协调 UI 与后端 API

### 3. 后端 API 抽象层

核心文件：

- `lib/src/services/backend_api_contract.dart`
- `lib/src/services/api_client.dart`
- `lib/src/services/local_backend_api.dart`

这里定义了统一接口，使页面层不需要关心当前到底是 sidecar 模式还是 integrated 模式。

### 4. 运行时接入层

核心文件：

- `lib/src/services/backend_runtime_contract.dart`
- `lib/src/services/backend_runtime_io.dart`

作用：

- 在桌面模式下管理 sidecar 的启动、停止和重启
- 将 sidecar 模式封装成可替换的运行时能力

## 四、世界包与数据流

### 1. 世界包定位

世界包 `.wpkg` 是整个游戏运行时的核心输入结构。它把原始文本整理成可游玩的剧情数据，并附带 lorebook、事件、转场、图片等内容。

### 2. 世界包构建路径

当前有两种来源：

- Python 旧提取管线生成（原仓库 [ypcypc/WhatIf](https://github.com/ypcypc/WhatIf) 的 `backend/` 提供）
- Flutter 集成构建流程生成

Flutter 侧相关服务：

- `local_worldpkg_builder.dart`
- `local_worldpkg_extraction_enhancer.dart`
- `local_lorebook_builder.dart`
- `local_transition_builder.dart`

主要流程：

1. 读取原始文本
2. 分句
3. 进行启发式事件划分
4. 提取角色、地点、物品、知识条目
5. 生成 transition / preconditions
6. 在需要时调用 LLM 对事件和 lorebook 做增强
7. 打包为 `.wpkg`

## 五、集成运行时核心链路

### 1. LocalBackendApi

入口文件：

- `lib/src/services/local_backend_api.dart`

职责：

- 对 UI 提供与 HTTP 模式一致的 API 形态
- 管理世界包扫描、加载、存档、语音列表、文本分段等
- 将页面层请求转发给 `LocalGameEngine`

### 2. LocalGameEngine

入口文件：

- `lib/src/services/local_game_engine.dart`

职责：

- 管理当前事件、阶段、回合数、玩家名、存档状态
- 推进三阶段剧情流
- 维护当前 transcript、Delta 状态、压缩记忆、偏离历史
- 在合适时机触发桥接规划与场景适配
- 维护轻量预取缓存

### 3. LocalNarrativeGenerator

职责：

- 基于 phase source、历史上下文、记忆上下文、实体上下文生成面向玩家的叙事文本
- 在有配置时调用 LLM slot
- 在缺少 slot 或 API key 时退回本地启发式结果

### 4. Deviation / Delta

核心文件：

- `local_deviation_agent.dart`
- `local_delta_state.dart`

职责：

- 判断玩家行动是否导致世界状态偏移
- 为偏移创建和演化 Delta
- 为后续桥接、场景适配和记忆提供状态输入

### 5. Memory Compression

核心文件：

- `local_memory_compression.dart`

职责：

- 在事件完成后把 transcript 压缩为 L0 摘要
- 在积累到一定数量后再形成 L1 摘要
- 在后续事件中根据 query 做相关记忆召回

### 6. Bridge Planner

核心文件：

- `local_bridge_planner.dart`

职责：

- 检测当前 Delta 与下一个事件 preconditions / setup 前提之间是否冲突
- 冲突时生成 bridge narrative
- 必要时演化已有 Delta，使世界变化可以继续接入后续剧情

### 7. Scene Adaptation

核心文件：

- `local_scene_adaptation.dart`

职责：

- 在不需要完整桥接的情况下，局部改写当前阶段的输入语境
- 让当前场景反映已生效的世界变化

## 六、语音与输入

### 1. 旁白播放

Sidecar 模式：

- 使用 SSE `audio` 事件
- 由 `NarrationAudioPlayer` 播放 base64 音频数据

Integrated 模式：

- 使用 `LocalTtsSpeaker`
- 直接调用 Flutter 平台 TTS
- 不再人为构造伪音频链路

### 2. 麦克风输入

使用：

- `speech_to_text`

作用：

- 在游戏页支持听写式输入
- 可与语音旁白形成"说完继续听"的对话模式体验

## 七、存档与运行时数据

### 1. 存档目录

- `saves/save_001/`
- `saves/save_002/`

### 2. 存档内容

主要包括：

- 当前事件 ID
- 当前阶段
- 总回合数
- transcript
- Delta 状态
- 记忆压缩状态
- 当前事件内偏离历史

### 3. 日志与运行输出

- `logs/sessions/*.jsonl`
- `output/*.wpkg`

这些目录都属于运行期生成数据，不应提交到 GitHub。

## 八、Android 与桌面本地工具链

项目支持在 `flutter_client/` 内维护本地 Android 打包工具链：

- `.android-sdk/`
- `.jdk/`
- `.flutter-maven/`

这样做的意义是：

- 不要求开发者在系统全局安装 Android SDK
- 方便在仓库范围内复现 APK 打包流程

桌面端仍以 Windows Flutter 运行流为主。

## 九、推荐扩展方向

如果后续继续迭代，这几个方向最值得投入：

1. 继续将 Python 运行时中的高级 scene adaptation orchestration 迁移到 Dart
2. 扩大 integrated 模式的回归测试覆盖，特别是多事件、多存档、多世界包组合
3. 明确 sidecar 模式是长期兼容路径还是阶段性过渡方案
4. 如果 Android 要变成正式目标，针对移动端重新设计一套更适合触屏的 UI 与交互

---

> 原始仓库：[ypcypc/WhatIf](https://github.com/ypcypc/WhatIf)
