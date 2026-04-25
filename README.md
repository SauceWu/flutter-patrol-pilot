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
├── README.md                      # 本文件
├── CHANGELOG.md                   # 版本变更日志(v0.1 / v0.2 / v0.3)
├── reference/
│   ├── iteration-protocol.md      # 核心状态机 + 停止条件
│   ├── failure-triage.md          # 信号 → 类别 → 动作 查找表(5-A ~ 5-E)
│   ├── patrol-patterns.md         # Patrol 4.x 语法速查(防止 agent 幻觉)
│   └── troubleshooting.md         # iOS / Xcode / CocoaPods / xcresult 常见坑
├── scripts/
│   ├── boot_sim.sh                # 幂等启动模拟器 → JSON
│   ├── build.sh                   # patrol build + install → JSON
│   ├── run_test.sh                # xcodebuild test-without-building (无 sim clone) + xcresult parse → JSON
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

### fvm 项目自动支持

`scripts/build.sh` 和 `scripts/run_test.sh` 启动时会从当前目录向上最多 8 层查找 `.fvm/flutter_sdk/bin`(monorepo/example 布局下 fvm 常挂在 repo 根),找到就 prepend 到 `PATH`。这意味着:

- **在 fvm 管理的项目里不需要任何额外配置** —— skill 会自动用 `.fvmrc` 锁定的 Flutter 版本而不是系统全局版本
- 在 monorepo 里从子目录(例如 `example/`)触发也 work,只要根目录有 `.fvm/flutter_sdk`
- 非 fvm 项目不受任何影响(检测失败就走原逻辑)
- `patrol_cli` 建议用 fvm 的 dart 激活: `fvm dart pub global activate patrol_cli`,这样 patrol 内部跑的 dart 跟项目 pin 的 Flutter 一致

检测成功时会在 stderr 打印 `[fvm] using /path/to/.fvm/flutter_sdk`,方便调试。

## Patrol 4.x 项目一次性 setup

### 推荐:一键 init(skill v0.3+)

在 Flutter 项目根目录(含 `pubspec.yaml` + `ios/Runner.xcodeproj`)跑:

```bash
bash <skill>/scripts/init_project.sh
```

`init_project.sh` 是**幂等**的,每一步先检查"已做过就跳过",踩过的所有坑都一次性修好:

| Step | 做什么 | 对应 Issue |
|---|---|---|
| 1 | preflight:验证 Flutter 项目结构 + ruby/xcodeproj/xcodebuild 可用 | — |
| 2 | 向上 8 层查找 `.fvm/flutter_sdk` 并 prepend PATH(monorepo/example) | — |
| 3 | 把 `~/.pub-cache/bin` append 到 PATH | — |
| 4 | 从 `pubspec.yaml` / `project.pbxproj` / `build.gradle` 推断 `app_name` / `bundle_id` / `package_name` | — |
| 5 | `pubspec.yaml`:加 `patrol` dev_dep + `patrol:` 配置块 | — |
| 6 | `ios/Podfile`:`platform :ios, '13.0'` + `use_modular_headers!` + `target 'RunnerUITests'` | Issue 12 |
| 7 | `ios/Runner.xcodeproj/project.pbxproj`:`objectVersion 70 → 60`,`ENABLE_USER_SCRIPT_SANDBOXING YES → NO` | Issue 13, 14 |
| 8 | `xcodeproj` gem 自动建 `RunnerUITests` UI Test Bundle target(含 Info.plist / build settings / target dependency on Runner) | Issue 12 |
| 9 | 写 `ios/RunnerUITests/RunnerUITests.m` 的 5 行 Patrol bootstrap | Issue 12 |
| 10 | `Runner.xcscheme`:`parallelizable="YES" → "NO"` + 确保 RunnerUITests 在 `<Testables>` 里 | Issue 15 |
| 11 | 脚手架 `patrol_test/smoke_test.dart`(带 intentional typo,给 agent 一个 5-D 分类练手题) | — |
| 12 | `.gitignore`:加 `patrol_test/test_bundle.dart`、`integration_test/test_bundle.dart`、`.test-results/` | — |
| 13 | `patrol_cli` 重激活(用 fvm dart 如果检测到)+ `flutter pub get` + `cd ios && pod install` | — |

失败时用 `reference/troubleshooting.md` 里编号的 Issue 定位。

**常用参数:**
```bash
bash <skill>/scripts/init_project.sh --dry-run            # 打印"会改什么",一个字节都不动
bash <skill>/scripts/init_project.sh --skip-pod-install   # 已知 pod install 会挂,先跳过
bash <skill>/scripts/init_project.sh --skip-pub-get       # 同上
bash <skill>/scripts/init_project.sh --patrol-version "^4.5.0"   # 固定版本
bash <skill>/scripts/init_project.sh \
    --app-name foo --bundle-id com.acme.foo --package-name com.acme.foo
```

stdout 最后一行是 JSON summary(`success`、`changes[]`、`next_steps[]`),适合 agent 消费。

### 别在 Xcode 里 Cmd+B 编 RunnerUITests

`PATROL_INTEGRATION_TEST_IOS_RUNNER` 宏依赖 `-D CLEAR_PERMISSIONS=...` / `-D FULL_ISOLATION=...`,这俩 flag 只有 `patrol build` / `patrol test` 会自动注入,**Xcode GUI 永远编不过这个 target**。调试时用 `scripts/build.sh`。

### 手工 setup(懂了再动,否则用 `init_project.sh`)

如果想手改/CI 不能跑 ruby/想确认每步动了什么,对应文档:

1. 加依赖: `flutter pub add --dev patrol && dart pub global activate patrol_cli`(fvm 项目用 `fvm dart pub global activate patrol_cli`)
2. Podfile: 见 `init_project.sh` Step 6 —— 必须 `use_modular_headers!` + `target 'RunnerUITests' do inherit! :complete end`
3. Xcode target:File → New → Target → UI Testing Bundle(Objective-C,Target to be Tested = Runner)。建完把 `RunnerUITests.m` 替换成 5 行 Patrol 样板。Product → Scheme → Edit Scheme → Test → `+ RunnerUITests` → 勾 Shared
4. Xcode 26 特殊:`sed -i '' 's/ENABLE_USER_SCRIPT_SANDBOXING = YES/NO/g'` 和 `sed -i '' 's/objectVersion = 70;/objectVersion = 60;/'` 都打 `ios/Runner.xcodeproj/project.pbxproj`
5. Runner.xcscheme:`sed -i '' 's/parallelizable = "YES"/parallelizable = "NO"/g' ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme` —— **不关这个会 clone sim**(Issue 15)
6. `cd ios && pod install && cd .. && patrol doctor` 收尾

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
- **`patrol test` 会触发 Xcode 并行测试 → 克隆出 `Clone 1/2/3` 模拟器**。`xcodebuild test-without-building` 默认 `-parallel-testing-enabled YES`,而 patrol_cli 4.3.x 既不关它,也用 `-destination name=<X>` 而不是 `id=<UDID>`(见 `~/.pub-cache/hosted/pub.dev/patrol_cli-*/lib/src/crossplatform/app_options.dart`)。**本 skill 从 v0.3 起默认绕开 `patrol test`**:`scripts/run_test.sh` 直接用 `patrol build` 产物调 `xcodebuild test-without-building`,主动加 `-parallel-testing-enabled NO -disable-concurrent-destination-testing -destination id=<UDID> -only-testing RunnerUITests/RunnerUITests`,并注入 `TEST_RUNNER_PATROL_{TEST,APP}_PORT=8081/8082`。`scripts/build.sh` 同时把 xctestrun 里 `ParallelizationEnabled` patch 成 `false` 作为冗余防线。只有显式 `--use-patrol` 才会回落到旧路径(此时会重新暴露 clone/同名 bug)。详见 `reference/troubleshooting.md` Issue 15
- 强烈建议把 `ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme` 里两处 `parallelizable = "YES"` 改成 `"NO"` 并提交,让 Xcode UI 跑测试时也不克隆
- **Xcode 26 + Flutter 下 `Runner.app` 会 dyld 崩溃**(症状:XCUI 卡在 `Wait for <bundle> to idle` 6 分钟后报 `The test runner timed out while preparing to run tests`)。Xcode 26 / Swift 6.1 加的 Swift Testing 运行时依赖 `_Testing_Foundation.framework` / `_Testing_CoreGraphics` / `_Testing_CoreImage` / `_Testing_UIKit` 和 `lib_TestingInterop.dylib`,但 Flutter 的构建流水线**不会**把它们 embed 进 `Runner.app/Frameworks/`,iOS 26 sim runtime 也**不附带**。**本 skill 从 v0.3 起,`scripts/build.sh` 在 `xcrun simctl install` 之前自动从 Xcode 平台目录把这 5 个文件 copy 进 `Runner.app/Frameworks/` 和 `RunnerUITests-Runner.app/Frameworks/`**(同时 install 两个 app)。Xcode <26 时自动 no-op。诊断与手工 fix 见 `reference/troubleshooting.md` Issue 16

## 贡献

- 改脚本前先本地跑 `bash -n scripts/*.sh && python3 -c "import ast; ast.parse(open('scripts/parse_failure.py').read())"` 做语法检查
- 任何改动都要保证 stdout 只有一行 JSON(破坏契约会让 agent 失明)
- 新增 failure 信号映射时同时更新 `reference/failure-triage.md` 的表和 per-category 详细块

## License

MIT(或按仓库实际 LICENSE 文件)。
