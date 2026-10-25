# Today UI/UX 重构研究（2026-10-24）

> 只做研究和提案。app 代码不改，也不开 PR，等卢元选定方向再动。
> 交互 mockup 和总览页在 `docs/research/uiux-overhaul-20261024/`（`index.html`、`a-tidy.html`、`b-one-bar.html`、`c-one-timeline.html`），用浏览器直接打开即可。现状截图在同一目录的 `shots/` 下。

## 结论

**推荐方向 B「一个输入框」，分两步落地。第一个 PR 先做方向 A 里风险最低的一块：“Today rows act”。**

- 先说结论。复杂的主要原因不是 tab 太多，而是 **Today 只能看、不能改**：
  - Today 上的行不能改期；
  - 逾期项被压在底部的折叠区里；
  - 有四种“先别管它”的隐藏概念（Settle 和三种 Snooze）；
  - 新建入口和时间选择器各有好几套。
- 10 个常用任务的总点击数：现状 **33** → A **23** → B **18**（约少 45%）。需要用户做的决策：**9 → 4 → 1**。
- C 的点击数和 B 一样（18），但要拆掉 Apple 式的 Week 网格和 Clock tab，和 CLAUDE.md 的路线“先在屏幕和手势上对齐 Apple，再超越”冲突。这次不推荐，除非卢元决定提前进入“超越”阶段。
- 第一个 PR 只做三件事：
  - Today 上提醒的长按菜单补上标准项（今天 / 明天 / 选日期 / 旗标），Settle 和 Snooze 先不删；
  - 逾期从底部折叠区挪到顶部的一行；
  - 这一行加一个“整理”按钮，直接打开现有的 Tidy 卡。

  只改 Today 这一个功能区，不碰数据结构、同步和闹钟编辑器。效果是“改期” 3 → 2 次点击，“处理逾期” 8 → 2 次。

## 更新（2026-10-25）：卢元的决定和执行计划

**决定**：按方向 B 做，基于 2026-10-25 的 main 重新对齐。

**更正**：
- **Settle 保留**。它是专门的功能：今天已经处理过的东西可以从 Today 收起来，Calendar 里的 event 不用删。这和“完成”是两回事。前文 §2.3 第 3 条把它和 Snooze 归成一类，这个说法不对。
- **Snooze 删除**。产品不需要这个功能，而且它默认关闭，界面上本来就看不到。

**main 上已经完成的部分**（审计之后合并的）：
- #155：底栏改成 "Ask AI or add anything" 输入框在前，Today 和 + 在右边。
- #163：点输入框直接进入全屏 Chat。
- #154：+ 在每一页都弹同一个菜单。这是卢元选的，所以方向 A 里“+ 点一下就新建”这一条作废。
- #164：删除不再要求确认，靠 Undo 兜底。

因此加提醒、加日程、设闹钟、问 AI 这几项任务的点击数已经降到 B 方向的水平。

**剩下的 6 个 PR，各自独立，CI 绿了再合并**（2026-10-25 已全部合并）：

| # | PR | 效果 |
|---|---|---|
| 1 | Workbench 编译修复（#165，已合并） | `./dev ui` 和 scene 截图恢复可用 |
| 2 | Today 的行可以直接改期（长按菜单补回 Today/Tomorrow/Unschedule，再加一个 Tomorrow 滑动手势）；逾期显示在顶部，旁边加 Tidy 按钮（#166，已合并） | 改期 3 → 2；处理逾期 8 → 2 |
| 3 | 删除 Snooze（Settle 不动）（#173，已合并） | 少一个概念 |
| 4 | Today 顶部加周条（#174，已合并） | 看明天 2 → 1 |
| 5 | Chat 输入时列出匹配的提醒和日程（#175，已合并） | 找东西 3 → 2 |
| 6 | 删除 Settings 里的 “Show overdue”（和原则 6 冲突）（#176，已合并） | 少一个设置项 |

Tomorrow 折叠区先保留。等周条在手机上实际用过一段时间，再决定要不要删。

## 1. 方法

- **现状**：在 `main @ 79b8922` 构建 TodayMock（`./dev build Debug --scheme TodayMock`），装到本会话专用的模拟器 Today-UIUX（iPhone 17 Pro，iOS 27.0），用 `-uiTesting -dataset tests/fixtures/today-dataset.json` 加载测试数据，逐屏截图并实走每个任务。同时读代码，列出所有入口、sheet、长按菜单、左滑操作和设置项（下文附 `file:line`）。
- **`./dev ui capture` 用不了**：main 上的 `TodayWorkbench` 编译失败。`ios/Development/SceneCatalog.swift:833` 找不到 `PlanCard`，`:946` 找不到 `AskNativeActions.applyPlan`。这两个符号是 #153（`10de5cc0b`）删掉的。所以所有 registered scene 目前都截不了图。这是一个独立的 bug，需要另开修复，本研究没有改动它。
- **点击计数口径**：
  - 从冷启动后的 Today tab 开始算。
  - 一次点按、长按或滑动各算 1 次。
  - 打字算 0 次，但会注明哪些步骤需要打字。
  - “决策”指用户必须选择路径、类型、位置或时间的地方。
  - 现状的数字是实测的；A、B、C 的数字是按 mockup 估算的；竞品的数字是估算（benchmark 资料多为二手，见 §3）。

## 2. 现状审计

### 2.1 导航地图（现状）

```
冷启动 → Today tab
├─ 顶栏：☰（侧栏） + 3 个图标 pill：Calendar / Reminders / Clock   ← Today 不在顶栏 pill 里，在底栏
├─ 底栏：[☀ Today | 💬 Chat] 胶囊 + [+]
│   └─ +：Today 页点一下 = 菜单（New event / reminder / alarm）
│         Calendar 页点一下 = 新日程；Reminders 页 = Quick add；Clock › Alarms = 新闹钟；World Clock = 加城市
│         Stopwatch/Timer 页点一下 = 菜单；其他页长按 = 菜单
├─ Today：日期 · 计时器 · 健康行 · 全天 · 时间线（含 Free 行和 Now 线） · Anytime today
│         · Overdue (N)▸ · Snoozed (N)▸ · Settled (N)▸ · Tomorrow (N)▸   ← 4 个折叠区全在底部
├─ Calendar：Week（默认）/ Month / Year；点日期头 → Today tab
├─ Reminders：智能列表胶囊（Today / Scheduled / All / Flagged / Completed）+ My Lists → 列表页（行内 New Reminder）
├─ Clock：Alarms / World Clock / Stopwatch / Timer
├─ Chat：浮动面板（建议 chip、预览卡、ChangeCard、Tidy 卡）
└─ 侧栏：🔍 Search · Activity · 按日期分组的聊天 · Archived · New chat · ⚙ Settings（约 37 个选择）
```

### 2.2 10 个任务的现状（实测）

| # | 任务 | 点击 | 决策 | 现状路径 / 卡在哪 |
|---|---|---|---|---|
| 1 | 看今天接下来是什么 | 0 | 0 | 打开就是 Today，自动滚到 Now |
| 2 | 加一个带时间的提醒 | 4 | 2 | Today 页 + → 菜单选 New reminder → 时间格 → Save。另一条路是 Chat 输入 → 发送（2 次），但用户得先在两条路之间选 |
| 3 | 改期 / 推迟 | 3 | 2 | Today 的长按菜单只有 显示详情 / Settle / 删除（截图 `03`）。要点开编辑器 → +1 day → Save。左滑的 Snooze 和 Settle 只是把行藏起来，日期没变 |
| 4 | 完成 | 1 | 0 | 点圆圈 |
| 5 | 加一个日程 | 6 | 2 | + 菜单 → New event → Apple 编辑器（标题、开始、结束、添加） |
| 6 | 设闹钟 | 4 | 1 | + 菜单 → New alarm → 滚轮 → Save（闹钟编辑器由 `fix/alarm-wheel-jank` 在改） |
| 7 | 问 AI | 2 | 0 | Chat → 输入 → 发送 |
| 8 | 找一个东西 | 3 | 0 | ☰ → 🔍 → 结果。搜索只在侧栏里，而且搜不到聊天 |
| 9 | 看明天 | 2 | 0 | 滚到底 → 展开 Tomorrow (N) |
| 10 | 处理逾期（测试数据 2 条） | 8 | 2 | 滚到底 → 展开 Overdue → 每条：点开 → +1 day → Save。Chat 的建议 chip “Tidy 2 overdue” 只要 3 次，但只在打开 Chat 后才看得到 |
| | **合计** | **33** | **9** | |

### 2.3 复杂度从哪里来（按影响排序）

1. **Today 只能看，不能改。**
   - Today 上提醒的长按菜单是 *显示详情 / Settle / [Snooze] / 删除*；左滑是 *删除 / [Snooze] / Settle*（`TodayPlannerUI/Rows.swift:21-33, 296-304`）。
   - Reminders 列表和 Calendar 的行上则有 *今天 / 明天 / 取消日期 / 旗标*（`EntryActions.swift:52-110`）。
   - 原因：`DayAgenda.attention(_:)` 在 Today 上总是返回非 nil 值（`FeatureToday/DayAgenda.swift:505-512`），于是 Rows 走了“替换标准菜单”的分支，而不是“在标准菜单上追加”。
   - CLAUDE.md 写的是“long-press menu (Show Details / Flag / Today / Tomorrow / Unschedule / Delete)”，和 Today 上的实际情况不符。
2. **逾期被藏起来了。**
   - Today 上逾期只出现在底部默认折叠的 “Overdue (N)” 区（`DayAgenda.swift:247, 611-624`）。
   - 顶部那条红色的 “N overdue” 快捷行（`DayAgenda.swift:228, 576-600`）只在 `showsWeekStrip == true` 时渲染，但 Today 唯一的调用方传的是 `false`（`TodayShell/HomeView.swift:452`），所以这段是**死代码**。CLAUDE.md 里“an "N overdue" line on top”同样过时了。
   - Tidy overdue 只能在 Chat 里用（输入短语，或点建议 chip）。
   - Settings 的 “Show overdue reminders” 能把逾期整个关掉，**和原则 6“逾期始终可见”冲突**。
3. **“只藏不改”的概念太多。**
   - Settle 和 Today Snooze 是 Today 专用的本地覆盖层（`TodayData/TodayFocusStore.swift`，单独的小文件，和 Activity、同步、`due` 都没有关系）。
   - 再加上通知里的 Snooze（只是重新提醒）和闹钟的 Snooze（另有设置项），一共三个“Snooze”，意思各不相同。
   - 对“改期”这个最常见的意图，用户得先在 Snooze、Settle 和编辑之间选一个，而前两个其实都不改日期。
4. **新建入口太多。**
   - + 的手势在各页不一样：Today、Stopwatch、Timer 上点一下出菜单，其余页点一下直接新建、长按才出菜单（`HomeView.swift:897-986`）。
   - 新建提醒有 4 个 UI：QuickReminderSheet（时间格）、列表里的行内 New Reminder（只有日期 chip，设时间要走 Custom… 再用滚轮）、TaskEditor（时间格）、Chat 卡片（只能靠追问改时间）。时间选择器有 3 种。
   - TaskEditor 由 4 个不同的 presenter 弹出（HomeView、ReminderListScreen、AskScreen、SearchView）。
5. **三个“今天”。**
   - Today tab、Reminders 的 Today 智能列表（带自己的 Overdue 分组）、Calendar 的日视图（点日期头会跳到 Today tab）。
   - 逾期也有 4 种看法：Today 折叠区、Reminders 的 Today 分组、Search 的 “Overdue” 建议、Tidy 卡。
6. **设置太多。**
   - 主屏 35 行，其中 26 个是用户选择；加上子页面，约 37 个选择。
   - 有些项控制的区块本来就默认折叠（Show Tomorrow、Show overdue）。
   - 两个分区都叫 “Calendar”（`SettingsView.swift:281`）。
   - 智能列表的显示/隐藏在 Settings 里一份、胶囊长按里又一份。
   - `eveningHourKey` 定义了却没有对应的设置行（`Preferences.swift:20`）。
7. **可发现性差的控件。**
   - 顶栏 pill 只有图标，没选中时没有文字。
   - Search 藏在侧栏里，开出来的 sheet 还叠在侧栏上面（两层）。
   - Tidy 只在 Chat 里。
   - 健康详情从 Today 和 Settings 两处都能进。
   - Week 网格里短日程的标题被截成 “P…”“S…”（截图 `05`）。
8. **其他小问题（代码层面）。**
   - 日程菜单的 “Show Details” 和 “Edit” 调用的是同一个动作（`Rows.swift:155-156`）。
   - 列表的改名有三个入口：Rename 弹窗、Color & Icon、Name & Appearance。
   - `AlarmsView.swift:90` 的 `adding` sheet 永远不会触发，是死代码。
   - Clock 里闹钟的删除用的是系统的 `.onDelete`，没有走 `RowAction`，和其他列表的样子不一致。

CLAUDE.md 有 4 处已经和现状不符：顶部 “N overdue” 行、Today 的长按菜单、“4 tabs pills on top”（实际 3 个 pill + 底栏 Today）、侧栏没写 Activity 行。这次没改 CLAUDE.md，等定了方向再一起改。

## 3. 竞品 benchmark（摘要）

说明：以下点击数是估算，资料来自 2025-2026 年的公开报道和官方帮助页，没有真机实测。

| App | 结构 | 加带时间的项 | 改期 | Today 和逾期 |
|---|---|---|---|---|
| Apple Reminders (iOS 26/27) | 智能列表 + My Lists | ~3-4；iOS 27 能解析 “2pm Thursday” | (i) → 日期，3 次以上 | 只有提醒，没有日程 |
| Apple Calendar (iOS 27) | Day/Week/Month/Year | + → 一句话 → 点建议，~3 | 拖动 | 提醒可以插在时间线里（全开或全关） |
| Apple Clock | 4 个 tab | + → 滚轮 → Save，~3 | — | iOS 26.1 起“停止”要滑动，Snooze 仍是点按 |
| Things 3 | 无 tab，一张主列表 | + → 标题 → When，~3 | 右滑 → When，2 | 日程放在 Today 顶部；没有“逾期”状态，到期的就留在 Today |
| Todoist | ~5 个 tab | + → 一句话 → 发送，2 | 滑动 → Schedule，2 | Overdue 区块 + 一键 **Reschedule** 全部 |
| Fantastical | DayTicker + 日历 | 一个自然语言框，用 “task” 关键词区分类型，~2 | — | 任务和日程在同一条流里 |
| Structured | Timeline + Inbox | ~4（自然语言还在 beta） | 拖动；“Replan” 一滑处理 | 所有东西都在一条时间线上 |
| Tiimo / Morgen | Today 时间线 + To-do | AI 共同规划，预览后保存 | — | AI 计划以预览块出现，确认后才写入 |

可以借鉴的做法：
- 一个自然语言输入框，由文字决定类型，不让用户先选类型。
- 用滑动打开日期 chip。
- 逾期一键整体改期（Todoist）。
- 当天只有一条时间线，没时间的项放进 “Anytime”。
- 明天、后天做成连续滚动（Fantastical DayTicker、Things Upcoming）。
- AI 只给预览，用户确认后才写入（Morgen、Tiimo，和我们的原则一致）。

要避免的做法：
- 先选类型再输入（Apple Calendar 的 Event | Reminder 切换，约 6-8 次点击）。
- 一个项有两个日期（Things 的 start 和 deadline，用户普遍觉得困惑）。
- AI 自动改期（Motion）。
- 每天强制走一遍规划流程（Sunsama）。
- 把主要入口折进菜单里（Todoist 改版时被用户骂过）。

参考来源：MacRumors iOS 27 Calendar/Reminders（2026-06-08）、9to5mac Reminders iOS 26、Cultured Code 的 Things 帮助文档、Todoist 帮助中心（Dates、Swipe、Calendar）、Flexibits App Store 页面、Structured 和 Tiimo 的官网与 App Store 页面、TechCrunch 关于 Todoist Ramble 的报道（2026-01）。

## 4. 三个方向

以下点击数都按 §1 的口径计算。“决策”包括选路径、类型、位置、时间。

| 任务 | 现状 | A 整理 | B 一个输入框 | C 一条时间线 |
|---|---|---|---|---|
| 看今天接下来 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 |
| 加带时间的提醒 | 4 / 2 | 3 / 1 | **2 / 0** | 2 / 0 |
| 改期 / 推迟 | 3 / 2 | **2 / 1** | 2 / 1 | 2 / 1 |
| 完成 | 1 / 0 | 1 / 0 | 1 / 0 | 1 / 0 |
| 加日程 | 6 / 2 | 6 / 1 | **3 / 0** | 3 / 0 |
| 设闹钟 | 4 / 1 | 4 / 1 | **3 / 0** | 3 / 0 |
| 问 AI | 2 / 0 | 2 / 0 | 2 / 0 | 2 / 0 |
| 找一个东西 | 3 / 0 | **2 / 0** | 2 / 0 | 2 / 0 |
| 看明天 | 2 / 0 | **1 / 0** | 1 / 0 | 1 / 0 |
| 处理逾期（2 条） | 8 / 2 | **2 / 0** | 2 / 0 | 2 / 0 |
| **合计（点击 / 决策）** | **33 / 9** | **23 / 4** | **18 / 1** | **18 / 1** |
| 顶层地点（tab、侧栏入口、面板） | 8 | 8 | 7 | 5 |
| “今天”出现的地方 | 3 | 3 | 3 | 1 |
| 新建提醒的 UI | 4 | 2 | 2 | 2 |
| Settings 选择 | ≈37 | ≈20 | ≈19 | ≈16 |

### 方向 A：整理（保守）

**IA**：不变。4 个 tab、侧栏、底栏都保留；Search 从侧栏移到顶栏的一个图标。

```
Today（逾期红条置顶 + 整理）· Calendar · Reminders · Clock
底栏：[Today | Chat] + [+ 点一下 = 新建当前页的类型，长按 = 菜单]
侧栏：聊天 · Activity · Settings
```

**删掉或合并的东西**
- Settle 和 Today 专用的 Snooze：概念、菜单项、左滑项、Snoozed/Settled 折叠区、两个设置项。
- Today 上的行用和其他列表一样的菜单与左滑：左滑是“明天 / 日期… / 删除”，长按是“今天 / 明天 / 下周 / 选日期 / 旗标 / 删除”。
- 顶部红条 “N 条逾期 · 整理”，直接打开现有的 `OverdueTidy` 卡；删掉底部的 Overdue 折叠区。
- + 在 Today 页改成点一下 = 新提醒，长按 = 菜单，和其他 tab 一样。
- 列表里的行内 New Reminder 改用 QuickTimeGrid。提醒只剩一套时间选择器。
- Settings 删掉：Show overdue（和原则 6 冲突）、Show Settle、Show Snooze、Show Tomorrow、Scroll to now、Show alarms in Today、Smart Lists 分区（胶囊长按里已有）、Open Calendar on、Suggestions on Ask、Archive finished chats；两个 Calendar 分区合并。26 个选择降到约 14 个。
- 日程菜单的 “Show Details” 和 “Edit” 合并；列表的 Rename 并入编辑器。
- Tomorrow 默认展开前 3 项。

**会坏的东西**
- 用过 Settle 或 Snooze 的用户，那些被隐藏的项会重新出现。只影响显示，数据和 `due` 不变。
- Settle、Snooze 相关的 UI 测试和 Preferences 单测要删掉或改写。
- J1 测试 `testReminderQuickAddWithPlus` 在 Today 页的步骤会变。

**迁移和工作量（按 PR 拆）**

| # | PR | 大小 |
|---|---|---|
| A1 | Today rows act：Today 菜单补标准项；逾期置顶 + 整理按钮（**第一个 PR**） | S |
| A2 | 删 Settle 和 Today Snooze（`TodayFocusStore` 文件留着不读，下个版本再删） | M |
| A3 | + 的手势统一 | S |
| A4 | 行内 New Reminder 改用时间格 | M |
| A5 | 砍 Settings | S-M |
| A6 | Search 移到顶栏 | S |
| A7 | 日程菜单、列表编辑器去重；删死代码（`overdueShortcut` 的条件、`AlarmsView.adding`） | S |

合计约 7 个 PR、4-6 个工作日。每个 PR 都可以单独回滚。

**原则风险**：没有违反。删 Settle 和 Snooze 不违反任何原则，但这是**推翻之前的产品决定**，需要卢元确认（见 §6）。

### 方向 B：一个输入框（推荐）

**IA**

```
顶栏：☰ + 4 个 pill（Today · Calendar · Reminders · Clock，Today 回到顶栏）
Today：周条（点一下或左右滑 = 任意一天）+ 逾期红条 + 时间线
底栏：一个常驻输入框「✦ 添加或提问…」+ 🎙
  ├─ 边输入边显示：已有的匹配项（= 搜索）+ 将要添加的预览卡（类型由文字判断，可改）
  ├─ 发送：明确的一次性提醒直接创建（沿用现有的 scoped 例外），日程、闹钟、改动仍出预览卡，点“添加”或“应用”才写入
  ├─ 问题：答案直接出现在 Today 上方；“继续聊”展开成现在的 Chat 面板
  └─ 长按 ✦：手动打开空白编辑器（提醒 / 日程 / 闹钟），给不想打字的人
侧栏：聊天历史 · Activity · Settings（不再放 Search）
```

**删掉或合并的东西（在 A 的基础上）**
- 底栏的 Today/Chat 胶囊和 + 按钮，合并进输入框。
- 侧栏的 Search，合并进输入框。
- Today 底部的 Tomorrow 折叠区和 Show Tomorrow，换成周条或左右滑。
- “用 + 还是用 Chat”这个选择消失。

**会坏的东西**
- 用户已经习惯的 + 和 Chat 入口。
- Chat 面板、Search、J1、J7 和侧栏相关的 UI 测试。
- Widget 和 Quick Actions 的 “ask”、“newTask” 入口要改成指向输入框。
- 一边输入一边搜索，需要对本地数据做按前缀、分页的查询（不能每敲一个字就全量扫描；SwiftData 要用带 limit 的 fetch，EventKit 要限定日期区间）。
- 周条和左右滑与 `TabSwipe` 的手势冲突，要把手势区域分开：Today 的内容区滑动切换日期，顶栏和底栏滑动切换 tab。

**迁移和工作量**：先完成 A1-A7，再做以下几项。

| # | PR | 大小 |
|---|---|---|
| B1 | Today 周条 + 左右滑切换日期（复用 `WeekStrip`） | M |
| B2 | 输入框 v1：替换胶囊和 +，发送后走现有的 `ChatRouting`、`CaptureParser`、`Dialogue` | L |
| B3 | 边输入边匹配（复用 `SearchView` 的查询，限 20 条、分页） | M |
| B4 | 问答就地显示，可展开成 Chat 面板 | M |
| B5 | 删侧栏 Search 和旧的 + 菜单；更新 widget 和 Quick Actions | S |

合计 A 之外再约 5 个 PR、6-9 个工作日。

**原则风险（需要卢元确认）**
- **AI 准备、用户决定**：没变。日程、闹钟和改动仍然要点预览卡上的按钮。但主输入框本身变成了一个“提交即对话”的入口：发送一条明确的一次性提醒就会直接创建。规则本身没变，但它的入口从 Chat 面板扩大到了主屏，更显眼，误触的几率也更高。建议保留现在的 Added 回执（带 Undo 和 Open），并让卢元确认这个例外是否适用于主输入框。
- **Apple 手势优先**：4 个 tab 和 Apple 式的屏幕都保留。去掉 + 偏离了 Apple Reminders 和 Calendar 的习惯，长按 ✦ 打开空白编辑器能部分弥补。另一个选择是保留一个小的 +，**需要卢元选**。

### 方向 C：一条时间线（激进）

**IA**

```
顶栏：☰ + 2 个 pill（日程 · 列表）
日程：连续的 agenda：逾期 → 今天 → 明天 → 往后各天（按天分页加载）
      点标题“10月 ▾”展开月历；捏合到年历；周网格放进 ⋯
列表：全部 / 旗标 / 已完成 + My Lists + 无日期提醒（Today 和 Scheduled 智能列表并入日程）
侧栏：Clock（闹钟 / 世界时钟 / 秒表 / 计时器）· 聊天 · Settings
底栏：同 B 的输入框
```

**删掉或合并的东西**
- Calendar tab：变成日程页上的缩放。
- Clock tab：移进侧栏。
- Reminders 的 Today 和 Scheduled 智能列表。
- Today 和 Calendar 日视图的区分。

**会坏的东西**
- 和 Apple 对齐的屏幕：Week 网格默认页、Clock tab。
- Rubric 维度 1（Calendar）和维度 3（Alarms 页）要重写。
- TabMemory、widget 深链、Calendar 的 Year 缓存。
- 约 40% 的 UI 测试要重写。

**迁移和工作量**：A + B 之外再约 8 个 PR（agenda 无限分页 L，Calendar 缩放 XL，Clock 移进侧栏 M，智能列表合并 M，还有测试和文档），约 3-4 周。

**原则风险**
- **和路线冲突**：CLAUDE.md 和 goal-and-rubric 的路线是“先对齐 Apple，证明对齐之后再超越”。C 等于提前进入“超越”阶段。**需要卢元明确决定**，否则不做。
- 另外一个冲突值得一提：rubric 的 Interaction 第 8 条是 “Drag to reschedule on the timeline”，而 CLAUDE.md 写的是 “Nothing is moved by drag in the Week grid”。这三个方向都没有加入拖动。如果要加，只能用于提醒，日程永远不能拖。**这一条需要卢元决定，是改 rubric 还是改原则。**

## 5. 推荐和第一个 PR

**推荐 B**。理由：
- 点击和决策的降幅与 C 相同（33/9 → 18/1）。
- 保留所有和 Apple 对齐的屏幕，不违反路线。
- 每一步都可以独立发布、独立回滚。
- A 的 7 个 PR 本身就是 B 的前置，即使中途停在 A，也已经少了约 30% 的点击。

**第一个 PR（A1，“Today rows act”）**
- **改什么**：
  - Today 上提醒的长按菜单在现有 Settle、Snooze 之外，补上标准的“今天 / 明天 / 选日期… / 旗标”（`TodayPlannerUI/Rows.swift` 的 `attention` 分支从替换改成追加）。
  - 逾期从底部的折叠区挪到时间线顶部的一行 “N 条逾期 · 整理”（复用已有但没被渲染的 `overdueShortcut`，去掉 `showsWeekStrip` 的限制）。
  - “整理”按钮打开 Chat 面板并直接显示 Tidy 卡（`openAsk` 加一个参数，复用 `OverdueTidy`）。
- **不改**：数据结构、EventKit 同步、Settle 和 Snooze 的存储、闹钟编辑器（`fix/alarm-wheel-jank` 正在改）。
- **验收**：
  - Today 上长按一个提醒能看到“明天”，点了以后 `due` 变成明天、时间不变，并且能 Undo。
  - Today 顶部能看到 “2 条逾期”；点“整理” → 应用 → 两条都改期并有 Undo。
  - 跑相关 UI 测试：`EntryActionsTests`、`TidyOverdueTests`、`OverdueTidyTests`，以及 Today 相关的套件。
  - 实测：改期 3 → 2 次点击，处理逾期 8 → 2 次。
- **风险**：低。只改 Today 一个功能区，纯粹是加东西，回滚就是 revert 一个 PR。

## 6. 需要卢元决定的事

1. **选方向**：A / **B（推荐）** / C。
2. **删除 Settle 和 Today Snooze**（A2）：这是推翻之前的产品决定。推荐删除，因为它们只藏不改，和“改期”的意图混在一起。
3. **B 的主输入框是否适用“明确的一次性提醒直接创建”这个例外**：推荐适用，并保留 Added 回执上的 Undo 和 Open。
4. **B 里要不要保留一个小的 +**：推荐不保留，长按 ✦ 打开空白编辑器。
5. **拖动改期**：rubric 第 8 条和 CLAUDE.md 冲突。推荐改 rubric，删掉这一条。如果保留，也只允许拖动提醒。

## 附：其他发现（本次没有修）

- `./dev ui capture` 和 Workbench 在 main 上编译失败（`SceneCatalog.swift:833` 的 `PlanCard`，`:946` 的 `AskNativeActions.applyPlan`，由 #153 引入）。
- CLAUDE.md 有 4 处过时（见 §2.3 末尾）。
- 死代码：`DayAgenda` 里的 `overdueShortcut` 在 Today 上不可达；`AlarmsView.adding` 从来不会被设置。
- `eveningHourKey` 没有对应的设置行，`Logic.swift:267` 的注释引用了一个不存在的 “Evening starts at” 设置。
