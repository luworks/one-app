import SwiftUI
import TodayShared
import WidgetKit

/// Lock Screen rectangular: the next item only (see Shared/LockScreenNext.swift for the words).
/// Line 1 is the bold time with a live countdown; lines 2-3 are the title, which may wrap (CJK wraps per character).
struct LockScreenNextView: View {
  let model: LockScreenNext

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      firstLine
      if !model.title.isEmpty {
        Text(model.title)
          .font(.subheadline)
          .foregroundStyle(model.isEmpty ? .secondary : .primary)
          .lineLimit(2)
          .minimumScaleFactor(0.9)
          .multilineTextAlignment(.leading)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(model.accessibilityLabel))
  }

  private var firstLine: some View {
    HStack(spacing: 4) {
      if model.showsAlarmSymbol {
        Image(systemName: "alarm.fill")
          .font(.footnote)
          .widgetAccentable()
      }
      Text(model.headline)
        .font(.callout.weight(.bold))
        .monospacedDigit()
        .widgetAccentable()
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .layoutPriority(2)
      lead
      Spacer(minLength: 0)
      if let more = model.more {
        Text(more)
          .font(.caption2.weight(.semibold))
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .fixedSize()
          .layoutPriority(3)
      }
    }
  }

  @ViewBuilder private var lead: some View {
    switch model.lead {
    case .none:
      EmptyView()
    case .countdown(let start):
      // "· in 24:59": a timer the system keeps ticking. (.relative would say "24 min, 59 sec": too wide for half a Lock Screen.)
      // Timer text grows to all the width it is offered, hence the fixed width (the window is under an hour: "59:59").
      HStack(spacing: 3) {
        Text("· in")
        Text(start, style: .timer)
          .monospacedDigit()
          .frame(maxWidth: 46, alignment: .leading)
      }
      .font(.footnote)
      .lineLimit(1)
      .minimumScaleFactor(0.8)
    case .text(let words):
      Text("· \(words)")
        .font(.footnote)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
  }
}
