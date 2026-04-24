---
phase: 01-reference-documentation
plan: C
type: execute
wave: 1
depends_on: []
files_modified:
  - reference/troubleshooting.md
autonomous: true
requirements:
  - REF-03

must_haves:
  truths:
    - "Agent 可通过跟随 troubleshooting.md 的分步说明，解决 iOS/CocoaPods/签名/xcresulttool 的常见故障，无需查阅外部文档"
    - "至少 10 个问题按出现频率排序（最常见在前）"
    - "每个问题均有 Symptom、Cause、编号修复步骤和 Loop Phase 映射"
    - "patrol doctor 命令明确记录为首次运行诊断"
    - "xcodebuild exit code 65 覆盖全部 5 个子原因及对应修复步骤"
    - "xcresulttool 弃用问题（Xcode 16+）有精确的版本检测和新命令语法"
    - "PatrolIntegrationTestBinding 双重初始化问题有明确的修复步骤"
    - "每个修复步骤映射到迭代协议阶段（[1]、[2]、[5] 等）"
  artifacts:
    - path: "reference/troubleshooting.md"
      provides: "iOS/Xcode/CocoaPods 常见故障症状→原因→修复步骤查找文档"
      min_lines: 250
      contains: "patrol doctor"
  key_links:
    - from: "reference/troubleshooting.md"
      to: "reference/iteration-protocol.md"
      via: "每个问题的 Loop Phase 字段引用 [1]–[7] 阶段编号"
      pattern: "\\[1\\]|\\[2\\]|\\[5\\]"
    - from: "reference/troubleshooting.md"
      to: "reference/failure-triage.md"
      via: "每个修复类别映射到 5-A/5-D 等"
      pattern: "5-A|5-D"
---

<objective>
创建 reference/troubleshooting.md — agent 在处理类别 5-A（构建失败）和 5-D（环境/缓存失败）时的逐步修复查找文档。

Purpose: 此文档阻止 agent 对错误类别执行不知情的操作（例如，对签名错误运行 `flutter clean`，或重建而不先诊断 code-65 子原因）。每个问题的修复步骤是有序的，按最可能成功的顺序排列。

Output: reference/troubleshooting.md，格式为 Symptom → Cause → Fix Steps（编号）→ Loop Phase，按频率排序，涵盖至少 10 个常见 iOS/Xcode/CocoaPods 故障模式。
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
  <name>Task C-1: 创建 reference/troubleshooting.md（完整内容）</name>
  <files>reference/troubleshooting.md</files>

  <read_first>
    - .planning/phases/01-reference-documentation/01-RESEARCH.md — "DOC 3" 小节：所有 11 个问题的逐字内容规范（症状、原因、修复步骤、Loop phase）
    - reference/iteration-protocol.md — 循环阶段编号 [0]–[7]，用于每个问题的 "Loop phase" 字段
    - .planning/phases/01-reference-documentation/01-CONTEXT.md — 锁定决策：Symptom→Cause→Fix numbered steps 格式，按频率排序，每个修复映射到迭代协议阶段
  </read_first>

  <action>
创建 reference/troubleshooting.md，内容必须完全符合以下结构规范。所有修复步骤均以 RESEARCH.md 中验证过的内容为准，逐字写入。

---

## 文档结构（按顺序）

### 标题与用途说明

标题：`# iOS Troubleshooting Reference`

说明：
- 本文档在迭代循环步骤 [6] Fix 中使用，用于类别 5-A（构建失败）和 5-D（环境/缓存失败）
- 按频率排序 — 先检查最上面的问题
- 每个修复步骤按顺序执行 — 不要跳过
- 每个问题末尾的 Loop Phase 字段说明此修复在循环中何处执行

---

### 首次运行诊断（放在所有问题之前）

标题：`## 首次运行：patrol doctor`

内容：

始终在新项目 session 开始时运行 `patrol doctor`。它检查：
- patrol_cli 版本
- Xcode 和 xcode-select 配置
- iOS 模拟器可用性
- Flutter SDK 版本
- CocoaPods 安装
- RunnerUITests 目标是否存在

```bash
patrol doctor
```

如果 `patrol doctor` 失败，在尝试任何构建/测试之前修复这些问题。

---

### 问题列表（按频率排序，共 11 个）

每个问题使用以下格式：

```
### Issue N — [标题]

**Symptom（症状）：** [描述]

**Cause（原因）：** [解释]

**Fix Steps（修复步骤）：**
1. [步骤 1]
2. [步骤 2]
...

**Loop Phase：** [N] [步骤名称] — category [5-X]
```

---

#### Issue 1 — xcodebuild Exit Code 65（最常见）

**Symptom：** `patrol build ios --simulator` 失败，报 `xcodebuild exited with code 65`

**Cause：** 覆盖 5 种不同子原因的笼统错误；仅凭退出码无法判断。

**Fix Steps：**
1. 从 xcodebuild 日志中提取第一个有意义的错误行（而非仅看退出码）
2. 如果是 `Unable to find a device matching the provided destination specifier` → 模拟器未启动；运行 `xcrun simctl boot <UDID>` 并轮询直到 "Booted"
3. 如果是 `Test runner never began executing tests after launching` → 端口冲突在 8081/8082；运行 `patrol test --test-server-port 8096 --app-server-port 8095`；用 `sudo lsof -i -P | grep LISTEN | grep :8081` 确认
4. 如果是 `No podspec found` 或依赖解析错误 → `cd ios && rm -rf Pods Podfile.lock && pod install`
5. 如果是 `Compiling for iOS X.Y, but module was built for iOS A.B` → 在 Podfile post-install hook 中对齐所有目标的 `IPHONEOS_DEPLOYMENT_TARGET`
6. 如果没有明确的子信号 → 清除 DerivedData：`rm -rf ~/Library/Developer/Xcode/DerivedData`；重试构建

**Loop Phase：** [2] Build → category 5-A

---

#### Issue 2 — 模拟器未启动 / 启动竞态条件

**Symptom：** 构建或安装似乎成功，但测试 runner 在 "Waiting for app to start…" 处挂起，或报 "Could not find simulator"

**Cause：** `xcrun simctl boot` 是异步的。它在模拟器继续启动时立即返回。Patrol/xcodebuild 在模拟器就绪之前启动。

**Fix Steps：**
1. `xcrun simctl boot <UDID> 2>/dev/null || true`（容忍 "already booted"）
2. 轮询：`until xcrun simctl list devices | grep "$UDID" | grep -q "Booted"; do sleep 1; done`
3. 验证：`xcrun simctl list devices | grep "$UDID"` 应显示 `(Booted)`
4. 仅在此之后运行构建/测试

**Loop Phase：** [1] Prepare environment

---

#### Issue 3 — CocoaPods 版本冲突

**Symptom：** `CocoaPods could not find compatible versions for pod 'X'`；或构建以提到 pod 名称的链接器错误失败

**Cause：** 更新 `pubspec.yaml` 插件后 `Podfile.lock` 过期；或长期未更新后本地 pod spec 库过期。

**Fix Steps（按顺序 — 不要跳过）：**
1. `flutter pub get`（重新生成 iOS plugin registrant — 必须先运行）
2. `cd ios && pod install`（通常够用）
3. 如失败：`pod install --repo-update`
4. 如失败：`rm -rf Pods Podfile.lock && pod install`
5. 如失败：`pod cache clean --all && pod repo update && pod install`
6. **绝不**不带特定 pod 名称运行 `pod update` — 会将所有 pods 更新到最新版本，可能引入破坏性变更

**Loop Phase：** [2] Build → category 5-A

---

#### Issue 4 — xcresulttool 命令已弃用（Xcode 16+）

**Symptom：** `parse_failure.py` 返回 `{}` 或 null `failures` 数组；日志包含 "This command is deprecated"；所有失败被归类为 5-E

**Cause：** `xcrun xcresulttool get --format json --path <path>`（旧的 "get object" 子命令）在 Xcode 16 中已弃用，需要 `--legacy` 标志。没有它，工具要么报错要么返回空输出。

**Fix Steps：**
1. 检查 Xcode 版本：`xcodebuild -version | head -1`
2. 检查 xcresulttool 版本：`xcrun xcresulttool --version`（版本 >= 23000 = Xcode 16+）
3. 对于 Xcode 16+（含 Xcode 26.x）：使用 `get test-results` 子命令：
   ```bash
   xcrun xcresulttool get test-results summary --path <path> --compact
   ```
4. 如果必须临时使用旧形式：`xcrun xcresulttool get --legacy --path <path> --format json`
5. 更新 `parse_failure.py` 以检测 Xcode 版本并相应分支

**验证：** `xcrun xcresulttool get test-results summary --path <xcresult> --compact` 应返回包含 `totalTestCount`、`passedTests`、`failedTests` 字段的 JSON。

**Loop Phase：** [5] Triage — 如果损坏则完全阻止 triage；在任何其他诊断之前修复

---

#### Issue 5 — PatrolIntegrationTestBinding 双重初始化

**Symptom：** 测试启动时崩溃 `"Binding is already initialized to IntegrationTestWidgetsFlutterBinding"`；零测试执行

**Cause：** 测试文件（或辅助文件）调用 `IntegrationTestWidgetsFlutterBinding.ensureInitialized()`，与 Patrol 自己的 binding 冲突。Patrol 2.x+ 自动初始化 `PatrolBinding` — 第二个初始化调用是致命的。

也由以下触发：通过 VSCode 内置测试 runner（play 按钮）运行 Patrol 测试，它调用 Flutter 的 integration_test runner 而非 Patrol CLI。

**Fix Steps：**
1. 从所有 Patrol 测试文件中删除 `IntegrationTestWidgetsFlutterBinding.ensureInitialized()`
2. 从 Patrol 测试的 `setUp`/`setUpAll` 中删除 `WidgetsFlutterBinding.ensureInitialized()`
3. 不要在 Patrol 测试文件中修改 `FlutterError.onError`
4. 只通过 `patrol test` 运行测试，绝不通过 `flutter test integration_test/`

**Loop Phase：** [2]/[3] — category 5-A（配置失败，非 app 逻辑）

---

#### Issue 6 — 模拟器构建的代码签名错误

**Symptom：** `patrol build ios --simulator` 因签名错误失败；`No signing certificate 'iOS Development' found`；或 Xcode 日志显示 `RunnerUITests.xctest` 签名步骤失败

**Cause：** `RunnerUITests` 目标可能显式设置了 `CODE_SIGNING_REQUIRED = YES`，覆盖了模拟器默认值。或者启用了需要真实签名的 entitlements（推送通知、App Groups），即使对于模拟器也是如此。

**Fix Steps：**
1. 在 Xcode 项目设置的 `RunnerUITests` 目标 → Build Settings 中确认：
   - `CODE_SIGNING_REQUIRED = NO`（对于模拟器配置）
   - `CODE_SIGNING_ALLOWED = NO`（对于模拟器配置）
   - `CODE_SIGN_IDENTITY = ""`（空字符串，非 "iPhone Developer"）
2. 删除模拟器中无法使用的 entitlements（如推送通知 entitlement）
3. 验证自动签名对 `Runner` 和 `RunnerUITests` 目标均一致配置
4. 更改后：`cd ios && pod install && cd ..`；然后重试构建

**Loop Phase：** [2] Build → category 5-A

---

#### Issue 7 — "Total: 0 Tests" 静默失败

**Symptom：** `patrol test` 以 0 退出（成功），但摘要显示 `Total: 0`；无测试输出

**Causes（原因）：**
1. 错误的 `--target` 路径（目录而非文件，或拼写错误）
2. 测试文件使用 `testWidgets()` 而非 `patrolTest()`
3. 导致测试发现失败的依赖冲突（Patrol issue #2573）

**Fix Steps：**
1. 验证 `--target` 指向特定的 `.dart` 文件，而非目录
2. 检查测试文件：必须使用 `patrolTest(...)`，而非 `testWidgets(...)`
3. 运行 `patrol doctor` 检查整体环境
4. 如果最近添加了依赖：`flutter pub get && cd ios && pod install`
5. 使用 `--verbose` 标志运行以查看测试发现输出：`patrol test --target <file> --verbose`

**Loop Phase：** [4] Decide — 将 `total == 0` 视为 5-A 失败，而非成功

---

#### Issue 8 — 模拟器上的旧 App 二进制文件

**Symptom：** 测试对新代码中存在的 UI 报 "widget not found" 错误；模拟器中显示的 app 版本与 `pubspec.yaml` 不匹配

**Cause：** `xcrun simctl install` 在 bundle ID 或 entitlements 冲突时可能静默失败替换 app。旧二进制文件仍然安装。

**Fix Steps：**
1. 每次安装前显式卸载：
   ```bash
   xcrun simctl uninstall booted <bundle_id> 2>/dev/null || true
   xcrun simctl install booted /path/to/Runner.app
   ```
2. 验证已安装版本：在模拟器上启动 app 并检查关于页面
3. 如果安装反复失败：`xcrun simctl erase <UDID>`（模拟器恢复出厂设置）— 最后手段

**Loop Phase：** [2] Build & install

---

#### Issue 9 — Apple Silicon 上的 arm64 架构不匹配

**Symptom：** 构建失败，报 `building for iOS Simulator-arm64 but attempting to link with file built for iOS Simulator-x86_64`；仅在 M1/M2/M3 Mac 上

**Cause：** CocoaPod 只捆绑了一种架构切片。

**Fix：** 在 `ios/Podfile` 底部添加：
```ruby
post_install do |installer|
  installer.pods_project.build_configurations.each do |config|
    config.build_settings['EXCLUDED_ARCHS[sdk=iphonesimulator*]'] = 'arm64'
  end
end
```
然后 `cd ios && pod install`。

**Loop Phase：** [2] Build → category 5-A

---

#### Issue 10 — DerivedData 缓存过期

**Symptom：** 神秘的 Xcode 错误：`Session.modulevalidation`、指向 `.dart_tool/` 或 `build/` 的 `no such file or directory`；`Module compiled with Swift X.Y cannot be imported by Swift A.B`

**Cause：** Xcode DerivedData 中的预编译模块过期。

**Fix：** `rm -rf ~/Library/Developer/Xcode/DerivedData` 然后重试构建。

仅在**同时**看到过期的 Flutter 构建产物（`.dart_tool/`、`build/` 问题）时运行 `flutter clean`。**不要**对每次构建失败都运行 `flutter clean`。

**Loop Phase：** [2] Build → category 5-D（环境/缓存），而非 5-A

---

#### Issue 11 — `com.apple.provenance` xattr 签名错误

**Symptom：** 构建失败，报 `xattr: [Errno 1] Operation not permitted: 'Flutter.framework'` 或 `com.apple.provenance` 相关的签名错误

**Cause：** 从外部来源下载的 Flutter.framework 具有隔离 xattr，阻止签名步骤。

**Fix Steps：**
1. 找到 Flutter.framework 位置（通常在 `build/` 或 Flutter SDK 安装中）
2. 清除 xattr：`xattr -cr /path/to/Flutter.framework`
3. 对整个项目 build 目录运行：`xattr -cr build/`
4. 重试构建

**Loop Phase：** [2] Build → category 5-D（环境修复，非代码修改）

---

### 快速参考：不要做什么

标题：`## 常见错误操作 — 禁止清单`

以表格形式写出以下常见错误操作：

| 错误操作 | 原因不对 | 正确做法 |
|---------|---------|---------|
| 对每次构建失败都运行 `flutter clean` | 仅限 5-D（缓存过期）；其他情况会浪费 30-60 秒 | 仅在 DerivedData 或 `.dart_tool/` 问题时使用 |
| 不诊断就重建 | code-65 下有 5 种子原因；盲目重试浪费时间 | 先提取具体错误行，匹配子原因表 |
| 不带 pod 名称运行 `pod update` | 更新所有 pods 到最新，可能引入破坏性变更 | `pod install`，若失败再 `pod install --repo-update` |
| 在 5-A 或 5-C 中修改 Dart/测试代码 | 问题在环境/配置层，非代码层 | 先清理环境，再考虑代码 |
| 在没有先获取 a11y 树的情况下对 5-E 进行推测性修复 | 5-E 是"未知"— 没有树就没有诊断依据 | 先运行 `scripts/sim_snapshot.sh --tree` |
| 跳过 `flutter pub get` 直接运行 `pod install` | `flutter pub get` 先重新生成 iOS plugin registrant | 始终按顺序：先 `flutter pub get`，再 `pod install` |

---

以上为文档全部内容。确保所有修复步骤均按可执行顺序排列，整个文档可独立使用。
  </action>

  <verify>
    <automated>grep -q "patrol doctor" reference/troubleshooting.md && echo "PASS: patrol doctor command present" || echo "FAIL: patrol doctor missing"</automated>
    <automated>grep -c "Issue [0-9]" reference/troubleshooting.md | awk '{if($1>=10) print "PASS: found",$1,"issues"; else print "FAIL: only",$1,"issues (need >=10)"}'</automated>
    <automated>grep -q "Loop Phase" reference/troubleshooting.md && echo "PASS: Loop Phase field present" || echo "FAIL: Loop Phase field missing"</automated>
    <automated>grep -q "xcresulttool.*deprecated\|deprecated.*xcresulttool\|Xcode 16\+" reference/troubleshooting.md && echo "PASS: xcresulttool deprecation issue present" || echo "FAIL: xcresulttool deprecation issue missing"</automated>
    <automated>grep -q "PatrolIntegrationTestBinding\|IntegrationTestWidgetsFlutterBinding" reference/troubleshooting.md && echo "PASS: binding double-init issue present" || echo "FAIL: binding issue missing"</automated>
    <automated>grep -q "Total: 0\|Total: 0 Tests\|total == 0" reference/troubleshooting.md && echo "PASS: Total:0 silent failure issue present" || echo "FAIL: Total:0 issue missing"</automated>
    <automated>grep -c "5-A\|5-D" reference/troubleshooting.md | awk '{if($1>=8) print "PASS: found",$1,"category references"; else print "FAIL: only",$1,"category references (need >=8)"}'</automated>
    <automated>wc -l reference/troubleshooting.md | awk '{if($1>=250) print "PASS: file has",$1,"lines"; else print "FAIL: file only has",$1,"lines (min 250)"}'</automated>
  </verify>

  <acceptance_criteria>
    - reference/troubleshooting.md 存在且 >= 250 行
    - `grep "patrol doctor" reference/troubleshooting.md` 返回至少 1 行（首次运行诊断命令）
    - `grep -c "Issue [0-9]"` 返回 >= 10（至少 10 个问题条目）
    - 所有问题条目均包含字符串 `Loop Phase`（迭代协议阶段映射）
    - Issue 1 包含 xcodebuild exit code 65 的 5 个子原因诊断步骤
    - Issue 4 包含 xcresulttool 弃用检测和新 `get test-results summary` 命令语法
    - Issue 5 包含 PatrolIntegrationTestBinding 修复（删除 `ensureInitialized()` 调用）
    - Issue 7 包含 `Total: 0` 静默失败检测
    - `grep "5-A\|5-D" reference/troubleshooting.md | wc -l` 返回 >= 8（分类引用贯穿全文）
    - 文件不包含 `flutter clean` 作为通用修复建议（仅在 5-D/DerivedData 上下文中使用）
    - 每个问题包含编号的修复步骤（Symptom → Cause → Fix Steps 格式）
  </acceptance_criteria>

  <done>
    reference/troubleshooting.md 已创建，包含：
    (1) 首次运行 `patrol doctor` 诊断章节（放在所有问题之前）
    (2) 11 个问题按频率排序（最常见在前）
    (3) 每个问题有 Symptom、Cause、编号 Fix Steps 和 Loop Phase 映射
    (4) Issue 1 覆盖 xcodebuild code-65 的全部 5 个子原因
    (5) Issue 4 覆盖 xcresulttool 弃用及 Xcode 16+ 新命令语法
    (6) Issue 5 覆盖 PatrolIntegrationTestBinding 双重初始化
    (7) Issue 7 覆盖 Total:0 静默失败
    (8) 常见错误操作禁止清单
  </done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| 修复命令 → shell 执行 | agent 将文档中的 bash 命令直接执行；错误命令可能破坏项目状态 |

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-01C-01 | Tampering | 修复步骤中的破坏性命令（`xcrun simctl erase`、`rm -rf Pods`）| mitigate | 破坏性命令在文档中标注为 "最后手段"（last resort）并说明前置条件，executor 应逐字复制此说明 |
| T-01C-02 | Elevation of Privilege | `sudo lsof` 命令要求提升权限 | accept | 该命令仅用于诊断（查看端口），不修改系统状态；仅在 port conflict 子诊断步骤中使用 |
| T-01C-03 | Information Disclosure | 文档中的文件路径和 bundle ID 示例 | accept | 所有路径为示例（`/path/to/`，`com.example.app`），非真实项目凭据 |
</threat_model>

<verification>
执行此 plan 后，验证：

1. `ls -la reference/troubleshooting.md` — 文件存在
2. `wc -l reference/troubleshooting.md` — 行数 >= 250
3. `grep "patrol doctor" reference/troubleshooting.md` — 找到首次运行诊断命令
4. `grep -c "Issue [0-9]" reference/troubleshooting.md` — 返回 >= 10
5. `grep "Loop Phase" reference/troubleshooting.md | wc -l` — 返回 >= 10（每个问题一个）
6. `grep "5-A\|5-D" reference/troubleshooting.md | wc -l` — 返回 >= 8
7. `grep "xcresulttool\|get test-results" reference/troubleshooting.md` — 找到 xcresulttool 弃用问题
</verification>

<success_criteria>
- reference/troubleshooting.md 已创建，内容完整，可独立使用
- agent 可跟随分步说明解决常见 iOS/Xcode/CocoaPods 故障，无需查阅外部文档
- 至少 10 个问题按频率排序
- 每个问题均有 Symptom → Cause → Fix Steps（编号）→ Loop Phase 格式
- patrol doctor 明确记录为首次运行诊断
- xcodebuild exit code 65 的 5 个子原因均有对应修复步骤
- xcresulttool 弃用问题有精确的版本检测和新命令语法
- PatrolIntegrationTestBinding 双重初始化有明确的删除步骤
</success_criteria>

<output>
完成后，创建 `.planning/phases/01-reference-documentation/01-C-SUMMARY.md`

包含：
- 创建了哪个文件（路径和行数）
- 覆盖的问题列表（Issue 1–11 的标题）
- 任何偏离计划的内容（如有）
</output>
