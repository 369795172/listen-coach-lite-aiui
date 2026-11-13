# Agent Manifest

## Identity
- Name: listen-coach-lite
- Version: 0.1.4
- Description: 听懂对方——戴上就能听懂对方在说什么，给你回应方向

## Capabilities
- Permissions:
  - microphone
  - llm

---

> 分界说明：上方 OAF manifest（Agent Manifest / Identity / Capabilities）是 AIUI Studio 读取的提审声明面，保持最小勿加内容；下方为工程治理层（维护者/agent 读），Studio 不依赖。

## Scope

listen-kernel 公开版 AIUI 子项目（Rokid Agent Store 发布面「听懂对方」）：平台全托管（ASR + LLM 全走 Rokid 平台服务）、与主线（`glasses/`、`brain/`）零数据交叠。

## Structure Routing

| 文件 | 用途 |
|---|---|
| `AGENTS.md` | 顶部 OAF manifest（提审声明面）+ 本治理层 |
| `app.json` | OAF 应用清单（pages 注册；敏感权限声明面，仅 `RECORD_AUDIO`） |
| `app.js` | 应用生命周期（onHide/onError 兜底委托会话收口） |
| `package.json` | npm 工程元数据（零运行时依赖） |
| `pages/index/index.ink` | 沉浸式三区面板（渲染 + 事件派发 + 手势判定；零业务判断） |
| `pages/index/state.js` | 会话状态机纯函数（`transition()` 唯一裁决层） |
| `pages/index/voice.js` | 语音链路接线（全仓唯一触碰 AIUI API 的模块；内嵌 prompt 镜像） |
| `pages/index/settlement.js` | 结算纯函数（三标记解析 / 兜底卡 / 场景匹配） |
| `prompts/coach_system.md` | 对话教练系统提示词源文件（镜像进 voice.js，契约守护一致性） |
| `prompts/samples.json` | 固定样例（≥6 场景；兜底卡数据源） |
| `tests/prompt_contract.mjs` | L0 prompt 资产契约（10 断言） |
| `tests/state_contract.mjs` | L0 状态机契约（234 断言） |
| `tests/settlement_contract.mjs` | L0 结算/接线契约（165 断言，含竞态与聆听窗口组） |
| `scripts/check_ready.sh` | 环境就绪探测（node / npm 脚手架包 / 真机 / scrcpy） |
| `scripts/check_structure.sh` | OAF 结构校验（manifest 存在 + pages 可解析） |
| `scripts/check_scope.sh` | 主线零改动差分核验（BASELINE 基线） |
| `scripts/check_terms_gate.sh` | terms-gate 机器读取（结论=可提审才 exit 0） |
| `scripts/package_stage.sh` | 提审暂存打包（只含提审面文件，allowlist fail-closed） |
| `docs/prd.md` | What & Why（范围与验收 SSOT：非目标 + 成功标准 + 约束三形式） |
| `docs/rfc.md` | How（架构 + 决策否案 D1-D8） |
| `docs/working.md` | Changelog + Lessons（aiui 子项目 change 记录 SSOT；**固定位于 docs/ 下**） |
| `docs/test.md` | 分层验证（L0 契约 → L1 结构边界 → L2 预览 → L3 真机） |
| `docs/onboarding.md` | 账号与设备准入 checklist（HITL 边界：实名/登录由 Marvin 本人） |
| `docs/findings.md` | 平台工具链探测记录（权限双声明面 / aix CLI / ink-open 不可考） |
| `docs/session-governance.md` | 会话治理护栏自查（符号锚）+ 假设节 A1-A5（护栏与假设 SSOT） |
| `docs/store-metadata.md` | 商店提审资料草稿（字段限额与口径一致性 check） |
| `docs/terms-findings.md` | LLM 数据条款问询状态（terms-gate 结论 SSOT） |
| `docs/terms-inquiry-draft.md` | 条款问询帖草稿（三问原文） |
| `docs/review-log.md` | 提审状态轮询记录（**submission tracking SSOT**） |
| `assets/` | 图标（6 尺寸 PNG + svg 源；README 有再生成命令） |
| `llm-mock/config.json` | 本地确定性 mock LLM（仅本地预览调试，**禁止入真机/提审包**） |
| `README.md` | 人读入口（本地开发三命令 + 目录速览 + 边界硬规则） |
| `BASELINE` | 主线零改动差分基线（工程开工时的 git commit） |
| `dist-stage/` | package_stage.sh 产物（gitignored，不入库） |

## Doc Update Discipline

- 每个 meaningful change 后必更新 `docs/working.md`：日期键倒序、特性级 bullet、Lessons 写成可迁移原则句
- 更新与 commit 绑定：先写 working.md 再 commit，不写不 commit
- 决策变更全量回写：影响几份文档就改几份（prd / rfc / session-governance / 本文件同步），不留口径漂移
- 审核驳回与平台实测结论落 `docs/working.md` + `docs/review-log.md`；假设证伪回写 `docs/session-governance.md` 假设节

## Git

- commit 切法：fix / release / docs 分离，不混装 mega-commit（沿仓根 AGENTS.md 反例教训）
- 分支：main 直推（仓根惯例）；commit 前缀标注来源工具（`[OpenCode]`）
- commit 前检查：`docs/working.md` 已更新；无 secrets/凭证/日志入库；`grep -rn "network\." aiui/` 零命中
- 提审重提流程：`package_stage.sh` 组装暂存目录 → GitHub 暂存仓导入 → Studio 全新 Agent（历史流程见 `docs/review-log.md`）

## Validation

三套契约测试 + 结构/边界/暂存校验，均在 listen-kernel 仓库根目录执行，退出码 0 为过：

```bash
node aiui/tests/prompt_contract.mjs        # L0 prompt 契约（10 断言）
node aiui/tests/state_contract.mjs         # L0 状态机契约（234 断言）
node aiui/tests/settlement_contract.mjs    # L0 结算/接线契约（165 断言）
bash aiui/scripts/check_structure.sh       # OAF 结构校验（manifest + pages 解析）
bash aiui/scripts/package_stage.sh         # 提审暂存打包（allowlist 校验）
bash aiui/scripts/check_scope.sh           # 主线零改动差分
```

治理结构合规（rootgrove 仓库根目录执行）：`./venv/bin/python tools/project_scaffold/scaffold.py check projects/listen-kernel/aiui`。分层验证全貌见 `docs/test.md`。

## Key Decisions

完整否案见 `docs/rfc.md`（D1-D8）。一句话版：

1. prompt 镜像内嵌 voice.js，不在运行时 import .md（D1）
2. generation 代次守卫关闭跨会话竞态（D2）
3. 提审走暂存目录隔离，VFS 全目录打包会把开发辅助物带进商店包（D3）
4. 三区渲染自持一屏 + tap/滑动手势区分（D4/D5，v0.1.3）
5. 聆听窗口三重设计：起手宽限 + 段间静默 + 空缓冲守卫（D6，v0.1.2）

## What NOT to do

- 不声明 `network` 权限、不发出任何外部 HTTP 请求；不调用自建后端 / Keychain 凭证 / Z.AI 订阅
- 不做连续监听、后台常驻（agentWorkers）、CAMERA、GEOLOCATION、媒体库权限
- 不做 TTS 播报（不替用户发声，HUD-only）；不在结算前上 HUD 中间文本
- prompt 资产零个人数据：不注入 rules/USER.md、rootgrove contexts、真实人名、本机路径
- 不挂 GitHub repo 外链，不改 listen-kernel repo 可见性；不改主线 `glasses/`、`brain/` 任何文件（例外仅仓根 README 相邻项目表、docs/working.md、.gitignore）
- 结构红线：不在 index.ink 写业务判断；不绕过 voice.js 触碰 AIUI API；状态裁决只经 state.js `transition()`；结算只经 settlement.js
- 不手改 voice.js 内嵌镜像——改 `prompts/` 源文件后同步镜像并跑契约测试
- `llm-mock/` 不入真机包/提审包；mock 不发任何网络请求

## 维护节奏

- 改实现：同步 `docs/rfc.md` 与 `docs/test.md` 对应层
- 改产品边界：先改 `docs/prd.md` 非目标 / 成功标准，再动代码
- 审核驳回：读理由 → 定位到代码假设 → 证伪回写 session-governance.md 假设节 → 整改重提记 review-log.md
- 提审窗口内每 24h 轮询记 `docs/review-log.md`；上架为终态
- 每个 meaningful change 先写 `docs/working.md` 再 commit
