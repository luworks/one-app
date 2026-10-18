# Health: which metrics, and a denser list

**中文摘要。** Health 面板从「每个指标一张大卡片」改成「分组的紧凑列表」：每行 56–64pt，左边是指标名、最新值（大号数字 + 小号单位）和一个很淡的日期标签（Today / Yesterday / 日期），右边是最近 7 天的小迷你图（累计型用柱，点状型用点线）。点一行进入详情（7 / 30 / 90 天切换、一张干净的图、平均/最低/最高和与上一段的变化），不生成任何文字总结。默认只显示 3 项：步数、睡眠、体重（只靠 iPhone 就有数据）；其余（静息心率、活动能量、锻炼分钟、步行+跑步距离、体脂、正念分钟、日照时间）放在「Add metric」里让用户自己加。不提供站立小时、HRV、噪声暴露，以及任何临床指标（血氧、血压、血糖）。所有数据只读 Apple Health，只存「选了哪些、什么顺序」，健康数值不落盘。

Status: design note for the compact metrics list (Health sheet). Product stance unchanged: no 5th tab, Today shows one quiet health line (can be switched off) that opens the Health sheet, Today only reads Apple Health, nothing leaves the device.

## (a) Which metrics are worth offering

Today is a time planner. A health number earns a place only if it helps answer "how much can I plan on this day?" or "did I leave room for my body?". It must also be a plain measurement, not a judgement.

| Metric | Source | Needs Watch? | Verdict | Why |
|---|---|---|---|---|
| Steps | iPhone | no | **Default** | The one number everybody understands; iPhone alone has it; already the first half of the Today line. |
| Sleep (time asleep) | iPhone or Watch or third-party app | no (iPhone alone only if an app writes it) | **Default** | The best single input for planning a day (what to move, what to protect). Already the second half of the Today line. |
| Weight | scale, manual entry | no | **Default** | Works with no hardware; the third thing people open Health for. Slow-moving, so it shows its date, not "today". |
| Resting heart rate | Watch | yes | Add metric | A recovery signal, but without a Watch the row would be a permanent "—". Not a default for that reason (the old README also excluded it). |
| Active energy | iPhone estimate, Watch is better | partly | Add metric | A familiar daily total. iPhone-only values are rough. |
| Exercise minutes | Watch | yes | Add metric | Plain minutes, useful when planning workouts. Empty without a Watch, so opt-in. |
| Walking + running distance | iPhone | no | Add metric | Same source as steps, in mi/km. Offered for people who think in distance. |
| Body fat | smart scale, manual | no | Add metric | Only present for people who record it, so it is opt-in. |
| Mindful minutes | Mindfulness apps, Watch | no | Add metric | A time-block people schedule on purpose; a plain minutes total fits a planner. |
| Time in daylight | iPhone, Watch | no | Add metric | "Did I get outside today" is a planning question. Plain minutes. |
| Stand hours | Watch (category type) | yes | **Do not offer** | A Fitness ring component, not a measurement. Only meaningful inside the ring, which Fitness shows better. |
| HRV | Watch | yes | **Do not offer** | One number with no personal baseline invites diagnosis and coaching ("is mine bad?"). We do not interpret health. |
| Noise exposure | iPhone, Watch | partly | **Do not offer** | Hearing protection, not planning. |
| Blood oxygen, blood pressure, glucose, ECG, cycle, medication | various | - | **Do not offer** | Clinical. Wrong place, wrong risk, and Apple Health does it properly. |

Default set: **Steps, Sleep, Weight** (three rows). Three, not four, because each default must show real data on an iPhone with no Watch; a fourth default would be an empty "—" row for many people. Everything else is one tap away under Add metric.

Rules that stay: no scores, no goals (the old 10,000-steps ring is gone), no streaks, no coaching text, no notifications, no writing to Apple Health, no health values stored by Today. Only the choice and order of metrics is saved (UserDefaults, a short JSON list of ids).

## (b) What ChatGPT's Health list does well, and what not to copy

Does well (we copy the structure):

- Compact rows: metric name, then the latest value in a large number with a small unit and a quiet date label ("173 kcal · Today"). One glance, no card chrome.
- A tiny sparkline per row, so trend is visible without opening anything. Bars for totals, dots for single readings.
- Grouping (Activity / Heart / Blood / Body) in a few rounded containers instead of one card per metric. Many metrics fit one screen.
- The date label is honest: stale data says its date ("October 14, 2026"), it does not pretend to be today.
- Detail is one sheet: big latest value, a range, one chart, a few facts.

Not copied:

- AI summary text blocks and the "Follow up" button. AI preparing health summaries is a later decision; the detail sheet is factual only.
- The Records / Accounts tabs and the account-linking flow. We read Apple Health directly, on device.
- Clinical metrics (blood oxygen, blood pressure, glucose) and HRV read as a diagnosis.
- Long date strings like "October 14, 2026" on every row. We say Today / Yesterday and fall back to "Oct 14".

## (c) Our current problems

Read from `HealthView.swift` and the old tab-version screenshot (`docs/health/health-light.png` at commit c650ffd, since replaced):

- One card per metric, each `secondarySystemFill` with 16pt padding on every side and a 12pt gap between title, value and content. Measured on the old screenshot, the steps card is about 270pt tall for one number and seven bars, weight about 300pt, sleep about 330pt. Three metrics fill two screens.
- The cards are full width with the value on the left and a lot of empty space on the right; the goal ring is decoration that adds a goal we do not otherwise have.
- Charts sit on the list, so every metric pays for a chart even when you only want today's number.
- Each card invents its own chrome (colored title, different footnotes, different tints), so adding a fourth metric means a fourth hand-built card.

Target: 3 default metrics in about 220pt instead of about 900pt, and a design where a new metric is one catalog entry.

## (d) Proposed layout

List (inset grouped, one rounded container per group, rows 56-64pt):

```
Health                                   (...)  Done

ACTIVITY
+------------------------------------------------+
| Steps                                          |
| 6,240 steps  Today                  |.|.|#|#|.|#|
+------------------------------------------------+
SLEEP & RECOVERY
+------------------------------------------------+
| Sleep                                          |
| 7 hr 12 min  Today                  |#|#|.|#|#|#|
+------------------------------------------------+
BODY
+------------------------------------------------+
| Weight                                         |
| 70.3 kg  Oct 14                     . .'. . . .|
+------------------------------------------------+

  + Add metric

Sample data. Today only reads Apple Health ...   Open Health
```

Right of every row: a sparkline of the last 7 days in one accent (pink, the heart on the Today line): bars for totals (steps, sleep, energy, minutes, distance), dots joined by a thin line for readings (weight, heart rate, body fat). Missing days are a faint dot, no data at all is a row of faint dots. Missing or stale values show "—" and the date, never a zero.

Row interactions: tap opens the detail; swipe from the right shows Hide (it only hides the row, nothing is deleted from Apple Health); long-press menu has Hide, Move Up, Move Down; press-hold-drag reorders inside a group. No Edit button.

Detail sheet:

```
Weight
70.3 kg   Oct 14

[ 7 Days ] [ 30 Days ] [ 90 Days ]

 71 +-----------------------------------+
    |  .   .                            |
 70 |      . .   .  .   .               |
    +-----------------------------------+
    Jul 20    Aug 19    Sep 18    Oct 17

 Average      Low        High
 70.6 kg      70.1 kg    71.2 kg
 -0.4 kg vs previous 90 days
```

Manage Metrics: a sheet listing every supported metric, grouped, each with a one-line description and a visibility toggle. Shown metrics start on; hidden metrics start off. Done or dismissing the sheet saves visibility, retaining the order of existing rows. Only newly shown metrics request Apple Health read access, after the sheet closes. Today's line is unchanged (steps + sleep) while both are shown; if either is hidden it uses the first two shown metrics that have a value for today.
