---
phase: 01-reference-documentation
plan: B
type: execute
wave: 1
depends_on: []
files_modified:
  - reference/patrol-patterns.md
autonomous: true
requirements:
  - REF-02

must_haves:
  truths:
    - "Agent 可仅用 patrol-patterns.md 生成或修复 Patrol 4.x 测试代码，无需依赖训练数据或外部文档"
    - "所有 6 种 finder 参数类型（String、RegExp、Type、Symbol、Key、IconData）均有代码示例"
    - "全部 3 个 SettlePolicy 值均记录，含何时使用指南，trySettle 标注为推荐默认值"
    - "$.native 和 $.platform.mobile 两种别名均展示"
    - "chained finders（containing()）、.at(n)、.first、.last、.which<T>() 均有示例"
    - "anti-patterns 章节涵盖最常见的 agent 错误（setUp vs patrolSetUp、SettlePolicy.settle 作为默认值等）"
    - "patrolSetUp/patrolTearDown 与 setUp/tearDown 的区别明确说明"
  artifacts:
    - path: "reference/patrol-patterns.md"
      provides: "Patrol 4.x 完整语法速查表"
      min_lines: 250
      contains: "SettlePolicy"
  key_links:
    - from: "reference/patrol-patterns.md"
      to: "reference/iteration-protocol.md"
      via: "read at loop steps [0] (generate test) and [6] (fix test)"
      pattern: "patrolTest|patrolSetUp|SettlePolicy"
---

<objective>
创建 reference/patrol-patterns.md — agent 生成和修复 Patrol 4.x 测试代码时的语法速查文档。

Purpose: Patrol 的 `$` API 在训练数据中覆盖不足，agent 经常生成不存在的 API（如 `find.byText()` 而非 `$('text')`）或遗漏 `$.platform.mobile` 等 Patrol 4.x 命名。此文档作为代码生成的唯一 grounding 文档。

Output: reference/patrol-patterns.md，按概念组织：Imports → Test Structure → Finders → Chained Finders → Interactions → Assertions → SettlePolicy → Native/Platform → Pump/Settle → Anti-patterns。
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
  <name>Task B-1: 创建 reference/patrol-patterns.md（完整内容）</name>
  <files>reference/patrol-patterns.md</files>

  <read_first>
    - .planning/phases/01-reference-documentation/01-RESEARCH.md — "DOC 2" 小节：所有章节（Section 1–12）的逐字代码示例和说明规范
    - .planning/phases/01-reference-documentation/01-CONTEXT.md — 锁定决策：概念组织顺序（Finders→Interactions→Assertions→Pump/Settle）、两种别名要求、SettlePolicy 全值要求
  </read_first>

  <action>
创建 reference/patrol-patterns.md，内容必须完全符合以下结构规范。所有代码块均以 RESEARCH.md 中验证过的 Context7 内容为准，逐字写入。

---

## 文档结构（按顺序）

### 标题与用途说明

标题：`# Patrol 4.x Patterns Cheatsheet`

说明：本文档在迭代循环步骤 [0]（生成测试）和步骤 [6]（修复测试）时使用。所有示例均为 Patrol 4.x 语法。

---

### Section 1 — Imports

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';
```

说明：widget-only 测试（无需原生自动化）使用 `patrolWidgetTest()`，imports 相同。

---

### Section 2 — Test Structure（完整的 patrolTest 骨架）

包含以下注意事项（作为注释或说明文字，紧贴代码块）：

```dart
void main() {
  patrolSetUp(() async {
    // 在此文件中每个 patrolTest 之前运行
    // 用于：清除 shared prefs、重置 auth 状态
    // 注意：不是 setUp() — vanilla setUp() 不与 Patrol 的原生生命周期集成
  });

  patrolTearDown(() async {
    // 在每个 patrolTest 之后运行
    // 注意：不是 tearDown()
  });

  group('FeatureName', () {
    patrolTest(
      'description: user can X and should see Y',
      config: const PatrolTesterConfig(
        existsTimeout: Duration(seconds: 10),
        visibleTimeout: Duration(seconds: 10),
        settleTimeout: Duration(seconds: 10),
        settlePolicy: SettlePolicy.trySettle,  // 推荐默认值
        dragDuration: Duration(milliseconds: 100),
        settleBetweenScrollsTimeout: Duration(seconds: 5),
        printLogs: true,
      ),
      ($) async {
        // 1. initApp() 在 pumpWidgetAndSettle 之前 — 顺序至关重要
        // initApp();   // 若项目有测试模式初始化器则取消注释

        // 2. 泵入 widget 树
        await $.pumpWidgetAndSettle(const MyApp());

        // 3. 测试步骤
        // 4. 断言
      },
    );
  });
}
```

关键说明（作为注意事项列表，在代码块之后）：
- `patrolSetUp`/`patrolTearDown` — 不是 `setUp`/`tearDown`。Vanilla 版本不与 Patrol 的原生自动化生命周期集成。
- `initApp()` 必须在 `pumpWidgetAndSettle` 之前调用，而非之后。
- Patrol 4.0 从 `patrolTest()` 中删除了 `bindingType` 和 `nativeAutomation` 参数。不要包含它们。
- 当不需要原生自动化时，使用 `patrolWidgetTest()`（而非 `patrolTest()`）。

---

### Section 3 — Finder 类型（$() 的所有参数类型）

标题：`## Finders — $() 参数类型`

说明：`$()` 可调用对象创建一个 `PatrolFinder`。支持以下参数类型：

```dart
// 精确文本匹配（String）
$('Log in')
$('Subscribe')

// 文本模式匹配（RegExp）
$(RegExp(r'Welcome.*'))
$(RegExp(r'^\d+ items?$'))

// widget 类型匹配（Type）
$(TextField)
$(ElevatedButton)
$(ListView)
$(Scaffold)

// Symbol key — 推荐，无需 Key() 包装
$(#submitButton)    // 等同于 $(const Key('submitButton'))
$(#emailInput)

// 显式 Key 对象
$(const Key('my-button'))
$(Key('dynamic-$id'))

// IconData
$(Icons.add)
$(Icons.close)
$(Icons.arrow_back)

// Semantics label — 使用 find.bySemanticsLabel()
$(find.bySemanticsLabel('Edit profile'))
```

---

### Section 4 — 链式 Finder（containing()）

标题：`## Chained Finders`

```dart
// 在特定 widget 类型内查找文本
await $(ListView).$('Subscribe').tap();
await $(ListView).$(ListTile).$('Subscribe').tap();

// 多级链式
await $(Scaffold).$(#box1).$('Log in').tap();

// containing() — 查找包含匹配后代的父 widget
await $(ListTile).containing('Activated').$(#learnMore).tap();

// 多个 containing() 过滤器 — 父 widget 必须包含所有后代
await $(Scrollable).containing(ElevatedButton).containing(Text).tap();

// 嵌套 containing
await $(Scrollable).containing($(TextButton).$(Text)).tap();
```

---

### Section 5 — 索引选择

标题：`## Index Selection — .at(n) / .first / .last`

```dart
await $(TextButton).at(2).tap();    // 第三个匹配项（0 索引）
await $(TextButton).first.tap();    // 第一个匹配项
await $(TextButton).last.tap();     // 最后一个匹配项
```

---

### Section 6 — 谓词过滤（.which()）

标题：`## Predicate Filter — .which<T>()`

```dart
await $(ElevatedButton)
    .which<ElevatedButton>((btn) => btn.enabled)
    .tap();
```

---

### Section 7 — 交互方法

标题：`## Interactions`

```dart
// tap — 在操作前等待可见（与 tester.tap 不同）
await $(#loginButton).tap();
await $(#button).tap(
  settlePolicy: SettlePolicy.noSettle,
  visibleTimeout: Duration(seconds: 5),
  settleTimeout: Duration(seconds: 3),
);

// 长按
await $(#contextMenuTarget).longPress();

// 输入文本 — 先清空字段
await $(#emailField).enterText('user@example.com');
await $(#passwordInput).enterText('secret',
  settlePolicy: SettlePolicy.trySettle);

// 滚动直到 widget 出现
await $('Delete account').scrollTo().tap();   // 滚动然后点击
await $('Subscribe').scrollTo();              // 仅滚动
await $(#bottomItem).scrollTo(
  view: find.byType(ListView),
  scrollDirection: AxisDirection.down,
  maxScrolls: 20,
);

// 等待 widget 在树中存在（不一定可见）
await $(#loadingIndicator).waitUntilExists();

// 等待 widget 可见且可点击
await $(#contentLoaded).waitUntilVisible();
await $(#contentLoaded).waitUntilVisible(timeout: Duration(seconds: 15));

// 获取 Text widget 的文本
final label = $(#welcomeMessage).text;
```

---

### Section 8 — 断言

标题：`## Assertions`

```dart
// 标准 flutter_test matchers 与 $ finders 配合使用
expect($('Log in'), findsOneWidget);
expect($('Log in'), findsNothing);
expect($(Card), findsNWidgets(3));
expect($(Card), findsWidgets);     // 一个或多个

// .exists — 非阻塞布尔值，无超时
expect($(#myWidget).exists, isTrue);
expect($('Error').exists, isFalse);

// .visible — 检查 hit-testability（不仅仅是树中存在）
expect($('Log in').visible, equals(true));
expect($('Log in').visible, isTrue);
```

---

### Section 9 — SettlePolicy：全部 3 个值和使用时机

标题：`## SettlePolicy — All Values`

SettlePolicy 是一个枚举，恰好有 **3 个值**：

| 值 | 映射到 | 使用时机 |
|----|--------|---------|
| `SettlePolicy.settle` | `pumpAndSettle()` | 仅限有限动画；若超时后仍有帧待处理则**抛出异常**。当需要保证完全稳定状态时使用。 |
| `SettlePolicy.trySettle` | `pumpAndTrySettle()` | **推荐默认值。** 在 settleTimeout 内泵入帧，之后即使帧仍待处理也不抛出异常继续。适用于有限和无限动画（如 `CircularProgressIndicator`、Lottie）。 |
| `SettlePolicy.noSettle` | `pump()` | 仅单帧泵入。当动画**必须继续**时使用（例如，需要观察进行中的动画状态）。 |

注意：patrol_finders v2 中默认值已更改为 `SettlePolicy.trySettle`。模板默认值应为 `SettlePolicy.trySettle`。

```dart
// 全局配置
config: const PatrolTesterConfig(
  settlePolicy: SettlePolicy.trySettle,  // 推荐模板默认值
)

// 单次操作覆盖
await $(#animatedButton).tap(settlePolicy: SettlePolicy.noSettle);
await $(#form).tap(settlePolicy: SettlePolicy.settle);
```

---

### Section 10 — 原生/平台自动化

标题：`## Native / Platform Automation — $.platform.mobile vs $.native`

说明段：Patrol 4.0 中 `$.platform.mobile` 是规范 API。`$.native` 是旧别名 — 两者都有效。展示两种形式，因为现有测试使用 `$.native`。

```dart
// --- 权限 ---
// 始终用 isPermissionDialogVisible() 守护，以处理已授权权限的重新运行
if (await $.platform.mobile.isPermissionDialogVisible()) {
  await $.platform.mobile.grantPermissionWhenInUse();
  // 或：await $.platform.mobile.grantPermissionOnlyThisTime();
  // 或：await $.platform.mobile.denyPermission();
}
await $.platform.mobile.selectFineLocation();  // 精确位置

// --- 通知 ---
await $.platform.mobile.openNotifications();
final notifications = await $.platform.mobile.getNotifications();
await $.platform.mobile.tapOnNotificationByIndex(0);
await $.platform.mobile.tapOnNotificationBySelector(
  Selector(textContains: 'New message'),
  timeout: Duration(seconds: 5),
);
await $.platform.mobile.closeNotifications();

// --- 导航 ---
await $.platform.mobile.pressHome();
await $.platform.mobile.openApp(appId: 'com.example.app');
await $.platform.mobile.openUrl('https://example.com');

// --- 系统切换 ---
await $.platform.mobile.enableWifi();
await $.platform.mobile.disableWifi();
await $.platform.mobile.enableCellular();
await $.platform.mobile.enableDarkMode();
await $.platform.mobile.enableAirplaneMode();

// --- 手势 ---
await $.platform.mobile.swipe(
  from: const Offset(0.5, 0.8),
  to: const Offset(0.5, 0.2),
  steps: 12,
);
await $.platform.mobile.swipeBack();     // iOS 返回手势（从左边缘滑动）
await $.platform.mobile.pullToRefresh();
await $.platform.mobile.pressVolumeUp();
await $.platform.mobile.pressVolumeDown();

// --- 设备信息 / 仅模拟器 ---
await $.platform.mobile.setMockLocation(37.7749, -122.4194);
final bool isVirtual = await $.platform.mobile.isVirtualDevice(); // 在模拟器上始终为 true

// --- 旧别名（$.native）— 仍然有效，供参考 ---
if (await $.native.isPermissionDialogVisible()) {
  await $.native.grantPermissionWhenInUse();
}
await $.native.pressHome();
await $.native.swipeBack();
```

**iOS 注意：** `$.native.pressRecentApps()` 是 Android-only API，在 iOS 上会编译报错。

---

### Section 11 — Pump / Settle 参考

标题：`## Pump / Settle`

```dart
// 泵入整个 widget 树并稳定（在 pumpWidget 之后、交互之前使用）
await $.pumpWidgetAndSettle(const MyApp());

// 手动泵入
await $.pump();                        // 单帧
await $.pump(Duration(seconds: 1));    // 泵入指定时长

// pumpAndSettle 变体（通常不直接使用 — 在操作中使用 settlePolicy）
await $.pumpAndSettle();
await $.pumpAndTrySettle();

// 大多数测试的正确模式：
// 1. 开始时 pumpWidgetAndSettle 一次
await $.pumpWidgetAndSettle(const MyApp());
// 2. 每个操作使用 settlePolicy: SettlePolicy.trySettle（或在 config 中设置）
await $(#button).tap(settlePolicy: SettlePolicy.trySettle);
// 3. 仅在需要手动帧控制时使用 $.pump()
```

---

### Section 12 — Anti-Patterns（常见 agent 错误，必须包含）

标题：`## Anti-Patterns — 常见错误`

以列表形式写出以下 6 个 anti-pattern，每条说明原因：

1. **`setUp()` 代替 `patrolSetUp()`** — Vanilla `setUp` 不接入 Patrol 的原生自动化生命周期；在 iOS 上导致间歇性失败

2. **`IntegrationTestWidgetsFlutterBinding.ensureInitialized()`** — 致命的双重初始化；从所有 Patrol 测试文件中完全删除

3. **`SettlePolicy.settle` 作为默认值** — 在无限动画（loading spinners、Lottie）上抛出异常；使用 `trySettle`

4. **`flutter test integration_test/`** — 运行错误的 runner；始终使用 `patrol test`

5. **在 iOS 上调用 `$.native.*` 的 Android-only 功能（`pressRecentApps()`）** — 在 iOS 上编译报错

6. **缺少权限守护** — 没有 `isPermissionDialogVisible()` 检查就调用 `grantPermissionWhenInUse()` 在重新运行时失败

---

## API 版本说明（文档末尾）

标题：`## Patrol 4.x API 变更速览`

简短表格对比旧 API 和当前 API：

| 旧方式 | 当前方式 | 变更版本 | 说明 |
|--------|---------|---------|------|
| `$.native.*` | `$.platform.mobile.*` | Patrol 4.0 | 两者仍有效；新代码用 `$.platform.mobile` |
| `integration_test/` 目录 | `patrol_test/` 目录 | Patrol 4.0 | 脚本须使用 `patrol_test/` 除非项目 opt-in |
| `patrolTest()` 中的 `bindingType` 参数 | 已删除（始终为 PatrolBinding）| Patrol 3.0 | 不要在新测试代码中包含 |
| `nativeAutomation: true` 参数 | 已删除（`patrolTest` 中始终启用）| Patrol 3.0 | 无需原生测试时使用 `patrolWidgetTest()` |
| `andSettle` finder 方法 | `settlePolicy` 参数 | patrol_finders v2 | `andSettle` 已完全删除 |
| `SettlePolicy.settle` 为默认值 | `SettlePolicy.trySettle` 为默认值 | patrol_finders v2 | 模板默认值必须为 `trySettle` |

---

以上为文档全部内容。确保文档可独立使用，所有代码示例经过验证（来自 RESEARCH.md Context7 源）。
  </action>

  <verify>
    <automated>grep -c "SettlePolicy\." reference/patrol-patterns.md | awk '{if($1>=6) print "PASS: found",$1,"SettlePolicy references"; else print "FAIL: only",$1,"SettlePolicy references (need >=6)"}'</automated>
    <automated>grep -q "SettlePolicy.settle\b" reference/patrol-patterns.md && grep -q "SettlePolicy.trySettle" reference/patrol-patterns.md && grep -q "SettlePolicy.noSettle" reference/patrol-patterns.md && echo "PASS: all 3 SettlePolicy values present" || echo "FAIL: missing one or more SettlePolicy values"</automated>
    <automated>grep -q '$(#' reference/patrol-patterns.md && grep -q '$(RegExp' reference/patrol-patterns.md && grep -q '$(Icons\.' reference/patrol-patterns.md && echo "PASS: Symbol, RegExp, IconData finder types present" || echo "FAIL: missing finder types"</automated>
    <automated>grep -q "containing(" reference/patrol-patterns.md && echo "PASS: containing() chained finder present" || echo "FAIL: containing() missing"</automated>
    <automated>grep -q '\.platform\.mobile' reference/patrol-patterns.md && grep -q '\.native\.' reference/patrol-patterns.md && echo "PASS: both $.platform.mobile and $.native aliases present" || echo "FAIL: missing one alias"</automated>
    <automated>grep -q "patrolSetUp\|patrolTearDown" reference/patrol-patterns.md && echo "PASS: patrolSetUp/patrolTearDown present" || echo "FAIL: lifecycle hooks missing"</automated>
    <automated>grep -q "Anti-Pattern\|anti-pattern\|Anti-pattern" reference/patrol-patterns.md && echo "PASS: anti-patterns section present" || echo "FAIL: anti-patterns missing"</automated>
    <automated>wc -l reference/patrol-patterns.md | awk '{if($1>=250) print "PASS: file has",$1,"lines"; else print "FAIL: file only has",$1,"lines (min 250)"}'</automated>
  </verify>

  <acceptance_criteria>
    - reference/patrol-patterns.md 存在且 >= 250 行
    - 所有 3 个 SettlePolicy 值均存在：`grep "SettlePolicy.settle\b\|SettlePolicy.trySettle\|SettlePolicy.noSettle"` 返回 >= 3 行
    - 所有 6 种 finder 类型均存在：String（`$('`）、RegExp（`$(RegExp`）、Type（`$(TextField`）、Symbol（`$(#`）、Key（`$(const Key`）、IconData（`$(Icons.`）
    - `containing()` 链式 finder 有代码示例
    - `.at(` 索引选择有代码示例
    - `.which<` 谓词过滤有代码示例
    - `$.platform.mobile` 和 `$.native` 两种别名均出现
    - `patrolSetUp` 和 `patrolTearDown` 均出现（区分于 `setUp`/`tearDown`）
    - anti-patterns 章节存在且至少包含 6 条条目
    - 不包含 `bindingType` 或 `nativeAutomation` 作为 `patrolTest()` 的参数（这些已在 Patrol 4.0 中删除）
  </acceptance_criteria>

  <done>
    reference/patrol-patterns.md 已创建，包含：
    (1) Imports 和完整 patrolTest 骨架
    (2) 6 种 finder 参数类型的代码示例
    (3) containing()、.at(n)、.first、.last、.which<T>() 的链式 finder 示例
    (4) 完整交互方法（tap、longPress、enterText、scrollTo、waitUntilVisible/Exists、.text）
    (5) 断言方法（findsOneWidget、findsNothing、.exists、.visible）
    (6) SettlePolicy 全部 3 个值的对比表和代码示例，trySettle 标注为推荐默认值
    (7) $.platform.mobile 和 $.native 两种别名的原生自动化 API
    (8) Pump/Settle 参考和正确使用模式
    (9) 6 条 Anti-patterns 条目
    (10) API 版本变更速览表
  </done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| 文档内容 → agent 代码生成 | agent 使用文档中的代码示例直接生成 Dart 代码；错误示例会生成无法编译的代码 |

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-01B-01 | Tampering | patrol-patterns.md 中的代码示例准确性 | mitigate | 所有 API 示例均经 Context7 /leancodepl/patrol 验证；executor 从 RESEARCH.md DOC 2 节逐字写入 |
| T-01B-02 | Information Disclosure | 代码示例中的 bundle ID / app ID | accept | 所有示例均使用占位符（`com.example.app`），非真实凭据 |
</threat_model>

<verification>
执行此 plan 后，验证：

1. `ls -la reference/patrol-patterns.md` — 文件存在
2. `wc -l reference/patrol-patterns.md` — 行数 >= 250
3. `grep "SettlePolicy\." reference/patrol-patterns.md | wc -l` — 返回 >= 6
4. `grep '$(#\|$(RegExp\|$(Icons\.' reference/patrol-patterns.md | wc -l` — Symbol、RegExp、IconData finder 均存在
5. `grep '\.platform\.mobile\|\.native\.' reference/patrol-patterns.md | wc -l` — 两种别名均存在
6. `grep "Anti-Pattern\|anti-pattern" reference/patrol-patterns.md` — anti-patterns 章节存在
</verification>

<success_criteria>
- reference/patrol-patterns.md 已创建，内容完整，可作为代码生成的唯一 grounding 文档
- agent 可仅凭此文档生成正确的 Patrol 4.x 测试代码，无需依赖训练数据
- 所有 6 种 finder 类型均有代码示例
- 所有 3 个 SettlePolicy 值均有说明，trySettle 明确标注为推荐默认值
- $.platform.mobile 和 $.native 两种别名均展示
- anti-patterns 章节防止常见 agent 错误（setUp vs patrolSetUp、SettlePolicy.settle 作为默认值等）
</success_criteria>

<output>
完成后，创建 `.planning/phases/01-reference-documentation/01-B-SUMMARY.md`

包含：
- 创建了哪个文件（路径和行数）
- 文档涵盖的 API 章节列表
- 任何偏离计划的内容（如有）
</output>
