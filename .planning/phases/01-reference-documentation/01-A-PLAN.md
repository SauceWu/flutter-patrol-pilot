---
phase: 01-reference-documentation
plan: A
type: execute
wave: 1
depends_on: []
files_modified:
  - reference/failure-triage.md
autonomous: true
requirements:
  - REF-01

must_haves:
  truths:
    - "Agent 在步骤 [5] Triage 时可查阅快速信号表，无需外部文档即可将任意失败分类为 5-A 到 5-E"
    - "所有 5 个类别（5-A 到 5-E）均有信号模式、允许动作、禁止动作的详细块"
    - "xcresulttool Xcode 16+ 子命令语法以可复制格式逐字出现在文档中"
    - "xcodebuild code-65 的子原因表覆盖全部 5 个子类别"
    - "pre-triage 检查明确：xcresulttool 输出为空 → 5-D，而非 5-E"
    - "'Total: 0 tests' 识别为 5-A 静默失败，而非成功"
    - "5-B 与 5-C 的关键区分规则（TimeoutException vs TestFailure）以粗体声明"
  artifacts:
    - path: "reference/failure-triage.md"
      provides: "完整的信号→类别→动作查找表，含 pre-triage 检查和各类别详细块"
      min_lines: 200
      contains: "5-A"
  key_links:
    - from: "reference/failure-triage.md"
      to: "reference/iteration-protocol.md"
      via: "loop phase numbers [0]–[7] referenced in each category block"
      pattern: "\\[2\\]|\\[5\\]|\\[6\\]"
---

<objective>
创建 reference/failure-triage.md — agent 迭代循环步骤 [5] Triage 的核心查找文档。

Purpose: 没有此文档，agent 会对错误类别应用错误的修复类别（例如，对签名错误修改 Dart 代码），浪费迭代次数或损坏代码。这是第 1 阶段中优先级最高的文档。

Output: reference/failure-triage.md，包含信号快速参考表、pre-triage 检查、以及全部 5 个类别（5-A 到 5-E）的详细块。
</objective>

<execution_context>
@$HOME/.claude-work-work/get-shit-done/workflows/execute-plan.md
@$HOME/.claude-work-work/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/ROADMAP.md
@.planning/phases/01-reference-documentation/01-CONTEXT.md
@.planning/phases/01-reference-documentation/01-RESEARCH.md
@reference/iteration-protocol.md
</context>

<tasks>

<task type="auto">
  <name>Task A-1: 创建 reference/failure-triage.md（完整内容）</name>
  <files>reference/failure-triage.md</files>

  <read_first>
    - .planning/phases/01-reference-documentation/01-RESEARCH.md — 第 "DOC 1" 小节：所有信号行、pre-triage 检查、各类别详细块的逐字内容规范
    - reference/iteration-protocol.md — 循环阶段编号 [0]–[7]，用于各类别的 "Loop phase" 引用
    - .planning/phases/01-reference-documentation/01-CONTEXT.md — 锁定决策：信号优先、per-category 详细块格式、5-E 强制 a11y 树步骤
  </read_first>

  <action>
创建 reference/failure-triage.md，内容必须完全符合以下结构规范：

---

## 文档结构（按顺序）

### 标题与用途说明（4 行以内）

标题：`# Failure Triage Reference`

简要说明本文档在循环 [5] Triage 步骤中的角色，以及如何使用（先看 pre-triage 检查，再查快速信号表，再看详细块）。

---

### Section 1 — Pre-Triage 检查（必须在信号表之前）

三条检查，编号 1-3：

1. **验证 xcresulttool 输出**：若 `parse_failure.py` 返回 `null` 或 `failures` 数组为空 → 这是 5-D/5-E，而非测试失败。检查 xcresult 路径是否存在以及 xcresulttool 命令是否正确。

2. **检查总测试数**：若 `latest.json` 中 `total == 0` → 视为 5-A（静默失败），而非成功。

3. **验证 xcresulttool 命令版本**：`xcrun xcresulttool --version` → 若 >= 23000，使用 `get test-results summary` 子命令语法；不得使用不带 `--legacy` 的 `get --format json`。

---

### Section 2 — 快速参考信号表（四列，用于快速查找）

列：`Signal (来自 parse_failure.py)` | `Category` | `First Action` | `Forbidden`

必须包含以下所有行（逐字写入，可微调 markdown 格式）：

| Signal | Category | First Action | Forbidden |
|--------|----------|--------------|-----------|
| `xcodebuild exited with code 65` | 5-A | 子诊断：检查日志中是否有端口冲突/缺失 pod/签名/sim 未启动 — 见 5-A 详细块 | 在诊断子原因之前修改 Dart/测试代码 |
| `xcodebuild exited with code 70` | 5-A | 修复 RunnerUITests 签名/provisioning；使用 `--allow-provisioning-updates` | 修改 app 代码 |
| `Dart compilation failed` / `.dart` 文件中有 `error:` | 5-A | 修复指定 file:line 的 Dart 语法/类型错误 | 先碰测试文件 |
| `no such module 'X'` | 5-A | `pod install` / `flutter pub get`；检查 Podfile.lock | 修改 Dart 代码 |
| `Failed to build app with entrypoint test_bundle.dart` | 5-A | 找到导入该文件的测试文件；修复其中的 Dart 错误 | 视为 Xcode 问题 |
| `SWIFT_VERSION` 或 deployment target 不匹配 | 5-A | 在 Podfile 中对齐 `IPHONEOS_DEPLOYMENT_TARGET` | 修改 Flutter 代码 |
| `Total: 0 tests` in summary JSON | 5-A（静默失败）| 检查 `--target` 路径；验证测试使用 `patrolTest()` 而非 `testWidgets()`；检查测试发现 | 视为成功 |
| `WaitUntilVisibleTimeoutException` | 5-B | 获取 a11y 树；检查：widget 是否在屏幕外、是否被遮挡、动画是否未完成；使用 `SettlePolicy.trySettle` 或 `scrollTo()` | 在检查树之前立即添加延迟 |
| `WaitUntilExistsTimeoutException` | 5-B | 检查导航/路由；widget 从未出现在树中 | 假设 widget 存在 |
| `pumpAndSettle timed out` | 5-B | 存在无限动画；将该动作改为 `settlePolicy: SettlePolicy.trySettle` | 删除 pump 调用 |
| `TimeoutException after 0:0X:XX`（runner 级别）| 5-B | 整个测试超过了 runner 超时；增加 `PatrolTesterConfig.visibleTimeout` 或拆分测试 | 忽略超时 |
| `PatrolIntegrationTestBinding` / `Binding is already initialized` | 5-B | 从测试文件中删除 `IntegrationTestWidgetsFlutterBinding.ensureInitialized()`；绝不在 Patrol 测试中调用 vanilla binding 初始化 | 修改 app 代码 |
| `TestFailure: Expected: ... Actual: ...` | 5-C | 找到生成错误值的 app 端代码；修复 app 代码 | **修改 `expect()` 的预期值** |
| `expect($(finder), findsOneWidget)` → 找到 0 个 widget | 5-C | 检查应渲染此 widget 的组件；修复控制渲染的 app 代码 | 删除断言 |
| `Unable to find a destination matching` | 5-D | 模拟器未启动或 UDID 过期；重新运行 `boot_sim.sh` | 修改代码 |
| `flutter pub get` failed | 5-D | 网络问题或 pubspec 错误；修复 pubspec，重试 pub get | 碰测试/app 代码 |
| `com.apple.provenance` xattr 签名错误 | 5-D | `xattr -cr /path/to/Flutter.framework` | 重新生成签名证书 |
| `patrol: command not found` | 5-D | 将 `~/.pub-cache/bin` 添加到 PATH；重新运行 `dart pub global activate patrol_cli` | 修改代码 |
| `gRPC connection refused` / `PatrolAppService connection refused` | 5-D | 测试前模拟器未完全启动；等待 "Booted" 状态，而非仅 "Booting" | 修改代码 |
| `CocoaPods could not find compatible versions` | 5-D | 按顺序运行 `flutter pub get && cd ios && pod install`；如失败：`--repo-update` | 修改 app 代码 |
| 端口冲突 `8081`/`8082` — `Test runner never began executing` | 5-D | `patrol test --test-server-port 8096 --app-server-port 8095`；用 `lsof` 检查端口 | 不诊断就重建 |
| `_pendingExceptionDetails != null` | 5-E | 获取 a11y 树；若仍不清楚 → STOP 并上报 | 推测性代码修改 |
| 假阳性（测试标记为通过，但行为错误）| 5-E | 截图；升级给用户 | 无需人工确认就进行任何修复 |
| `No signal / empty parse output`（null failures 数组）| 5-E | 检查 xcresult 路径有效性；检查 Xcode 版本 → xcresulttool 命令不匹配 | 视为通过 |
| 原生崩溃 / Dart 堆栈缺失 / XCUITest 崩溃 | 5-E | 获取 a11y 树；若树无法解释则 STOP | 推测性代码修改 |

---

### Section 3 — 关键区分规则（信号表之后，详细块之前）

一个加粗的突出框或 blockquote，包含：

**5-B vs 5-C 的决定性区分：**
- 5-B 抛出 `TimeoutException`、`WaitUntilVisibleTimeoutException` 或 `WaitUntilExistsTimeoutException`
- 5-C 抛出 `TestFailure`，带有 `Expected:` / `Actual:` 配对
- 检查第一个堆栈帧中的异常类名 — 这是决定性信号，而非错误消息内容

---

### Section 4 — Per-Category 详细块（每类一节）

#### 4-A: Category 5-A — Build Failure

**What it is:** 编译或 Xcode 构建步骤在任何测试运行之前失败。未向 `.test-results/latest.json` 写入测试结果 JSON。

**区分信号：** 未生成 `latest.json`，或 `latest.json` 存在但 `total == 0`。

**xcodebuild code-65 子类别表（必须包含所有 5 行）：**

| Code-65 子原因 | 日志片段 | 修复方法 |
|--------------|---------|---------|
| 模拟器未启动 | `Unable to find a device matching the provided destination specifier` | 预启动：`xcrun simctl boot <UDID> \|\| true`；轮询直到 "Booted" |
| 端口冲突 8081/8082 | `Test runner never began executing tests after launching` | `patrol test --test-server-port 8096 --app-server-port 8095` |
| CocoaPods 过期 | `No podspec found` / 依赖解析错误 | `cd ios && rm -rf Pods Podfile.lock && pod install` |
| Deployment target 不匹配 | `Compiling for iOS X.Y, but module was built for iOS A.B` | 在 Podfile post-install hook 中对齐 `IPHONEOS_DEPLOYMENT_TARGET` |
| Xcode/macOS 版本不兼容 | 应用在启动画面崩溃 | 更新 Xcode；清除 DerivedData：`rm -rf ~/Library/Developer/Xcode/DerivedData` |

**xcresulttool 诊断命令（Xcode 16+ / Xcode 26.x，逐字写入代码块）：**

```bash
# Xcode 16+（含 Xcode 26.x）：使用 get test-results 子命令
# 不得使用旧形式：xcrun xcresulttool get --format json --path <path>
# 该形式已弃用；不带 --legacy 会报错。

# 快速摘要（triage 最有用）
xcrun xcresulttool get test-results summary \
  --path /path/to/TestResults.xcresult \
  --compact

# 所有测试（通过/失败结构）
xcrun xcresulttool get test-results tests \
  --path /path/to/TestResults.xcresult \
  --compact

# 特定测试的详细失败信息
xcrun xcresulttool get test-results test-details \
  --path /path/to/TestResults.xcresult \
  --test-id "RunnerUITests/ExampleTest/testSomeFeature()" \
  --compact

# 活动日志（逐步操作跟踪）
xcrun xcresulttool get test-results activities \
  --path /path/to/TestResults.xcresult \
  --test-id "RunnerUITests/ExampleTest/testSomeFeature()" \
  --compact

# 运行时检查 JSON 结构（若结构不清楚）
xcrun xcresulttool get test-results summary --schema
```

**允许的动作：** 修复 Xcode 项目配置、CocoaPods、Podfile、指定 file:line 的 Dart 代码。运行 `pod install`。仅在确认缓存过期时清除 DerivedData。

**禁止的动作：** 在构建干净之前碰测试代码或 app 逻辑。对任何其他类别运行 `flutter clean`。

**Loop phase:** 步骤 [2] Build — category 5-A

---

#### 4-B: Category 5-B — Test Timeout / Finder Failure

**What it is:** 测试已启动，但 Patrol 的 finder 或 pump 在等待 widget 或 UI 稳定时超时。

**决定性信号：** 异常类为 `TimeoutException`、`WaitUntilVisibleTimeoutException` 或 `WaitUntilExistsTimeoutException` — 而非 `TestFailure`。

**与 5-C 的关键区别（粗体显示）：**
- **5-B 抛出超时异常；5-C 抛出 `TestFailure` 并带有 `Expected:` / `Actual:` 配对。检查第一个堆栈帧中的异常类。**

**允许的动作：**
- 在 `PatrolTesterConfig` 中增加 `visibleTimeout`/`existsTimeout`
- 切换到 `SettlePolicy.trySettle`
- 在交互前添加 `scrollTo()`
- 在断言前添加 `waitUntilVisible()`
- 删除多余的 `IntegrationTestWidgetsFlutterBinding.ensureInitialized()` 调用

**禁止的动作：** 修改预期值。删除测试。使用 `patrol develop` 代替 `patrol test`。

**Loop phase:** 步骤 [5] Triage → 步骤 [6] Fix（修改测试配置，不修改 app 逻辑）

---

#### 4-C: Category 5-C — Assertion Failure

**What it is:** 测试运行到完成，但 `expect()` 求值为 false。App 行为与测试期望不符。

**决定性信号：** `TestFailure: Expected: <X> Actual: <Y>` — 始终在失败消息中有 `Expected:` 和 `Actual:` 配对。

**硬性规则（逐字重复）：**

> **绝不修改 `expect()` 的预期值以匹配有问题的 app 行为。断言是规格说明。修复 app 代码。**

**允许的动作：** 修复堆栈指示的 file:line 处的 app 端代码。修复 widget 渲染逻辑。修复生成错误值的状态管理。

**禁止的动作：** 修改 `expect()` 预期值。删除断言。放宽匹配器（`equals(5)` → `greaterThan(3)`）。

**Loop phase:** 步骤 [5] Triage → 步骤 [6] Fix（修改 app 代码，不修改测试）

---

#### 4-D: Category 5-D — Environment / Cache Failure

**What it is:** 失败在本地构建环境或缓存层，而非代码中。

**允许的动作（仅限这些）：**
- 重启模拟器
- 修复 PATH
- 仅限此类别运行 `flutter clean && flutter pub get`
- 运行 `xattr -cr` 处理签名问题
- 更新 CocoaPods
- 重新查询模拟器 UDID

**禁止的动作：** 修改任何 Dart/测试代码。对任何其他类别运行 `flutter clean`。

**Loop phase:** 步骤 [1] Prepare environment / 步骤 [6] Fix（仅环境层面）

---

#### 4-E: Category 5-E — Unknown — 强制 a11y 树步骤

**What it is:** 信号与 5-A 到 5-D 均不匹配，或信号冲突。

**强制首个动作（粗体）：**

> **必须首先：运行 `scripts/sim_snapshot.sh --tree` 获取 a11y 树快照。**

决策树：
1. 若树解释了状态 → 重新归类为 5-B 或 5-C，应用对应修复
2. 若仍不清楚 → 截图（`scripts/sim_snapshot.sh --screenshot`）
3. 若仍不清楚 → **STOP。向用户报告，包含树摘要和截图路径。不得进行推测性修复。**

**禁止的动作：** 在获取树之前进行任何推测性代码修改。跳过 a11y 树步骤直接截图。在用户确认前应用修复。

**Loop phase:** 步骤 [5] Triage（若归类失败则停止，不进入步骤 [6]）

---

以上为文档全部内容。确保整个文档可独立使用，不需要外部链接。
  </action>

  <verify>
    <automated>grep -c "5-A\|5-B\|5-C\|5-D\|5-E" reference/failure-triage.md | awk '{if($1>=20) print "PASS: found",$1,"category references"; else print "FAIL: only",$1,"category references"}'</automated>
    <automated>grep -q "TestFailure" reference/failure-triage.md && grep -q "TimeoutException" reference/failure-triage.md && echo "PASS: distinguishing signals present" || echo "FAIL: missing TimeoutException or TestFailure"</automated>
    <automated>grep -q "Total: 0" reference/failure-triage.md && echo "PASS: Total:0 rule present" || echo "FAIL: Total:0 rule missing"</automated>
    <automated>grep -q "get test-results summary" reference/failure-triage.md && echo "PASS: xcresulttool subcommand syntax present" || echo "FAIL: xcresulttool syntax missing"</automated>
    <automated>grep -q "Pre-Triage\|pre-triage\|Pre-triage" reference/failure-triage.md && echo "PASS: pre-triage section present" || echo "FAIL: pre-triage section missing"</automated>
    <automated>grep -q "sim_snapshot.sh" reference/failure-triage.md && echo "PASS: 5-E mandatory a11y tree step present" || echo "FAIL: 5-E a11y tree step missing"</automated>
    <automated>wc -l reference/failure-triage.md | awk '{if($1>=200) print "PASS: file has",$1,"lines"; else print "FAIL: file only has",$1,"lines (min 200)"}'</automated>
  </verify>

  <acceptance_criteria>
    - reference/failure-triage.md 存在且 >= 200 行
    - `grep -c "5-A\|5-B\|5-C\|5-D\|5-E"` 返回 >= 20（五个类别在全文中反复引用）
    - 文件同时包含字符串 `TestFailure` 和 `TimeoutException`（区分 5-B/5-C 的关键）
    - 文件包含字符串 `Total: 0`（静默失败规则）
    - 文件包含字符串 `get test-results summary`（Xcode 16+ 子命令语法）
    - 文件包含包含 `Pre-Triage` 或 `pre-triage` 的章节标题
    - 文件包含字符串 `sim_snapshot.sh`（5-E 强制步骤）
    - 文件包含 xcodebuild code-65 子类别表（5 行），可通过 `grep -c "Code-65\|code-65\|Simulator not booted\|Port conflict\|CocoaPods"` 验证 >= 3 行
    - 文件包含字符串 `절不修改.*expect\|绝不修改.*expect\|Never change.*expect`（5-C 硬性规则）（中英文均可）
    - 文件不包含 `$.native.pressRecentApps`（越界内容，属于 Phase 2）
  </acceptance_criteria>

  <done>
    reference/failure-triage.md 已创建，包含：
    (1) pre-triage 三项检查
    (2) 全部 24 行信号的快速参考表（四列）
    (3) 5-B vs 5-C 区分规则
    (4) 5-A 到 5-E 五个类别的详细块，每个块含允许/禁止动作和 loop phase 引用
    (5) 5-A 块中 code-65 子类别表（5 行）和 xcresulttool 代码示例（6 个命令）
    (6) 5-E 块中明确的 a11y 树强制步骤和决策树
  </done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| 文档内容 → agent 推理 | agent 将文档内容作为指令执行；错误内容会导致错误修复动作 |

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-01A-01 | Information Disclosure | failure-triage.md 中的文件路径示例 | accept | 路径为示例（`/path/to/`），非实际项目路径；风险可接受 |
| T-01A-02 | Tampering | 文档内容准确性 | mitigate | RESEARCH.md 和 CONTEXT.md 中的所有信号模式均经 Context7 和 CLI 验证；executor 应从已验证来源逐字写入内容 |
</threat_model>

<verification>
执行此 plan 后，验证：

1. `ls -la reference/failure-triage.md` — 文件存在
2. `wc -l reference/failure-triage.md` — 行数 >= 200
3. `grep "TestFailure\|TimeoutException\|5-A\|5-B\|5-C\|5-D\|5-E" reference/failure-triage.md | wc -l` — 返回 >= 20
4. `grep "get test-results summary" reference/failure-triage.md` — 找到 xcresulttool 子命令
5. `grep "Total: 0" reference/failure-triage.md` — 找到静默失败规则
6. `grep -i "pre-triage\|pre-triage" reference/failure-triage.md` — 找到 pre-triage 章节
</verification>

<success_criteria>
- reference/failure-triage.md 已创建，内容完整，可独立使用
- agent 可在不查阅外部文档的情况下，将任意失败信号分类为 5-A 到 5-E
- 所有 5 类别均有信号模式、允许/禁止动作
- xcresulttool Xcode 16+ 子命令语法逐字出现（可复制运行）
- 5-B vs 5-C 区分规则明确标注（TimeoutException vs TestFailure）
- pre-triage 检查明确：xcresulttool 空输出 → 5-D，total==0 → 5-A
</success_criteria>

<output>
完成后，创建 `.planning/phases/01-reference-documentation/01-A-SUMMARY.md`

包含：
- 创建了哪个文件（路径和行数）
- 文档的关键结构节点
- 任何偏离计划的内容（如有）
</output>
