# 集成运行时说明

这份文档描述的是 `WHATIF_BACKEND_MODE=integrated` 时启用的本地 Flutter 集成运行时。它代表迁移后的新方向：让桌面应用在本地直接通过 Dart 服务完成主线叙事流程，而不是在运行时强依赖 Python HTTP 后端。

## 一、目标与边界

集成运行时的目标不是立刻删除 Python sidecar，而是提供一条新的本地执行路径：

- 默认路径：`Flutter -> Python sidecar -> HTTP / SSE`
- 集成路径：`Flutter -> Dart 本地服务`

这样做有三个直接收益：

1. 桌面端逐步形成前后端一体化结构
2. 主链路功能可以在 Flutter 项目内持续沉淀
3. 后续如果继续迁移 Python 后端，会有清晰的落点和边界

## 二、核心入口

集成运行时的主要入口如下：

- 模式选择：
  - `lib/src/services/backend_api_io.dart`
- 本地后端 API：
  - `lib/src/services/local_backend_api.dart`
- 本地游戏引擎：
  - `lib/src/services/local_game_engine.dart`
- 本地世界包读取：
  - `lib/src/services/local_worldpkg.dart`
- 本地世界包构建：
  - `lib/src/services/local_worldpkg_builder.dart`

## 三、能力地图

### 1. 世界包构建能力

集成运行时已经支持从本地文本构建可游玩的世界包。

当前实现包括：

- `.txt` / `.md` 输入
- 分句
- 启发式事件抽取
- 启发式 lorebook 抽取
- 启发式 transition 生成
- 可选的 LLM 事件重分段与 lorebook 增强

关键文件：

- `local_worldpkg_builder.dart`
- `local_worldpkg_extraction_enhancer.dart`
- `local_lorebook_builder.dart`
- `local_transition_builder.dart`

### 2. 剧情推进能力

集成运行时已经支持主线桌面剧情流：

- 世界包加载
- 首事件进入
- `setup / confrontation / resolution`
- 玩家动作提交
- 事件推进
- 存档 / 读档
- 事件背景图读取

关键文件：

- `local_backend_api.dart`
- `local_game_engine.dart`
- `local_worldpkg.dart`

### 3. 叙事生成与偏离处理

为了不只是"把原文吐出来"，集成运行时引入了一套轻量但可扩展的本地 agent 服务。

包括：

- 本地叙事生成
- 玩家动作偏离分析
- Delta 状态管理
- 桥接规划
- 场景适配

关键文件：

- `local_narrative_generator.dart`
- `local_deviation_agent.dart`
- `local_delta_state.dart`
- `local_bridge_planner.dart`
- `local_scene_adaptation.dart`

### 4. 上下文、记忆与召回

集成运行时目前已经具备完整的"短期文本上下文 + 压缩记忆召回"链路。

包括：

- recent transcript context
- lorebook entity context
- transition preconditions 注入
- L0 / L1 记忆压缩
- 查询式召回

关键文件：

- `local_context_enrichment.dart`
- `local_memory_compression.dart`

### 5. 语音与预取

为了让 integrated 模式不只是"功能能跑"，而是有可用体验，当前又补齐了两块关键能力：

- 本地 TTS 旁白播放
- 轻量预取

本地 TTS：

- integrated 模式下不再依赖 sidecar 音频 SSE
- 直接通过 Flutter 平台 TTS 朗读当前旁白

轻量预取：

- 在 `setup -> confrontation` 之间预取下一段提示
- 在 `resolution -> next event` 之间预取下一事件入口
- 保持实现轻量，不机械照搬 Python worker

关键文件：

- `local_tts_speaker.dart`
- `local_game_engine.dart`
- 游戏页面

## 四、运行时主流程

### 1. 启动阶段

1. `LocalBackendApi.create()` 初始化路径、配置和本地服务
2. UI 选择世界包后，`LocalGameEngine` 接管当前 `LocalWorldPkg`
3. 第一事件进入 `setup`
4. `LocalNarrativeGenerator` 根据 phase source 生成面向玩家的文本

### 2. 对局阶段

当玩家推进剧情时，主要流程是：

1. 玩家进入 `confrontation`
2. 通过文本或语音输入动作
3. `LocalDeviationAgent` 分析这次动作是否对世界造成偏移
4. `LocalDeltaStateManager` 创建或更新 Delta
5. `LocalNarrativeGenerator` 生成 `resolution`
6. 如果启用了 TTS，Flutter 直接朗读旁白

### 3. 事件切换阶段

当当前事件结束，需要进入下一个事件时：

1. 当前事件 transcript 会被压缩成 L0 记忆
2. 如果数量达到阈值，会进一步形成 L1 记忆
3. 活跃 Delta 会衰减
4. `LocalBridgePlanner` 检测 Delta 是否与下一个事件冲突
5. 如果冲突，优先生成 bridge narrative
6. 如果只是局部世界变化，则由 `LocalSceneAdaptationPlanner` 进行场景适配
7. 引擎会尝试预取下一段最可能用到的叙事结果

## 五、LLM Slot 复用策略

集成运行时尽量沿用 `backend/llm_config.yaml` 中已有的 slot 命名，避免重新造一套配置体系。

典型 slot 包括：

- `event_extractor`
- `decision_text_extractor`
- `lorebook_extractor`
- `setup_orchestrator`
- `confrontation_orchestrator`
- `resolution_orchestrator`
- `unified_writer`
- `deviation_controller`
- `l0_compressor`
- `l1_compressor`
- `bridge_planner`

如果 slot 缺失，或者对应 provider key 不可用，集成运行时不会直接失败，而是退回本地启发式逻辑。

## 六、和 Python 运行时的差异

当前 integrated 模式已经能覆盖主链路，但它仍然是"面向本地桌面可用"的精简实现，而不是对 Python 运行时的逐行复刻。

已知差异：

- 还没有完整复刻 Python 版本更复杂的 scene adaptation orchestration
- 预取已经实现，但仍比 Python worker 更轻量，没有完整复制 stream takeover 等行为
- 某些 prompt 模板、恢复分支、边界条件处理与旧运行时不完全一致

这意味着：

- 如果你追求最接近旧系统的运行时行为，请继续使用 sidecar 模式（需搭配原仓库 [ypcypc/WhatIf](https://github.com/ypcypc/WhatIf) 的 `backend/`）
- 如果你追求"本地一体化桌面应用"的未来方向，请优先演进 integrated 模式

## 七、当前结论

对于"本地可运行、桌面优先、逐步后端迁移"的目标来说，集成运行时已经不是一个演示壳，而是一个可继续迭代的主干基础设施。

它目前最适合承担的角色是：

- 本地桌面实验与演进主线
- Dart 侧运行时能力沉淀中心
- 后续后端进一步迁移的承接层

---

> 原始仓库：[ypcypc/WhatIf](https://github.com/ypcypc/WhatIf)
