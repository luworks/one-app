# Bonobo 的设计思路，以及哪些适合 Today

> 调研日期：2026-10-17。只做调研，没有改任何代码。
> 范围：Bonobo（原 Moleskine Studio / Bonobo Labs）的 Timepage（日历）、Overlap（世界时钟）、Actions（待办）、Flow（速写本）。
> 对照的是 `CLAUDE.md` 里的产品原则：克制、先展示事项、AI 只准备由用户决定、先追平 Apple 自带应用再谈超越、数据留在本地、会议默认不动。

## 结论

Bonobo 最值得学的不是它的 60 多种主题色，而是三件小事：**把空着的时间显示出来**、**用颜色深浅表示一天有多满**、**用手指拖动时间轴来查看任意时刻**。这三件都很便宜，也不会让界面变吵。
Timepage 也有不少我们不该照搬的地方：用拖动来移动会议，用一条连续的时间线取代月历网格，还有几十种主题。这些和"会议默认不动"、"先追平 Apple"两条原则冲突。

### Top 8（按"价值 ÷ 成本 × 是否克制"排序）

| # | 想法（来源） | 放在哪里 | 工作量 | 克制吗 |
|---|---|---|---|---|
| 1 | 在 Today 时间线里显示**空闲时间**，例如"10:30–14:00 空闲 3.5 小时"（Timepage） | `ios/One/DayAgenda.swift` 的 `timeline`，新增 `TimelineItem.gap`；样式放在 `Rows.swift`，和 `NowRow` 放一起 | S | 是。它展示的是"已有事项之间的空白"，也正好是 `DayPlanner`（Plan my day）的输入 |
| 2 | **月份热力图**：一天的事情越多，日期底色越深（Timepage Heat Map） | `CalendarView.swift` 的 `MiniMonth`（Year 视图）；Month 视图保留 Apple 式的 `DayDots` 不变 | S | 是，前提是只用在 Year 视图，或者做成一个开关 |
| 3 | **出发时间 / 路上要多久**：给有地点的事件估算路程，并提示"该出发了"（Timepage travel time） | `Rows.swift` 的 `EventRow` / `ExternalEventRow` 加一行小字；`TodayWidgets/TodayWidgets.swift` 的 `NextUpWidget` | M | 是。Apple 日历本身就有 Time to Leave，所以这属于追平 |
| 4 | **双指捏合缩放** Week 视图：改变一屏显示几天，以及每小时的行高（Timepage pinch） | `CalendarView.swift` 的 `WeekView`（`dayCount`）和 `WeekPage`（`hourHeight = 48` 改成可变） | M | 是。Apple 日历的 Day/Week 也支持捏合缩放时间 |
| 5 | **可拖动查看的世界时钟**：左右滑动整条时间，每个城市的颜色随白天、夜晚、对方的"可联系时间"变化，点一下回到现在（Overlap） | 新建 `WorldClockCard`，放在 `AlarmsView.swift` 的 `TimerCard` 下面。**现在代码里还没有世界时钟** | L | 是。只有一个手势、一种颜色语言，没有图表 |
| 6 | **下一个事件的倒计时**，用 Live Activity 或锁屏小组件显示（Timepage Countdown / Event Countdown） | `TodayWidgets/AlarmLiveActivity.swift` 已经有闹钟的 Live Activity，可以照着做一个 `NextEventActivity`；`WidgetFeed.swift` 提供数据 | M | 是。只显示一个数字，而且要用户自己打开 |
| 7 | **日期底色区分**：过去的日子变淡，周末浅浅地加底色（Timepage Day Shading） | `CalendarView.swift` 的 `WeekPage` 列背景和 `MonthPage` 日期格；`SettingsView.swift` 的 `SettingsKey` 加一个开关 | S | 是 |
| 8 | 在 Today 顶部用**一行天气**显示最高、最低气温和降雨（Timepage weather） | `DayAgenda.swift` 顶部（和 `AgendaHeader` 放一起），默认关闭 | M | 有条件。WeatherKit 要把位置发到 Apple 的服务器，和"数据留在本地"的方向有张力，所以排在最后，并且需要用户主动打开 |

---

## Bonobo 简介

- Bonobo 是一个大约 10 人的小团队，以前叫 Moleskine Studio，后来叫 Bonobo Labs，2025 年改名为 Bonobo，团队没有变。（[about](https://bonobolabs.com/about)，[改名公告](https://bonobolabs.com/articles/name-change-announcement/)）
- Timepage 在 **2015 年 5 月**以 Moleskine 的名义发布（[9to5Mac](https://9to5mac.com/2015/05/28/moleskine-iphone-app/)，[MacStories 评测](https://www.macstories.net/reviews/timepage-a-beautiful-and-clever-calendar-app/)）。Flow 拿过 2019 年 Apple Design Award（[MacStories](https://www.macstories.net/news/apple-design-awards-2019-winners-announced/)）。Timepage、Actions、Flow 打包订阅销售，Overlap 免费（[llms.txt](https://bonobolabs.com/llms.txt)，[App Store 合集](https://apps.apple.com/py/app-bundle/calendar-planner-sketchbook-notebook-drawing-task-to/id1797219065?l=en-GB)）。
- 它们的共同风格：用大号粗体日期、淡彩底色、少量强调色，动画很收敛（[Paste 评测](https://www.pastemagazine.com/tech/ios/moleskine-timepage-ios-app-review-digital-paper)，[MacStories](https://www.macstories.net/reviews/timepage-a-beautiful-and-clever-calendar-app/)）。**没有找到任何来源说明它用的是哪款字体**，所以这里不做推测。

---

## Timepage（日历）

### T1. 连续时间线 + 每天的天气
- **是什么**：首页是一条可以上下滚动的竖向时间线，以周为单位，一眼看完未来几天；每天旁边显示天气，长按某一天可以看最高、最低气温和降雨概率。（[Navigating Timeline](https://bonobolabs.com/support/timepage/navigating-timeline-and-day-view.md)，[Weather](https://bonobolabs.com/support/timepage/viewing-weather-information.md)，[MacStories](https://www.macstories.net/reviews/timepage-a-beautiful-and-clever-calendar-app/)）
- **为什么好用**：日程是按"天"来看的，不按"格子"看；天气决定了穿什么、怎么出门，和日程放在一起才有用。
- **放进 Today**：用连续时间线取代 Month 网格**不采纳**，见文末。天气见 Top 8 第 8 条，默认关闭。
- **工作量**：天气 M（WeatherKit 的权限配置、缓存、隐私说明）。

### T2. 空闲时间提示
- **是什么**：App Store 介绍里写着它会给出类似"事件之间的空闲时间"这样的建议（[App Store](https://apps.apple.com/app/id989178902)）。
- **为什么好用**：日历只画"有事的地方"，但人真正要决定的是"空的地方拿来做什么"。
- **放进 Today**：`DayAgenda.timeline` 已经把事件、外部事件、计划好的任务、闹钟、现在线按 `start` 排好了顺序。只要在相邻两个有时长的事项之间、空档超过某个阈值（比如 45 分钟）时插入一个 `.gap(start, end)`，渲染成一行很淡的小字"空闲 1 小时 30 分"就行。下一步可以让这行小字的长按菜单提供"把一个提醒放到这里"，**依然由用户来点**，复用 `DayPlanner` 的逻辑（`Logic.swift`）。
- **工作量**：S。**克制**：是。

### T3. 月份热力图（Heat Map）
- **是什么**：月历的日期按事件多少深浅着色，可以按住底部按钮左右滑动，一次只看一个日历的分布（[Heat Map](https://bonobolabs.com/support/timepage/navigating-heat-map.md)）；也有热力图小组件（[Widgets](https://bonobolabs.com/support/timepage/timepage-widgets.md)）。
- **为什么好用**：一眼看出"哪一周很满、哪几天有空"，不需要读任何文字。
- **放进 Today**：Month 视图继续用 Apple 风格的 `DayDots`（先追平）。Year 视图的 `MiniMonth` 现在只有数字，可以给每个日期加一层 `Color.accentColor.opacity(0.08…0.45)` 的圆形底色，按当天事件数分成 3 到 4 档。数据可以在 `YearView` 里一次性按月统计，传给 `MiniMonth`，不要每个格子各查一次。
- **工作量**：S。**克制**：是（Year 视图本来就是"看密度"的地方）。

### T4. 路程时间 / 出发提醒
- **是什么**：根据步行、骑车、开车、公共交通估算到达事件地点要多久；手表和小组件上显示"距下个事件还有多久、路上要多久"（[MacStories](https://www.macstories.net/reviews/timepage-a-beautiful-and-clever-calendar-app/)，[Widgets](https://bonobolabs.com/support/timepage/timepage-widgets.md)）。
- **为什么好用**：把"几点开会"换成了"几点出门"，后者才是要采取行动的时间点。
- **放进 Today**：用 `MKDirections.calculateETA` 计算，只对有 `location`、并且在今天或明天的事件计算，结果按事件缓存。显示在 `EventRow` 的副标题里（"开车 18 分钟 · 9:42 出发"）；`NextUpWidget` 也显示同样的内容。是否用 AlarmKit 做"该出发了"的提醒，需要用户在该事件上主动打开，不能默认打开。
- **工作量**：M。**克制**：是。Apple 日历有同样的功能，这算追平。

### T5. 捏合改变显示密度
- **是什么**：在时间线上捏合，改变一屏显示几天（[Changing Timeline Size](https://bonobolabs.com/support/timepage/changing-timeline-size.md)）；Overlap 的图表也能捏合缩放时间（[Overlap Getting Started](https://bonobolabs.com/support/overlap/getting-started/)）。
- **放进 Today**：`WeekView` 已经支持 `dayCount` 为 7 或 3。可以加一个 `MagnifyGesture`：横向在 7、3、1 天之间切换，纵向连续调整 `WeekPage.hourHeight`（比如 32 到 96）。注意它和横向翻页的 `ScrollView`、以及 `DraggableTaskBlock` 拖动任务的手势冲突，要实机测试。
- **工作量**：M。**克制**：是（Apple 的做法）。

### T6. 日期底色（Day Shading）
- **是什么**：可选择隔天加底色、隔周加底色、过去的日子加底色、周末加底色、只突出今天，还有"加深"选项（[Day Shading](https://bonobolabs.com/support/timepage/day-shading.md)）。
- **放进 Today**：只做两种，并且默认打开：过去的日子文字变淡，周末列加很浅的底色。改 `WeekPage` 的列背景和 `MonthPage` 的格子。不要做 6 种选项。
- **工作量**：S。**克制**：是。

### T7. 倒计时 / 下个事件的 Live Activity
- **是什么**：倒计时小组件，可以倒数到某个事件或日期，过了之后还能正数；另外有一个下个事件倒计时的 Live Activity，显示在锁屏和灵动岛上（[Widgets](https://bonobolabs.com/support/timepage/timepage-widgets.md)）。
- **放进 Today**：`TodayWidgets/AlarmLiveActivity.swift` 已经有现成的结构。可以新做一个 `NextEventActivity`，只在用户在事件详情里点"在锁屏显示倒计时"时才启动（AI 不会替用户启动）。倒计时小组件可以扩展 `WidgetFeed.swift`。
- **工作量**：M。**克制**：是。

### T8. 小而准的动效
- **是什么**：3.7.5 版的更新说明里写到：快速滚动时间线时日期标签会变大；今天的标记更粗；从某一天打开事件的过渡更顺；月份热力图的日期更粗（[3.7.5 更新说明](https://bonobolabs.com/new/en/timepage/3.7.5/)）。说明里还提到 Day 页面有"新的光影效果"，但没有具体描述，所以这里**只记录，不提议**。
- **放进 Today**：在 `DayAgenda` 或 `WeekView` 快速滚动时，把当前日期标题放大，或者做成悬浮的日期标签。S，属于锦上添花，没有进 Top 8。

### T9. 新建事件的方式
- **是什么**：右下角有一个悬浮的 + 按钮，点一下新建今天的事件；**把 + 拖到时间线上的某一天**，就新建那一天的事件；在 Day 页面下拉也能新建（[How to Add an Event](https://bonobolabs.com/support/timepage/how-to-add-an-event.md)）。Week 视图可以按住拖出一段时间来新建（[App Store](https://apps.apple.com/app/id989178902)）。输入时会联想联系人和地点（[MacStories](https://www.macstories.net/reviews/timepage-a-beautiful-and-clever-calendar-app/)）。
- **放进 Today**：`CLAUDE.md` 的目标是右下角 +"点一下按页面添加，长按出菜单"。"把 + 拖到某一天"可以作为第三种手势，用在 Calendar 的 Month 视图上（拖到哪天就在哪天新建）。但它和长按菜单有冲突，属于"超越"阶段，先不做。Week 视图按住拖出时间段新建，Apple 日历也有，可以排进追平清单（M）。
- **时间拨盘（Time Scrubber）**：3.7.5 更新说明提到新建事件页面里有一个 Time Scrubber（[3.7.5 更新说明](https://bonobolabs.com/new/en/timepage/3.7.5/)），也就是用横向拨动来选时间，不用滚轮。可以放进 `QuickReminderSheet.swift`，规则写在 `QuickTime.swift`：在现有的预设时间和加减按钮下面加一条横向拨动条，按 15 分钟吸附，和 `TimerDial` 的吸附逻辑一致。M，没有调整 Top 8 的排序。

---

## Overlap（世界时钟）

> 注意：代码里搜不到世界时钟、秒表或天气的实现（`ios/One/` 下没有 `TimeZone(identifier:` 或 WeatherKit）。下面的提议都是在 `AlarmsView` 里**新建**区块。

### O1. 左右滑动整条时间（time scrubbing）
- **是什么**：首页每个时区是一个彩色色块。左右滑动整屏就能把时间往前或往后拨，底部显示"7 小时后"这样的偏移量，点一下回到现在（[Getting Started](https://bonobolabs.com/support/overlap/getting-started/)，[App Store](https://apps.apple.com/app/id1516950324)）。
- **为什么好用**：时区换算不用心算。"他们那边明天上午 9 点，我这边是几点"变成了手指一拨就能看到的事。
- **放进 Today**：`AlarmsView` 里放一个 `WorldClockCard`，结构跟 `TimerCard` 一样，位于它下面。每行是"城市名（可改名为人名）+ 当地时间"，整张卡片支持横向 `DragGesture`，以 15 分钟为一档变化；拨动时出现一个"+3 小时"的小标签，点它回到现在。`DayAgenda` 里已经有"Back to today"按钮，文案和交互可以统一。
- **工作量**：L（时区搜索、持久化、手势、无障碍朗读）。**克制**：是。

### O2. 用颜色表示白天、夜晚和对方方便的时间
- **是什么**：每个时区可以设置"available"时段和前后宽限；拖动时，整行颜色会随着是否在对方的可联系时段内而变化。默认主题用不同颜色区分夜晚、白天和可联系时间（[Getting Started](https://bonobolabs.com/support/overlap/getting-started/)，[Customizing](https://bonobolabs.com/support/overlap/customizing.md)，[App Store 2.0 说明](https://apps.apple.com/app/id1516950324)）。
- **为什么好用**：用颜色代替数字，一眼就能知道"现在打电话会不会吵醒对方"。
- **放进 Today**：O1 的每一行用 3 种状态色（夜晚、白天、可联系），可联系时段默认 9:00–18:00。**不做** Overlap 那种计算最佳会议时间的 Overlap Graph（太重了）。
- **工作量**：M（包含在 O1 里）。

### O3. 把拨到的时间直接做成事件
- **是什么**：分享按钮可以把选中的时间发出去，或者直接用它新建事件（[Getting Started](https://bonobolabs.com/support/overlap/getting-started/)）。
- **放进 Today**：拨动后长按某一行，菜单里出现"在这个时间新建事件"，打开现有的事件编辑器（`Editors.swift`），时间已经预先填好。是用户自己点的，符合"AI 准备、用户决定"。S（在 O1 之后做）。

---

## Actions（待办）

### A1. Review Mode：集中处理逾期任务
- **是什么**：把逾期的任务集中在一起，一张一张处理：上滑改期，下滑删除，横滑完成（[Schedule](https://bonobolabs.com/support/actions/schedule.md)）。
- **为什么好用**：把"处理逾期"变成一个有开头、有结尾的小仪式，不会越积越多。
- **放进 Today**：`DayAgenda` 里"N overdue"那一行可以加一个"逐个处理"入口。**但是**：手势要先和 Apple 提醒事项一致（左滑删除或旗标，点圆圈完成），上滑、下滑这类自创手势不能用。逐个处理时，只用按钮："今天 / 明天 / 下周 / 完成 / 删除"。符合原则 6（逾期事项一直可见，不会被悄悄挪走）。M，有条件，没进 Top 8。

### A2. 自然语言输入
- **是什么**：在标题里写"Pay rent on the 1st of every month"，就会自动识别日期、时间和重复规则（[Natural Language](https://bonobolabs.com/support/actions/natural-language-inputs.md)）。
- **现状**：Today 已经有 `AICapture` / `Understanding` / `parse` 这条链路，而且做得更多（预览卡）。不需要另外借鉴。

---

## Flow（速写本）

### F1. 笔记挂在某一天上
- **是什么**：Flow 的画布可以关联到 Timepage 的某一天（不是某个事件），在那天的 Day 页面里能看到（[Flow + Timepage](https://bonobolabs.com/support/together/flow-timepage.md)，[Day View](https://bonobolabs.com/support/timepage/navigating-day-view.md)）。
- **放进 Today**：如果以后要做"今天的笔记"，可以在 `DayAgenda` 底部放一个可折叠的"Note"块，**永远不会自动变成任务**（原则 5）。目前不在路线图上，只记录下来。
- 其他 Flow 的特点（无限画布、纸张纹理、Metal 笔刷）和 Today 无关，不展开。

---

## 不采纳（以及原因）

| Bonobo 的做法 | 为什么不采纳 |
|---|---|
| 在 Day 页面长按事件后拖动，改到别的时间或日期；横滑卡片改期（[Navigation](https://bonobolabs.com/support/timepage/navigation.md)） | 违反原则 2"会议默认不动"。我们只允许拖动**任务**，`DraggableTaskBlock` 已经实现了 |
| 用一条连续时间线**取代**月历网格 | 违反"先追平 Apple 日历"。Paste 的评测也提到有人会想念传统网格 |
| 60 多种主题色、6 组配色、在 Overlap 里下拉切换主题（[Themes](https://bonobolabs.com/support/timepage/themes.md)，[Customizing](https://bonobolabs.com/support/overlap/customizing.md)） | 不克制。最多做到跟随系统的强调色 |
| Overlap Graph（多个时区的最佳会议时间曲线） | 太重，用户量小；O2 的颜色已经覆盖了 80% 的价值 |
| "历史上的今天"、联系人头像、叫 Uber | 和"时间"无关，属于装饰或第三方服务 |
| Day 页面的"光影效果" | 来源没有具体描述，无法评估 |
| Day 页面模块可以自由排序、开关（天气、生日、Flow、历史上的今天等） | 违反"先展示事项"。Today 的结构应该固定 |

---

## 来源

- Timepage App Store：https://apps.apple.com/app/id989178902
- Overlap App Store：https://apps.apple.com/app/id1516950324
- Bonobo 合集（App Store）：https://apps.apple.com/py/app-bundle/calendar-planner-sketchbook-notebook-drawing-task-to/id1797219065?l=en-GB
- Bonobo 支持文档索引：https://bonobolabs.com/llms.txt
- Timepage Timeline：https://bonobolabs.com/support/timepage/navigating-timeline-and-day-view.md
- Timepage Day View：https://bonobolabs.com/support/timepage/navigating-day-view.md
- Timepage 手势：https://bonobolabs.com/support/timepage/navigation.md
- Timepage Heat Map：https://bonobolabs.com/support/timepage/navigating-heat-map.md
- Timepage Day Shading：https://bonobolabs.com/support/timepage/day-shading.md
- Timepage 捏合缩放：https://bonobolabs.com/support/timepage/changing-timeline-size.md
- Timepage 主题：https://bonobolabs.com/support/timepage/themes.md
- Timepage 天气：https://bonobolabs.com/support/timepage/viewing-weather-information.md
- Timepage 小组件：https://bonobolabs.com/support/timepage/timepage-widgets.md
- Timepage 新建事件：https://bonobolabs.com/support/timepage/how-to-add-an-event.md
- Timepage 3.7.5 更新说明：https://bonobolabs.com/new/en/timepage/3.7.5/
- Overlap 入门：https://bonobolabs.com/support/overlap/getting-started/
- Overlap 概览：https://bonobolabs.com/support/overlap/overlap-overview.md
- Overlap 自定义：https://bonobolabs.com/support/overlap/customizing.md
- Actions 自然语言：https://bonobolabs.com/support/actions/natural-language-inputs.md
- Actions Schedule / Review Mode：https://bonobolabs.com/support/actions/schedule.md
- Flow + Timepage：https://bonobolabs.com/support/together/flow-timepage.md
- Bonobo 关于我们：https://bonobolabs.com/about
- Bonobo 改名公告：https://bonobolabs.com/articles/name-change-announcement/
- MacStories 评测 Timepage（2015）：https://www.macstories.net/reviews/timepage-a-beautiful-and-clever-calendar-app/
- 9to5Mac Timepage 发布报道：https://9to5mac.com/2015/05/28/moleskine-iphone-app/
- Paste 评测 Timepage：https://www.pastemagazine.com/tech/ios/moleskine-timepage-ios-app-review-digital-paper
- MacStories 2019 Apple Design Award：https://www.macstories.net/news/apple-design-awards-2019-winners-announced/
