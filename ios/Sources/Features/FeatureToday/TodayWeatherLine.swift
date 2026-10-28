#if os(iOS)
  import SwiftUI
  import TodayCore

  /// A compact read-only summary with an hourly detail sheet, alongside the Health summary.
  package struct TodayWeatherLine: View {
    let snapshot: WeatherSnapshot
    @Environment(\.locale) private var locale
    @State private var showsDetails = false

    package init(snapshot: WeatherSnapshot) {
      self.snapshot = snapshot
    }

    package var body: some View {
      Button {
        showsDetails = true
      } label: {
        HStack(spacing: 6) {
          Image(systemName: snapshot.symbol).foregroundStyle(.secondary)
          Text(
            "\(WeatherFormat.temperature(snapshot.temperatureCelsius, locale: locale)) · \(snapshot.condition)"
          )
          .font(.footnote).foregroundStyle(.secondary).monospacedDigit()
          Spacer(minLength: 0)
          AppleWeatherMark(attribution: snapshot.attribution)
          Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(
            .tertiary)
        }
        .frame(minHeight: 36)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .listRowSeparator(.hidden)
      .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
      .accessibilityIdentifier("weather.summary")
      .accessibilityHint("Shows weather details")
      .sheet(isPresented: $showsDetails) {
        NavigationStack {
          WeatherDetail(snapshot: snapshot)
        }
        .presentationDragIndicator(.visible)
      }
    }
  }

  private struct WeatherDetail: View {
    let snapshot: WeatherSnapshot
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss

    private func temperature(_ value: Double) -> String {
      WeatherFormat.temperature(value, locale: locale)
    }

    var body: some View {
      List {
        Section(snapshot.location) {
          Label(
            "\(temperature(snapshot.temperatureCelsius)) · \(snapshot.condition)",
            systemImage: snapshot.symbol)
          LabeledContent("Feels like", value: temperature(snapshot.apparentTemperatureCelsius))
          LabeledContent("High", value: temperature(snapshot.highCelsius))
          LabeledContent("Low", value: temperature(snapshot.lowCelsius))
          if let probability = snapshot.precipitationProbability {
            LabeledContent("Chance of precipitation", value: "\(probability)%")
          }
        }
        if !snapshot.hours.isEmpty {
          Section("Hourly forecast") {
            ForEach(snapshot.hours) { hour in
              HStack {
                Text(hour.date, format: .dateTime.hour())
                Image(systemName: hour.symbol).foregroundStyle(.secondary)
                Spacer()
                if let probability = hour.precipitationProbability {
                  Text("\(probability)%").foregroundStyle(.secondary)
                }
                Text(temperature(hour.temperatureCelsius)).monospacedDigit()
              }
            }
          }
        }
        Section {
          LabeledContent(
            "Updated", value: snapshot.updatedAt.formatted(date: .omitted, time: .shortened))
          Link(destination: snapshot.attribution.legalURL) {
            HStack {
              AppleWeatherMark(attribution: snapshot.attribution)
              Spacer()
              Text("Weather data sources")
              Image(systemName: "arrow.up.right")
            }
          }
          .accessibilityLabel("Weather data sources")
          .accessibilityIdentifier("weather.attribution")
        }
      }
      .navigationTitle("Weather")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
      }
    }
  }

  private struct AppleWeatherMark: View {
    let attribution: WeatherAttribution
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
      AsyncImage(url: colorScheme == .dark ? attribution.lightMark : attribution.darkMark) {
        image in
        image.resizable().scaledToFit()
      } placeholder: {
        Text("Weather").font(.caption2).foregroundStyle(.secondary)
      }
      .frame(width: 64, height: 18)
      .accessibilityLabel("Apple Weather")
    }
  }
#endif
