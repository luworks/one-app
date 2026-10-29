#if os(iOS)
  import Testing
  import TodayPlatform

  @Suite @MainActor struct WeatherAvailabilityTests {
    @Test func liveWeatherIsDisabledEvenWhenRequested() {
      let weather = WeatherModel()
      #expect(!weather.isAvailable)
      weather.update(enabled: true, force: true)
      #expect(weather.state == .off)
      #expect(weather.snapshot == nil)
    }
  }
#endif
