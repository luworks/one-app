# one. × Apple Intelligence：用 iPhone 自带大模型做「说一句话就能加 / 调」

调研日期 2026-10-15。资料来源：Apple 官方 Foundation Models 文档（developer.apple.com）+ 本机 Xcode 27 / iOS 27 SDK 编译验证。第三方博客只用来补充，已标注。

Current scoped exception (2026-10-20): a clear submitted one-off reminder is authorized by Send and uses deterministic rules plus confirmed persistence. See “Submitted one-off reminder requests” below. Historical preview-only statements in this research document remain applicable to all other changes.

## 结论（先看这个）

1. **能做，而且几乎不用改产品原则。** 用 Apple 的 `FoundationModels` 框架（iOS 26+）调用设备上的端侧模型：免费、离线、数据不出设备、没有 API key、不需要后端。
2. **模型只负责「理解」，不负责「执行」。** 让它输出一个结构化的 `Intent`（`@Generable`），App 把它转成现有的 `Capture` / `PlanCard` 预览卡，用户点 Add / Apply 才写入。这和 CLAUDE.md 里「AI prepares, the user decides」完全吻合，也正好接上现有的 `AskView.send()` → `pending` / `plan` 流程。
3. **日期和排程不要交给模型。** 端侧模型约 3B 参数，推理弱、不知道今天几号。让它只抽取（标题、相对天数、几点、操作类型、目标 id），日期换算继续用确定性代码；排程继续用现有 `DayPlanner`。现有 `CaptureParser` 保留为「模型不可用 / 失败」时的兜底，也可以拿来交叉校验。
4. **最大的工程约束是上下文只有 4096 token**（输入+输出+schema+工具定义全算）。调整日程这类「要引用已有条目」的需求，必须由代码先筛出少量候选（≤ 20 条，短 id），再塞进 prompt。
5. **最低版本问题：** 项目 deployment target 是 iOS 17，AlarmKit 已经用 `#available(iOS 26)` 隔离（`Ringer.swift`）。AI 同样做成 `#if canImport(FoundationModels)` + `@available(iOS 26, *)` 的可选增强，老系统 / 非 Apple Intelligence 设备继续走 `CaptureParser`。
6. **Private Cloud Compute（32K 上下文、可推理）不建议现在上。** 需要向 Apple 申请 managed entitlement，而且只有 iOS 27；README 里你们是 free Apple ID 签名，大概率拿不到。先把端侧做好。

## 1. 框架能力（官方文档已确认）

| 项目 | 事实 | 来源 |
|---|---|---|
| 框架 | `FoundationModels`，`SystemLanguageModel.default` 是端侧模型 | 官方 |
| 系统要求 | iOS / iPadOS / macOS / visionOS 26.0+；设备需支持 Apple Intelligence | 官方 |
| 模型版本 | 三代：26.0–26.3、26.4、27.0。Apple 会随系统升级换模型，**prompt 行为可能漂移**，要有回归用例 | 官方 `updating-prompts-for-new-model-versions` |
| 可用性 | `model.availability`：`.available` / `.unavailable(.deviceNotEligible)` / `.unavailable(.modelNotReady)`（下载中）等 | 官方 |
| 上下文 | 端侧 4096 token / session；英文约 3–4 字符一个 token，**中日韩约 1 字一个 token**。超了抛 `LanguageModelError.contextSizeExceeded` | 官方 |
| 结构化输出 | `@Generable` + `@Guide`，框架保证返回值符合你的 Swift 类型（含枚举、范围约束、可选值） | 官方 |
| 工具调用 | `Tool` 协议：`name`、`description`、`@Generable Arguments`、`call(arguments:)`；工具可并发调用；官方建议**每个请求 3–5 个工具以内** | 官方 |
| 语言 | 用 `supportsLocale()` / `supportedLanguages` 判断；不支持的语言抛 `unsupportedLanguageOrLocale`。简体中文在首发语言列表里（第三方博客），**以真机 `supportsLocale(Locale(identifier:"zh_CN"))` 为准** | 官方 + 第三方 |
| 设备范围 | iPhone 15 Pro 及以后等（第三方博客），**以 Apple Intelligence 官网列表为准** | 第三方 |
| 仅 iOS 27 的 API | `GenerationOptions(toolCallingMode:)`、`PrivateCloudComputeLanguageModel`、图片 prompt、dynamic profile。**我在 iOS 26 target 下编译验证过：这些要加 `#available(iOS 27)`** | 官方 + 本机编译 |

## 2. 架构：Parse → Resolve → Preview → Apply

```
用户输入（打字 / 听写）
   │
   ▼
[路由] 现有 isPlanRequest / isQuestion 先挡掉明确的（"plan my day" 走 DayPlanner，不烧 token）
   │
   ▼
[模型 · 抽取]  LanguageModelSession.respond(to:, generating: ParsedAction.self)
   │            输入：用户原话 + 今天日期/星期/时区 + 候选条目（仅编辑类需要）
   ▼
[代码 · 解析]  dayOffset+hour+minute → Date；targetID → 真实 OneTask；校验原则
   │            （事件不能被挪；due 不动；停闹钟≠完成）
   ▼
[预览卡]       CaptureCard（新增）/ ChangeCard（调整，类似 PlanCard）
   │
   ▼  用户点 Add / Apply
[commit]       走现有 commit + Undo toast；ringsAsAlarm → Ringer.sync；event → CalendarSync.save
```

不推荐的做法：把「创建任务」做成 `Tool`，让模型直接调用写库。官方文档说工具可以有副作用（比如开暗黑模式），但那样 AI 会绕过预览卡，违反原则 1。**工具只用来读（查空闲时间、查条目），写永远经过预览卡。**

### 2.1 Schema 草图（已在 iOS 26 SDK 上通过 `swiftc -typecheck`，除去 `toolCallingMode`）

```swift
import FoundationModels

@available(iOS 26, *)
@Generable
enum ActionKind: String { case addTask, addEvent, addAlarm, editTask, question }

@available(iOS 26, *)
@Generable
struct ParsedAction {
    var kind: ActionKind
    @Guide(description: "Title in the user's own words, keep the original language")
    var title: String
    @Guide(description: "Days from today, 0 = today", .range(0...365))
    var dayOffset: Int?
    @Guide(.range(0...23)) var hour: Int?
    @Guide(.range(0...59)) var minute: Int?
    var durationMinutes: Int?
    @Guide(description: "Existing item id, only for editTask")
    var targetID: String?
    @Guide(description: "For editTask: moveToTime, postpone, moveToTomorrow, ringAsAlarm")
    var edit: String?
}
```

要点：
- **字段名就是 prompt 的一部分**（官方强调），要短而清晰；`@Guide` 描述也占 token，只在必要处加。
- 输出用 `dayOffset + hour + minute`，不要让模型输出 ISO 日期字符串——它不知道今天几号，训练数据截止较早（第三方博客测得）。
- 对「周五」「下周一」「大后天」这类说法，建议**让现有 `CaptureParser` 先算出日期**，模型输出与之冲突时以解析器为准或者把差异显示在预览卡上让用户改。（`CaptureParser` 已覆盖中英文周几、月日、范围时间。）
- 若需要让模型「先想后答」，官方建议在 struct 里**第一个字段放 `reasoningSteps: String`**，否则推理文字会混进字段。

### 2.2 Instructions（要点）

```text
You extract one action from the user's message for a planner app.
Today is Thursday 2026-10-15, 09:41, timezone Asia/Shanghai.   // 代码里动态拼
The person's locale is zh_CN.                                  // 官方要求的固定句式
Keep titles in the user's original language. Never invent a date or time.
If no time is given, leave hour and minute empty.
```

- locale 句子要用官方给的**固定英文格式** `The person's locale is zh_CN.`（文档明确说这个措辞来自训练）。
- 不遵守时用大写 MUST / ALWAYS，但官方也提醒别过量。
- 用户输入只放在 prompt，**不要拼进 instructions**（防 prompt injection）。
- 条件逻辑用 Swift 代码拼 prompt，不要在 prompt 里写一长串 IF/ELSE（官方建议）。
- few-shot 2–15 个简单示例有效，但每个要短；中英混合各放几个。

### 2.3 「调整日历 / 任务」怎么做

这是最难的一类，因为模型要引用**已存在**的东西，而 4096 token 装不下全部数据。

**先判断是不是「调整」（代码规则，`Editing.looksLikeEdit`，有单测）：只有句子能指到一个已存在的条目才算调整，否则一律当新建（capture）。**
- 「提醒我 / remind me / 别忘了」开头的新建请求，除非原话里的词对上了某个条目的标题，否则不是调整（「提醒我把车挪一下」是新提醒）。
- 仅仅一个钟点（「下午 3 点」）恰好等于某条目的开始时间，不算指到了它；只有「三点那个会改到四点半」「the 3pm one」「move the 4:30 to 5:30」这种用钟点指代条目的说法才算。
- 回答「Which one do you mean?」时，如果回答本身是一个新请求（提醒我…、「我想…」且只有个别词和某选项标题重叠），它不是在选条目，按新建处理（`Dialogue.answerToWhichOne`）。

1. 代码先按规则筛候选：未完成任务 + 未来 7 天内的任务，最多 ~20 条。
2. 给每条一个短 id 并压成一行：`t3|Send Q3 report|due Fri|plan Thu 15:00`。
3. 模型只输出 `kind=editTask, targetID=t3, edit=postpone / moveToTime(hour,minute)`。
4. 代码校验：
   - `targetID` 必须在候选里（否则当作没听懂，让用户重说）；
   - 目标是事件 → 不走 `editTask`，转到 §2.6 的 `moveEvent`（原则 2 已改）；
   - 只改这条提醒唯一的日期 `due`（原则 3：一条提醒只有一个日期，没有单独的计划时间）；
   - 闹钟跟随任务（`ringsAsAlarm` + `Ringer.sync`）。
5. 出一张 ChangeCard：「Send Q3 report: 3:00 PM → 5:00 PM」，Apply / Undo。

「帮我安排今天」这类：不再是一个功能（提醒没有单独的计划时间，`DayPlanner` 和 Plan card 已删除），按普通对话回答。

### 2.4 闹钟

不需要新机制：「明早 7 点叫我」→ `addAlarm` → 生成 `OneTask(due: 7:00)` 且 `ringsAsAlarm = true`，沿用 `Ringer`（AlarmKit，iOS 26，要 `NSAlarmKitUsageDescription`，首次会请求授权——项目已具备）。原则 4 不变：停闹钟 ≠ 完成任务。

### 2.5 问答

「今天还有什么？」这类现在是 `todaySummary` 的拼字符串。可以把 `todaySummary` 的结果作为上下文交给模型润色，或者保持现状——**如果没坏就别修**，建议第一版不动。

### 2.6 AI 建议调整会议（已决定，原则 2 已改写）

**决定：** AI 可以改会议，包括有其他参会人的会议，直接写系统日历。但只在用户要求时，并且必须经过预览卡。

**触发（由我选，用户授权）：**
1. 用户主动说「把下午的会往后挪一小时」→ `kind = moveEvent`。
2. 晨报 / Home 的 needs-you 卡片里出现**真实冲突**（两个事件重叠，或已排时间的任务与事件重叠）时，卡片上提供「建议调整」按钮，点了才生成预览。
3. 不做：没有冲突时的主动「优化」建议；AI 在后台自行改日历。一个冲突只提示一次，可以关掉。

**流程：** 与任务调整相同（候选筛选 → 短 id → 模型输出 `moveEvent(targetID, hour, minute | dayOffset)` → 代码校验 → ChangeCard → Apply / Undo），区别在校验和卡片内容：
- 候选里只放用户日历（可写）里未来 7 天的事件，带短 id，含「有无参会人」标记。
- 卡片必须写清**影响范围**：
  - 自己的事件：`Lunch 12:00 → 13:00`。
  - 你是组织者、有 N 位参会人：`4 pm 评审 → 5 pm · 会向 N 位参会人发送更新`。
  - 你是被邀请人、不是组织者：EventKit 对被邀请人改时间的行为我**没有验证**（可能保存失败，也可能只改本地且不通知组织者）。第一版建议卡片明确提示「你不是组织者，改的只是你自己的日历，不会通知对方」，并提供次要按钮「写一条给组织者的留言」（只生成文字，不发送）。spike 阶段先在真机上验证实际行为再定。
- **重复事件只改这一次**：用 `store.save(ek, span: .thisEvent)`。现有 `CalendarSync.save` 固定用 `.futureEvents`，AI 不能复用，要加一个 span 参数。
- 只读日历 / 订阅日历：不可改，只提示冲突。
- 需要补的数据（目前 `OneEvent` / `ExternalEvent` 都没有）：是否有参会人、当前用户是否组织者、日历是否可写（EventKit 里大概对应 `hasAttendees`、`organizer`、`calendar.allowsContentModifications`，**未在本机核对**）。
- Undo：写之前记下原 start/end；Undo 把时间改回去。已发出的参会人更新无法撤回，Undo 之后会再发一次更新，卡片和 Undo toast 里要说明。
- `DayPlanner` 不变：规划任务时事件仍是固定障碍。

## 3. 风险与对策

| 风险 | 对策 |
|---|---|
| 4096 token 上限 | 每条消息新建 session（不要长对话）；候选 ≤ 20；catch `contextSizeExceeded` 后重试精简版；用 `SystemLanguageModel.tokenCount(for:)` 在开发期量一下实际占用 |
| 日期算错 / 幻觉 | 模型只出相对量；代码换算；与 `CaptureParser` 交叉校验；预览卡永远显示解析后的绝对日期时间 |
| 中文质量 | 先用 `supportsLocale()` 判；写一个小评测集（中英混合 30–50 句），用官方 Evaluations 框架或简单单元测试跑；因为 Apple 会换模型版本，要持续回归 |
| 安全护栏误杀正常输入 | 捕获 guardrail 错误 → 回落 `CaptureParser`，不要给用户报错 |
| 设备 / 系统不支持 | `availability != .available` 或 iOS < 26 → 直接走现有 `CaptureParser`，UI 不变；设置页可以显示一行「AI 理解：开 / 不可用（原因）」 |
| 延迟 | `session.prewarm()` 在 AskView 出现时调用；用 `streamResponse` 让预览卡逐字段出现（可选） |
| 模型被 App Intents / Siri 替代？ | 另一条路：把 AddTask / AddEvent 暴露成 App Intents，让系统 Siri 自己调用。**本次没有深入调研**，建议单独评估；它不替代应用内的 composer |

## 4. 与现有代码的接点

| 现有 | 改动 |
|---|---|
| `AskView.send()`（`ios/One/AskView.swift`） | 在 `pending = CaptureParser.parse(text)` 处换成 `await Understander.parse(text)`，失败回落 |
| `Capture`（`Capture.swift`） | 加一个 `kind == .alarm` 或 `ringsAsAlarm` 字段；保持 `insert(into:)` 的「只在 Add 后写入」 |
| `PlanCard` | 复制出 `ChangeCard`（旧值 → 新值） |
| `DayPlanner` / `Ringer` / `CalendarSync` | 不改 |
| 写入路径（已核对代码） | 任务只存在本地 SwiftData（`Reminders.swift` 只是本地通知，没有 EKReminder；`DevImport` 仅 DEBUG 导入）。**事件**通过 `CalendarSync.save` 写入系统日历。AI 新增事件必须走和手动添加相同的路径（不要只 `context.insert`），否则系统日历里看不到 |
| 新文件 `Understanding.swift` | `ParsedAction`、instructions 拼装、候选筛选、校验；`#if canImport(FoundationModels)` 包住 |
| 测试 | 把「解析结果 → Capture / Change」的纯函数做成可单测（不依赖真模型）；真模型只做真机冒烟 |

## 5. 建议的推进顺序

1. **Spike（半天）：** 先试 iOS 27 模拟器（本机 Apple Silicon，已装 iOS 27 模拟器；官方文档里 Xcode scheme 有「Simulated Apple Foundation Models Availability」选项，说明模拟器里框架可用）——**条件是 Mac 上已开启 Apple Intelligence，模拟器是否真能跑出模型输出我没有验证**。跑不起来再上真机。最终准确率/延迟仍以真机为准。内容：跑 `ParsedAction`，对 30 句中英混合输入看准确率和耗时；确认 `supportsLocale(zh_CN)`。这一步决定值不值得继续。
2. **新增（addTask / addEvent / addAlarm）**：替换 `CaptureParser` 调用点，保留兜底。
3. **调整（editTask）**：候选筛选 + ChangeCard。
4. 之后再考虑：streaming、App Intents / Siri、PCC。

## 6. 未验证 / 需要真机确认

- 我没有在真机或模拟器上**运行**过模型，只做了类型检查；准确率、延迟、中文表现全是未知，必须由第 1 步的 spike 回答。
- iPhone 具体机型范围、简体中文在当前系统版本的支持情况：以 Apple Intelligence 官网列表和 `supportsLocale()` 为准。
- 免费 Apple ID 签名下端侧 FoundationModels 是否需要额外 entitlement：官方文档只提到 PCC 需要 managed entitlement；端侧没有提到，但需真机确认。

## 来源

- [Foundation Models（官方总览）](https://developer.apple.com/documentation/foundationmodels)
- [SystemLanguageModel](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel)
- [Expanding generation with tool calling](https://developer.apple.com/documentation/foundationmodels/expanding-generation-with-tool-calling)
- [Managing the context window](https://developer.apple.com/documentation/foundationmodels/managing-the-context-window)
- [Prompting an on-device foundation model](https://developer.apple.com/documentation/foundationmodels/prompting-an-on-device-foundation-model)
- [Supporting languages and locales](https://developer.apple.com/documentation/foundationmodels/supporting-languages-and-locales-with-foundation-models)
- [Adding server-side intelligence with Private Cloud Compute](https://developer.apple.com/documentation/foundationmodels/adding-server-side-intelligence-with-private-cloud-compute)
- [AlarmKit 官方示例](https://developer.apple.com/documentation/alarmkit/scheduling-an-alarm-with-alarmkit)、[WWDC25 session 230](https://developer.apple.com/wwdc25/230)
- 第三方（仅作补充，未当作事实依据）：[Natasha The Robot](https://www.natashatherobot.com/p/apple-foundation-models)、[Blake Crosley](https://blakecrosley.com/blog/apple-foundation-models-framework)

## 7. 技术选型结论（2026-10-16，实测）

### 7.1 目标与方法

目标（评测前设定）：在难度更高的新句子集上，「从一句话生成预览卡」全字段正确率 ≥ 90%，类型判断 ≥ 95%，调整类请求（改期 / 取消 / 问清楚）≥ 90%；p50 延迟 ≤ 1 秒（Mac 上的代理指标）；离线可用、数据不出设备、新手机无需下载大文件；任何情况下都能回落到 `CaptureParser`；用户点 Add / Apply 前不写入任何东西。

方法：同一批人工标注的句子（r1 33、r3 37、r4 41 条捕获；20 条编辑，标签在跑任何模型之前写好），同一份 prompt 和字段名，开源模型用 llama.cpp 的 JSON schema 语法约束（等价于 `@Generable`）、温度 0、Q4_K_M；Apple FM 来自 spike（温度默认，5 次）。评分脚本：`ios/Eval/open/score_open.py`，与 spike 的 Swift 评分一致。三种任务：
- **kind**：只判断 task / event / alarm，其余字段用 `CaptureParser`（方案 A2）。
- **full**：模型直接抽取全部字段。
- **edit**：给 8 个候选条目，输出 move / delete / clarify / none + 目标 id + 新日期时间。

### 7.2 结果（百分比；r4 是最难的一套）

| 模型 | 类型 kind r3/r4 | A2 全字段 r3/r4 | 直出 full r3/r4 | 调整 op / 目标 / 时间 | p50 kind / full / edit（Mac，秒） |
|---|---|---|---|---|---|
| `CaptureParser` 单独 | 73 / 66 | 68 / 39 | - | - | - |
| **Apple FM（端侧，macOS 26.6 的模型）** | 96 / 93 | 96 / 63 | 26 / 20 | 79 / 85 / **26**（从不 clarify） | 0.35 / 1.0 / 1.0 |
| Qwen3.5-0.8B | 70 / 66 | 78 / 51 | 5 / 0 | 80 / 75 / 40 | 0.2 / 0.7 / 0.4 |
| Qwen3.5-2B | 86 / 80 | 92 / 59 | 27 / 17 | 85 / 85 / 60 | 0.3 / 0.9 / 0.6 |
| **Qwen3.5-4B** | 97 / 90 | 97 / 61 | 57 / 41 | **95 / 95 / 100** | 0.4 / 1.6 / 1.3 |
| Qwen3-1.7B（Core AI 注册表有） | 46 / 39 | 46 / 29 | 27 / 15 | 80 / 75 / 60 | 0.2 / 0.7 / 0.6 |
| Qwen3-4B（Core AI 注册表有） | 65 / 59 | 68 / 41 | 38 / 20 | 85 / 85 / 85 | 0.3 / 1.2 / 1.1 |
| Gemma 4 E2B | 86 / 93 | 86 / 63 | 27 / 24（近半输出为空） | 15（17/20 请求失败）| 0.5 / 2.7 / 3.4 |
| **gpt-6-luna（云）** | 97 / 95 | 97 / 63 | **95 / 80** | 90 / 90 / 90 | 1.2 / 2.2 / 1.7 |

说明：表中编辑类样本只有 20 条，每条 = 5 个百分点；其余套 33–41 条，每条 2.4–3 个百分点，差几个点不显著。Apple FM 的 A2 / full 数字来自 spike（`ios/Eval/open/apple-fm-r4-*-summary.md`），Gemma 4 E2B 的 full / edit 大量输出为空，结果不可靠，没有继续排查。Qwen3.5-9B 因为太慢、占用过高，只跑了一小部分后停止，不计入结论；gpt-6-luna 是云端的质量上限参照。

### 7.3 发现

1. **「捕获」的瓶颈是解析器的日期覆盖，不是模型。** r4 上解析器日期只对 78%。它漏掉的是：这周末 / 月底 / 下个月3号 / 下下周一 / the 22nd / the 1st、中文数字钟点（七点半、九点）、相对时间（30分钟后、in 2 hours）。gpt-6-luna 能答对其中 8 条，但这类规则可以直接写进解析器（确定性、离线、免费）。把这些补上，A2 的上限从约 63% 升到约 90%（估算，未实测）。
2. **类型判断（task / event / alarm）：** Apple FM（93–96%）≈ Qwen3.5-4B（90–97%）≈ gpt-6-luna（95–97%）。端侧、不用下载的 Apple FM 已经够用。Qwen3.5 ≤ 2B 和 Qwen3 系列不够（≤ 86%）。
3. **「模型直接抽取全部字段」只有 gpt-6-luna 接近可用（r4 80%）。** 端侧模型都不行（Apple FM 20%，Qwen3.5-4B 41%）。
4. **调整类请求：Apple FM 现在的 schema 不够。** 操作判断 79%、目标 85%，但新时间只对 26%（算术：推迟半小时、同一时间改到明天），并且 15 条「该先问清楚」的请求一条都没问（0/15）。Qwen3.5-4B 在同一 prompt 上 95 / 95 / 100，gpt-6-luna 90 / 90 / 90。时间算术应该交给代码（模型只输出 op、目标 id 和「推迟多少分钟 / 改到几点」这类小数字），歧义判断也应该由代码做（用户说的词命中多个候选 → 直接问）。这个重设计**还没测**。
5. **开源模型的接入成本高于看上去的：**
   - iOS 27 的 Core AI 可以把开源模型放进同一个 `LanguageModelSession`（`CoreAILanguageModel`，`@Generable` 和工具调用沿用同一套 API），但注册表里是 Qwen3（0.6B / 1.7B / 4B / 8B）、Gemma 3 / 3n、Gemma 4（需 iOS 27.2+）、Phi、SmolLM2，**没有 Qwen3.5**。实测 Qwen3 在我们的任务上明显差（kind 59–65%）。
   - 好用的 Qwen3.5-4B Q4 约 2.7 GB 文件，运行时内存估计 3 GB 以上（未在手机实测），要么增大安装包要么首次下载；只能走 llama.cpp 或 MLX Swift（Qwen3.5 支持情况未核实），要自己维护推理引擎。
   - 对比 Apple FM：零安装包体积、零下载、系统管理内存。

### 7.4 选型

| 层 | 选择 | 连接方式 | 尺寸 / 成本 |
|---|---|---|---|
| 捕获（加任务 / 事件 / 闹钟） | **`CaptureParser`（补齐日期规则）+ Apple FM 做 task/event/alarm 三选一（A2）** | `FoundationModels`，`@Generable` 枚举，不需要 entitlement；仅 iOS 27 | 0 额外体积；p50 约 0.35 s（Mac） |
| 调整已有条目（改期 / 取消 / 问清楚） | **v1：Apple FM，输出 op + 目标 id + 小数字，时间算术和歧义判断由代码做；先做出来再测** | 同上 | 约 1 s |
| 设备不支持 Apple Intelligence | 仅 `CaptureParser`（调整类请求提示「需要 Apple Intelligence」或让用户手动改） | - | - |
| 复杂请求的上限（可选，不在 v1） | gpt-6-luna 或同类云端小模型，用户明确开启，经自己的服务端转发 | HTTPS + 服务端代理（密钥不进 App） | p50 1.2–2.2 s；任务标题会离开设备；价格我没有核实 |
| **不采用** | 打包 Qwen / Gemma 进 App（v1）；Core AI 的 Qwen3 小模型；PCC | - | - |

理由：Apple FM 在最关键的「类型判断」上与更大的开源模型和云端模型持平，却不增加包体积、不需下载、不增加推理引擎维护；真正拖累准确率的是解析器的日期覆盖，补规则比换模型便宜得多；调整类请求的短板是 schema 设计（让模型做算术）而不是模型太小。Qwen3.5-4B 是端侧开源里唯一在调整类请求上有明显优势的，保留为后备：如果重设计后 Apple FM 的调整类请求仍低于 90%，再评估把它打包或首次下载，并确认 iPhone 内存。

### 7.5 没有验证的风险

- Apple FM 的数字来自 macOS 26.6 的端侧模型。官方文档说 iOS 27.0 是单独的一代模型，可能更好也可能不同，**必须在 iOS 27 真机上重跑**（`ios/Eval/Understanding/run.sh`、`score_open.py` 都可复用）。
- 所有延迟是 Mac 上的数字，不代表 iPhone。手机上的 p50 需要真机实测。
- 评测集是我和 spike 写的，句子少（41 / 20），r4 的标题评分对改写偏严格（例如「和王总吃午餐」被判错），数字有几个点的噪声。解析器补规则之后需要一套**没见过**的新句子做最终验证。
- 开源模型是温度 0、固定 seed；Apple FM 默认采样，对 Apple FM 略不利。
- Qwen3.5-9B、Gemma 4 E4B、Gemma 3 / 3n 没有完成测试（前两个因占用资源过高被我停止，后者因被 Gemma 4 取代跳过）。
- 云端只测了 gpt-6-luna（按你的要求，因为最便宜），没有比较其他尺寸。
- 密钥管理、云端隐私条款、费用都没有评估。

### 7.6 下一步（按顺序）

1. 给 `CaptureParser` 补日期规则（周末 / 月底 / 下个月N号 / N号 / 下下周 / 中文数字钟点 / 相对时间），用 r4 做开发集，另写一套新句子做最终验证。
2. 调整类请求：重设计 Apple FM 的 schema（op + 目标 id + 推迟分钟 / 目标时刻），代码做算术和歧义判断，在 `edit-cases-r4.json` 上重测；再写一批新的调整类句子验证。
3. 在 iOS 27 真机上重跑所有 Apple FM 评测，测手机延迟。
4. 如果第 2 步仍 < 90%，评估 Qwen3.5-4B 的包体积 / 内存方案。

### 7.7 Round 5 更新（修订 7.4 的结论）

spike 做了 7.6 的前两步，数字如下（评测集很小，r4 是开发集，只有 r5 是没见过的新句子；Apple FM 仍是 macOS 26.6 的模型）：

**捕获：补齐解析器的日期规则后，模型的增益基本消失。**

| 方案 | r4（开发集，41） | r5（新句子，36） |
|---|---|---|
| 解析器单独（日期 / 时间 / 时长 / 标题，不看 kind） | 41/41 | 36/36 |
| 解析器单独（含 kind） | 65.9% | 80.6% |
| 原 A2（解析器 + Apple FM 三选一） | 89.4% | 77.8% |
| A2g（A2 + 代码层闹钟守卫，已接入 `Understander.parse`） | 92.7% | 85.2% |
| C0（解析器 + 闹钟关键词规则，不用模型） | 78.0% | 88.9% |

- 模型把「提醒我吃药」「45分钟后提醒我取快递」判成闹钟，把「周末大扫除」「下午三点去银行」这类杂事判成事件。所以 A2g 加了守卫：只有原话里出现 wake me / alarm / 闹钟 / 起床 / 叫醒 / 叫我，「闹钟」才算数（「提醒我」不应该变成会响的 AlarmKit 闹钟）。
- C0、A2g 两套合计 77 句，差距在噪声内。模型唯一明显的增益是**没有事件关键词的事件**（体检、组会、出差），代价是把一些杂事判成事件。
- 事件 / 任务的边界本身有主观性，标签由我们自己写。

**修订后的选型：**
- 捕获 v1：**补齐规则的 `CaptureParser` + 闹钟关键词守卫**；Apple FM 的 task / event / alarm 分类作为**可选增强**（有就用，没有就用解析器），它的价值只在无关键词的事件。设备不支持 Apple Intelligence 时体验几乎不变。不需要任何其他模型。
- 调整已有条目：**Apple FM + 代码**。模型只输出 op + 目标 id；日期时间交给 `CaptureParser`，「推迟多久」从原话里读（模型自己给的分钟数不可靠，「两天」会给出 240 / 480 / 180），含「所有 / all」、命中多个条目、没指明对象一律强制追问，问句直接判 none。实测：

| 指标 | 旧 schema（r4） | 新设计 r4 | 新设计 r5（新 18 句） |
|---|---|---|---|
| op 准确率 | 79% | 100% | 100% |
| 目标准确率 | 85% | 100% | 100% |
| 移动时间完全一致 | 26% | 100% | 100% |
| clarify 召回 | 0% | 100%（15/15） | 100%（20/20） |

注意：这 100% 主要来自代码规则，模型单独跑这个 schema 的 op 只有 74–80%，仍不会主动追问。r5 并不完全是盲测（一条因解析器把「1:1 to 4pm」读成 1pm–4pm 的时间段而失败，修了之后才到 100%）。只有 8 个候选条目；条目多、标题相近时会更常追问（偏安全），没有测。

**所以 Qwen3.5-4B / 云端模型的位置：** 本地开源模型和云端模型都不再需要。Qwen3.5-4B 在调整类请求上的优势（95 / 95 / 100）被「代码做算术和歧义判断」基本抹平，不值得 2.7GB 的包体积和自维护推理引擎。gpt-6-luna 仍然是唯一能处理开放式自由输入的选项，但没有任何证据表明 v1 需要它。

**工作在哪里：** 以上代码（解析器规则、`Understanding.swift`、`Editing.swift`、新评测句子）都在 spike 的 worktree 和分支 `claude-/great-mccarthy-28dd71`，**没有提交，没有合并到本分支，编辑部分没有接入任何界面**。

**仍未验证：** iOS 27.0 的模型、手机延迟、评测集规模、大量条目下的追问频率。

### Submitted one-off reminder requests

The user's Send tap authorizes a clear actionable one-off reminder in chat. No recurrence words means once; do not ask whether to create a reminder or whether it repeats when the request already establishes that. Rules own the original action/date/time, including context-only follow-ups such as `setting reminder` and `one off`. At 09:11, `11点去 costco 加油 买 粒粒` uses the parser's existing local next-11:00 policy: today at 11:00, as the reminder deadline/alert, not planned work time. A passed clock time uses tomorrow under the existing policy. Materially ambiguous action/time stays a preview or asks the necessary clarification.

This exception covers no calendar events/invitations, alarms, recurring requests, edits, deletes or background grant. Both fallback and Foundation Models pass through the same deterministic admission boundary. Direct creation uses the normal Activity approval/Undo/Open receipts, waits for local durability and connected EventKit commit, and retains a retry/cancel draft on failure. A system creation whose local save and compensation both fail retains its real identity so retry does not create a second reminder. Decided continuation answers reuse the existing card; Undo/Cancel never silently re-add it.
