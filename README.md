# flutter-ios-agent-test

一个 Claude Code / Claude Desktop 通用的 Agent Skill。让 AI agent 接过一个 Flutter 项目 + 一个测试意图后,能自主编译、装到 iOS 模拟器、跑 Patrol 测试、分类失败、迭代修复——命中停止条件时干净地交还给人,而不是无限乐观地瞎改。

> 用一句话描述: **让 agent 有一套可信的 Flutter iOS 测试闭环,能跑、能诊断、能停。**

## 它解决什么问题

Agent 在"跑通一个 Flutter 测试"这种任务上,最常见的四个失败模式:

1. **改断言迎合 app** — `expect(x, 5)` 失败就改成 `expect(x, 4)`,测试永远"通过"
2. **误分类失败** — 构建失败、测试超时、断言失败三种信号在 log 里长得像,但正确动作完全相反
3. **Token 爆炸** — `xcrun simctl spawn log` / `xcresulttool` 原始 dump 塞进 context,一轮迭代几万 tokens
4. **不知道什么时候该停** — 连续改 10 个文件都没让测试前进,还在硬改

这个 skill 把这四件事硬编码进流程:

- **硬规则**禁止改断言、禁止删失败测试、禁止跳过 triage
- **信号表**把 `TimeoutException` / `TestFailure` / `xcodebuild exit 65` 等 20+ 条真实信号映射到 5-A 至 5-E 类别,每类有明确的允许动作和禁止动作
- **脚本契约**所有 shell 脚本 stdout 只输出一行 JSON 摘要,全量 log 留在 `.test-results/iter-N/` 磁盘上,按需 grep
- **停止条件**迭代上限 / 同类失败连续次数 / 错误面未缩小 / 单次修改文件/行数 都有硬阈值

## 适用场景

适用:

- 用户有一个 Flutter 项目,想在 iOS 模拟器上验证某个场景
- 用户用自然语言或 Markdown 描述一个流程,想自动转成 Patrol 测试并跑通
- 用户有现成的 Patrol 测试失败了,想让 agent 分类 + 修复

不适用:

- 纯 Android 测试
- Flutter web / desktop
- 非 Flutter 的 iOS app
- 只想"写"测试不想跑

## 接入方式

这个 skill 遵守 Anthropic 的标准 Agent Skill 格式(`SKILL.md` + YAML frontmatter),因此可以被 **Claude Code CLI / Claude Desktop / Cursor** 以及其他支持 AGENTS 协议的 agent 客户端直接加载。

### 方式一:作为全局 skill(一次安装,所有项目可用)

把本仓库克隆到 skill 目录:

```bash
git clone <this-repo-url> ~/.claude/skills/flutter-ios-agent-test
```

| 客户端 | 说明 |
|---|---|
| **Claude Code CLI** | 自动扫 `~/.claude/skills/`,agent 按 `description` 触发词激活 |
| **Claude Desktop** | 同上路径,同样自动扫 |
| **Cursor** | 同样扫 `~/.claude/skills/`(已验证:Cursor 1.x 起把 `.claude/skills/` 里所有 skill 一并加载到 available skills) |

装完无需额外配置 — agent 看到 `"test Flutter on simulator"` / `"验证 Flutter 功能"` / `"跑通流程"` / `"Patrol failures"` 等触发词时会自动激活。

### 方式二:项目级接入(只在当前仓库激活,精确控制触发范围)

仓库根目录下的 `templates/` 提供三种 snippet,对应三种项目级入口:

| Snippet | 目标文件 | 适用客户端 | 触发范围 |
|---|---|---|---|
| `templates/CLAUDE_md_snippet.md` | `CLAUDE.md`(项目根) | Claude Code CLI / Claude Desktop | 每次开会话加载 |
| `templates/AGENTS_md_snippet.md` | `AGENTS.md`(项目根) | Cursor / OpenAI Codex / 其他 AGENTS-aware agent | 每次开会话加载 |
| `templates/cursor_rule_snippet.mdc` | `.cursor/rules/flutter-ios-testing.mdc` | Cursor 原生 rule 系统 | 按 `globs:` 匹配(`pubspec.yaml` / `patrol_test/**` / `ios/Podfile`)自动附加,不污染其他项目 |

选哪一个:

- **跨客户端最通用** → `AGENTS.md`
- **只用 Claude Code** → `CLAUDE.md`
- **只用 Cursor 且希望只在 Flutter 项目激活** → `.cursor/rules/*.mdc`

三个 snippet 都需要把内容中的 `<PATH_TO_SKILL>` 替换成 skill 的真实绝对路径。

## 核心循环

完整版见 `reference/iteration-protocol.md`。下面是简图:

```
[0] 意图输入 → 若非 .dart,用 template 生成 Patrol 测试,展示给用户
[1] 环境准备(boot_sim.sh,记录 last_known_good_commit)
[2] Build & Install(build.sh)
     └─ 失败 → 5-A
[3] Run Test(run_test.sh)
[4] 通过? → DONE
[5] 失败分类(MANDATORY — 不可跳)
     5-A 构建失败 → 改 Dart / 改 Podfile / 改签名
     5-B 测试超时 → 改 Patrol finder / 超时 / 滚动
     5-C 断言失败 → 改 app 逻辑(禁止改断言)
     5-D 环境问题 → 重启 sim / 清 pod / 改端口
     5-E 不确定 → 抓 a11y tree,若仍不清楚则 STOP
[6] 应用修复(记录: file / lines / why / expected_effect)
[7] 停止条件检查(先于回 [2])
     - iter >= 6 → STOP
     - 同一 test+category 连续 3 次 → STOP
     - 连续 2 次修复未缩小错误 → 回滚 + STOP
     - 单次修复 > 10 文件 或 > 200 行 → STOP
     都没命中 → iter++, 回 [2]
```

## 硬规则

skill 顶层 `SKILL.md` 明确禁止:

- 改断言来让测试"通过"
- 删掉失败的测试(必要时用 `skip: 'reason'` 标记并报告)
- 跳过失败分类步骤
- 超过最大迭代次数继续硬跑
- 错误面连续 2 次未缩小还继续改

## 目录结构

```
flutter-ios-agent-test/
├── SKILL.md                       # skill 主入口(带 Agent 触发描述)
├── PLAN.md                        # 本 skill 的设计决策 + smoke test 记录
├── README.md                      # 本文件
├── reference/
│   ├── iteration-protocol.md      # 核心状态机 + 停止条件
│   ├── failure-triage.md          # 信号 → 类别 → 动作 查找表(5-A ~ 5-E)
│   ├── patrol-patterns.md         # Patrol 4.x 语法速查(防止 agent 幻觉)
│   └── troubleshooting.md         # iOS / Xcode / CocoaPods / xcresult 常见坑
├── scripts/
│   ├── boot_sim.sh                # 幂等启动模拟器 → JSON
│   ├── build.sh                   # patrol build + install → JSON
│   ├── run_test.sh                # patrol test + xcresult parse → JSON
│   ├── parse_failure.py           # xcresult/log → 结构化失败数组
│   └── sim_snapshot.sh            # a11y tree(默认) / screenshot(按需)
└── templates/
    ├── patrol_test_template.dart  # 生成 Patrol 测试的起手模板
    └── CLAUDE_md_snippet.md       # 项目 CLAUDE.md 接入片段
```

## 前置要求

Skill 在第一次运行时会自动验证并缓存:

- Flutter ≥ 3.22(Patrol 4.x 要求 iOS deployment target ≥ 13.0)
- Patrol CLI 已激活: `dart pub global activate patrol_cli`(本 skill 开发于 `patrol_cli 4.3.1`)
- Xcode 16+ 或 Xcode 26.x(脚本对 `xcresulttool` 新旧两种 API 都做了版本适配)
- 至少一个 iOS 模拟器: `xcrun simctl list devices available`
- 目标 sim 的 iOS runtime 与 Xcode 自带 SDK 版本匹配(否则 `patrol test` 的 `-destination "OS=latest"` 会找不到设备)

任一缺失,skill 会停下来告诉用户该装什么,**不会未经授权做全局安装**。

## Patrol 4.x 项目一次性 setup(skill 管不到的部分)

Patrol 4.x 需要在 iOS 侧做一次性手工配置,之后 skill 全自动。未配置时 skill 会返回:

```
xcresult issue: Tests in the target "RunnerUITests" can't be run because
"RunnerUITests" isn't a member of the specified test plan or scheme.
```

这时按下面一次:

1. `flutter pub add --dev patrol`
2. `cd ios && pod install`
3. Xcode 打开 `ios/Runner.xcworkspace` → Product → Scheme → Edit Scheme → Test → `+` → 选 `RunnerUITests`
4. Xcode 的 File Inspector 里把 scheme 标成 Shared(勾 `Shared`),commit `ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme`
5. Podfile 的 `platform :ios, '13.0'` 取消注释并设 ≥ 13.0

之后所有迭代全程 skill 自己跑。

## Token 纪律

Simulator / xcresult / Flutter build 的原始 log 是 token 杀手,skill 默认:

- 所有脚本 stdout **只输出一行 JSON 摘要**,全量 log 路径在 `build_log_path` / `test_log_path` 字段里,按需读
- `parse_failure.py` 主动剥离 SDK 栈帧(`package:flutter/` / `package:patrol/` / `dart:` 等),只留 app-level 堆栈
- `sim_snapshot.sh` **默认 a11y tree 不截图**,只有树不足以解释失败时才取 screenshot
- 每轮迭代之间只输出一行状态: `iter 3/6 · build ok · 2/3 tests pass · fixing 5-C in login_screen.dart`

目标:6 次迭代闭环典型 token 开销 ≤ 30k。

## 已知局限

- 当前脚本主打 iOS 模拟器;真机需要 signing / provisioning 配置,skill 只做 triage 不代改
- 自然语言 → Patrol 测试的生成依赖 agent 的 Patrol 语法知识 + `patrol-patterns.md` 速查,复杂交互(permissions / deep links / background app)需要人工 review 生成的测试
- `sim_snapshot.sh --tree` 需要 [`axe`](https://github.com/cameroncooke/AXe) CLI;未装时自动 fallback 到 screenshot 并在 `warning` 字段标记
- Patrol CLI 目前不支持 `-destination "id=<UDID>"`,只用 `name=<X>,OS=latest`;sim runtime 和 Xcode SDK 版本必须匹配

## 贡献

- 改脚本前先本地跑 `bash -n scripts/*.sh && python3 -c "import ast; ast.parse(open('scripts/parse_failure.py').read())"` 做语法检查
- 任何改动都要保证 stdout 只有一行 JSON(破坏契约会让 agent 失明)
- 新增 failure 信号映射时同时更新 `reference/failure-triage.md` 的表和 per-category 详细块

## License

MIT(或按仓库实际 LICENSE 文件)。
