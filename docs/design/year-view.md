# Year view: every mark needs a reason

Mockup: `docs/design/year-view.html` (published privately: https://claude.ai/artifact/8qYkDirW8FCx1QSKoJrE4P).

## 中文摘要

现在的年视图几乎每天都被涂成橙色,因为"忙碌程度"把所有东西都数进去了:每天的站会、每周的例会、订阅的日历(假日、体育赛程、生日)、旅行的每一天,而且阈值是固定数字(1-2、3-4、5+),只要工作日有一个重复事项,整年就全亮了,颜色因此没有信息。
我的建议是只保留四个有明确含义的标记:红色日期数字 = 节日/假日(按设置里的地区集合计算,不依赖网络),彩条 = 持续多天的全天事件(用该日历自己的颜色),灰色底 = "对你来说特别忙的一天"(只数你自己的一次性事项,并且只标记你最忙的前 10%,至少 3 项),红圈 = 今天。
周末淡化、选中框、截止日小点、生日小点全部砍掉:Apple 的年视图没有这些,格子只有约 15pt 宽,标记一多就又是"彩虹"。
右上角的 i 按钮打开一张图例,点任何一天可以看到它为什么被标记。
第一步(这次已实现)是修正计数规则 + 按你自己的基线取百分位 + 内置节日表 + 设置里的节日开关;彩条、图例之外的内容留到后面。需要你决定的 4 个问题见文末。

## 1. Diagnosis

The Year heat counts everything, and the thresholds are absolute, so a normal week lights every weekday.

- `YearView.countDays` adds one for every `CalEntry` from `CalendarEntries.make`: Today's own events (every occurrence of a repeating one), every Apple Calendar event from every visible calendar (the `repeats` flag exists on the entry but is only used for alarms), planned tasks, and one-time alarms. Only repeating *alarms* are skipped.
- That includes subscribed calendars (US Holidays, sports schedules, Birthdays), so a holiday makes a day "busy". A five-day trip adds one to each of its five days, so it reads as five lightly busy days, not as a trip.
- `CalendarLayout.busyLevel` is 1-2 / 3-4 / 5+ in absolute numbers. A person with a daily standup (weekdays) and a weekly sync is at level 1 on every weekday and level 2 on Tuesdays all year. The test dataset has exactly this: "Standup" repeats on weekdays.
- All three levels are one hue (the accent orange at 16 / 34 / 58 percent), so the only information left is "how many items", and that number is mostly routine.
- Reminders that have a due date but no planned time are not counted at all, so the one thing that really is "due" never shows.

In the mockup's example year (standup, weekly sync, sports on weekends, holidays, four trips) the current rule shades 325 of 365 days, 89 percent. That matches the screenshot: Jul 2026 to Jun 2027 almost entirely peach.

## 2. Evaluating the ingredients

The test for every mark: it must say something you did not already know, and tapping the day must show you why.

| Ingredient | Verdict | Why |
|---|---|---|
| (a) Holidays and festivals | Keep | Fixed, rare (about 15 days a year per set), and the first thing you look for in a year. Red day number, no fill. |
| (b) Multi-day events as a band | Keep | The only place a real calendar color is useful: a trip is a span and a band is a span. Uses the calendar's own color, so it needs no legend entry beyond "event that lasts days". |
| (c) Deadlines as a dot | Cut as a mark; count toward busy | A dot on every day with a dated reminder repeats the saturation problem for anyone with a full Reminders list. A reminder still due counts toward "busy" instead. Revisit only if users ask. |
| (d) Unusually busy | Keep | Relative to your own baseline, so it always marks a few days and never all of them. One quiet gray tint, no intensity levels. |
| (e) Today, weekends, selected day | Today only | Today is Apple's red circle. Weekend dimming and a selection ring are not in Apple's Year view and cost legibility in 15-pt cells. The Year has no selected day to show. |
| (f) Birthdays | Cut | One mark per person: dozens a year for a normal contact list. Birthdays stay in Month and Today, and are excluded from the busy count. |
| (g) Legend | Keep | An "i" button at the trailing edge of the year title opens a small key listing only the marks that exist. Tapping a day shows the reason. |

Recommended combination, called B in the mockup: **holiday number, trip band, busy tint, today circle.** Variant A leaves out the busy tint (safest); variant C adds dots, birthdays, weekend and selection to show why they are cut.

### Marks and their meaning

| Mark | Meaning | Light and dark |
|---|---|---|
| Red day number, bold | A holiday or festival from your chosen sets (and Apple's Holidays calendar, step 4) | System red, lighter in dark mode |
| Colored band across the days | An all-day event of two or more days, in its calendar's color (trip, conference, leave) | Calendar color at 24 percent in light, 34 percent in dark (same as `EventTint`) |
| Gray rounded tint behind the number | Unusually busy for you: at least 3 of your own one-off items, in the top tenth of your active days | Primary at 16 percent in light, 22 in dark; the app accent is no longer used in Year |
| Red filled circle | Today (as Apple) | System red |

Precedence on one day: today beats everything; a band beats a busy tint (you are away, not busy); a holiday number color combines with a band or tint.

### The rule for "unusually busy"

- Load of a day = your own one-off items that day: Today events and Apple Calendar events that do not repeat, planned tasks, and reminders still due (from today on, not done, not repeating).
- Not counted: repeating items (a daily standup says nothing about one day), calendars that are subscribed, Birthdays or named like holidays, and all-day events that last two or more days (trips are spans).
- Baseline = the days of the visible year that have a load of at least 1. Threshold = the larger of 3 and the 90th percentile of those days. Mark days at or above the threshold. If that marks more than 15 percent of the active days (ties), raise the threshold to the next distinct value until it fits.
- Edges: an empty year marks nothing. A year where every active day is equally full marks nothing (nothing is unusual). A sparse future year still needs 3 items, so a day with one dentist visit never lights up.
- In the mockup: 8 days of 139 active days.

### Holidays

Two sources, combined by day (so nothing needs deduplication, a day is either marked or not):

1. **Built-in rules** (step 1, implemented): computed for any year, no table to expire, works offline and under `-uiTesting`.
   - United States: New Year's Day, Martin Luther King Jr. Day (3rd Monday of Jan), Presidents' Day (3rd Monday of Feb), Memorial Day (last Monday of May), Juneteenth, Independence Day, Labor Day (1st Monday of Sep), Columbus Day (2nd Monday of Oct), Veterans Day, Thanksgiving (4th Thursday of Nov), Christmas Day.
   - China: New Year's Day, Chinese New Year's Eve, Spring Festival, Lantern Festival, Qingming, Labour Day, Dragon Boat, Mid-Autumn, National Day. The lunar dates come from Foundation's `Calendar(identifier: .chinese)` read on China Standard Time and skipping leap months. Qingming is a solar term (April 4 or 5), by the standard 21st-century formula, valid 2001-2100.
   - International: New Year's Day, Valentine's Day, Easter (computus), Mother's Day (2nd Sunday of May), Father's Day (3rd Sunday of June), Halloween, Christmas Day.
   - Checked dates: Spring Festival is Feb 17, 2026 and Feb 6, 2027 (not Feb 17, 2027); Mid-Autumn Sep 25, 2026; Thanksgiving Nov 26, 2026; Easter Apr 5, 2026; Dragon Boat Jun 19, 2026.
2. **Apple's own Holidays calendar** (step 4): EventKit cannot tell which calendar is "the holiday one". The heuristic is a subscribed calendar (`EKCalendarType.subscription`) or a calendar whose title contains "holiday", "节假日", "节日" or "假期" (Google's holiday calendars are CalDAV, not subscriptions, so the title check is needed). Single-day all-day events in such calendars mark their day. This is optional: step 1 already works for users without it, and respects Settings → Calendars if the calendar is hidden.

The default sets follow `Locale.current.region`: US gives United States and International; CN, HK, MO, TW, SG give China and International; anything else gives International. Settings → Calendar → Holidays in Year lets the user switch each set (or all) off.

### Tap behaviour

Stays as Apple Calendar: tapping a month opens Month. A 15-pt day cell is below any tap target, so day taps wait for step 4 (a tap on a day number opens Month with that day selected; Month's own second tap opens it in Today). The "why is this marked" explanation lives in the month's VoiceOver value ("Thanksgiving, 1 busy day") in step 1 and in a sheet in step 4.

## 3. Edge cases

- **No Holidays calendar, or Apple Calendar off**: the built-in sets are the only source. Nothing breaks, because they use no EventKit.
- **Calendars hidden in Settings**: hidden calendars contribute nothing to the busy count, bands, or the Apple holiday source (they already do not appear in `CalendarEntries.make`). Built-in holidays are separate and follow their own Settings toggle.
- **Birthdays**: `EKCalendarType.birthday` is treated as background: no mark, no load.
- **All-day versus timed**: only all-day events lasting two or more days become bands. A timed overnight event (22:00 to 02:00) counts as load on both days. A single all-day event counts as 1 load on its day.
- **Time zones**: holiday dates are `DayKey` (year, month, day) numbers, never instants, so they cannot slip a day when the phone travels. EventKit all-day events are floating dates in the device's zone. Lunar festivals are read in China time because the festival date is the date in China.
- **Observed holidays** (July 4 on a Saturday observed on Friday), China's make-up working days and extended holiday blocks: not supported. Cut for now, say so in the key if added later.
- **Performance**: a year is one cached EventKit query, as today. Holidays are computed per year and cached; the Chinese calendar walk is 365 days and only runs when the China set is on.

## 4. What to cut

Weekend dimming, selection ring, deadline dots, birthday marks, per-level intensity, a rainbow of per-calendar dots, and any count on the day cell. If a mark needs a paragraph to explain, it does not belong in a 15-pt cell.

## 5. Settings

A new Settings section "Calendar" with one row, **Holidays in Year**, that opens three switches (United States, China, Christmas, Easter and more) with a one-line example under each. Stored as `today.setting.yearHolidays` ("auto" means follow the region). No birthday setting because birthdays are not shown. Later: "Use Apple's holidays calendar" (on by default) at step 4.

## 6. Plan and effort

1. **S1 (small, done in this change)**: load rule (own, one-off, no trips, no background calendars, plus due reminders), percentile baseline, computed holiday sets, Settings row, key sheet, month accessibility value, unit tests and one UI test. Removes the orange heat.
2. **S2 (medium)**: trip bands (week-row segmenting in `MiniMonth`, calendar colors, a11y).
3. **S3 (small)**: key sheet lists only the marks that exist this year.
4. **S4 (medium)**: Apple's Holidays calendar via the heuristic above; tap on a day number.
5. **S5 (large, probably never)**: observed holidays, China make-up working days, regional sets beyond US and China.

## 7. Questions for you

1. **Hide birthdays entirely from Year?** Recommendation: yes. They stay in Month and Today. The alternative, a small dot, would be one of the clutter sources in variant C.
2. **Mark all festivals the same (red number), or separate days off from festivals like Halloween and Valentine's Day?** Recommendation: the same for now. Two tiers need a second visual and the key gets longer; ask again if people read red as "day off".
3. **Which sets are on by default?** Recommendation: follow the phone's region (US gives US plus Christmas, Easter and more; CN gives China plus those). You can change it in Settings. Do you want China on for you regardless of the region?
4. **Is a busy line of "3 or more of your own one-off items, top tenth of days" right?** Recommendation: yes, start there and tune from your own year once step 1 is on your phone.
