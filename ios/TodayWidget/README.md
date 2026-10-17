# Today date widget (source only, not in the Xcode project yet)

`TodayWidget.swift` shows the weekday and day of the month (home-screen small widget plus Lock Screen circular and rectangular) and refreshes after midnight. It needs no shared data, so no App Group.

The folder is deliberately not referenced by `One.xcodeproj`, so it cannot affect the app build. To turn it on in Xcode:

1. File > New > Target > Widget Extension. Name `TodayWidget`, uncheck Live Activity and Configuration Intent, embed in `One`.
2. Delete the template Swift file Xcode generated, then add this folder's `TodayWidget.swift` to the new target.
3. Bundle identifier `com.luworks.one.TodayWidget`, same team as the app, deployment target iOS 17 or later.
4. Run, then long-press the Home Screen > + > Today.
