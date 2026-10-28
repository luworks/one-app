#if os(iOS)
  import CoreLocation
  import Foundation
  import Observation
  import TodayCore
  import WeatherKit

  /// Foreground-only Apple Weather access. No location or forecast is written to disk.
  @MainActor
  @Observable
  public final class WeatherModel: NSObject, CLLocationManagerDelegate {
    public enum State: Equatable { case off, loading, ready, locationDenied, unavailable }
    public private(set) var state: State = .off
    public private(set) var snapshot: WeatherSnapshot?

    @ObservationIgnored private let sample: WeatherSnapshot?
    @ObservationIgnored private var manager: CLLocationManager?
    @ObservationIgnored private var request: Task<Void, Never>?
    @ObservationIgnored private var enabled = false
    @ObservationIgnored private var waitingForLocation = false
    @ObservationIgnored private var waitingForAuthorization = false
    @ObservationIgnored private var lastSuccess: Date?
    @ObservationIgnored private var lastFailure: Date?
    @ObservationIgnored private var requestID = UUID()

    /// Live weather is held back until WeatherKit signing is configured.
    public var isAvailable: Bool { sample != nil }

    /// A sample is supplied only by development compositions.
    public init(sample: WeatherSnapshot? = nil) {
      self.sample = sample
      super.init()
    }

    public func update(enabled: Bool, force: Bool = false) {
      let enabled = enabled && isAvailable
      self.enabled = enabled
      guard enabled else {
        requestID = UUID()
        request?.cancel()
        request = nil
        manager?.stopUpdatingLocation()
        waitingForLocation = false
        waitingForAuthorization = false
        lastSuccess = nil
        lastFailure = nil
        snapshot = nil
        state = .off
        return
      }
      if let sample {
        snapshot = sample
        state = .ready
        return
      }
      let location = locationManager()
      switch location.authorizationStatus {
      case .notDetermined:
        state = .loading
        if !waitingForAuthorization {
          waitingForAuthorization = true
          location.requestWhenInUseAuthorization()
        }
      case .authorizedAlways, .authorizedWhenInUse:
        waitingForAuthorization = false
        if !force, let lastSuccess, snapshot != nil,
          Date().timeIntervalSince(lastSuccess) < 15 * 60
        {
          return
        }
        if !force, let lastFailure, Date().timeIntervalSince(lastFailure) < 5 * 60 { return }
        guard request == nil, !waitingForLocation else { return }
        state = .loading
        waitingForLocation = true
        location.requestLocation()
      case .denied, .restricted:
        waitingForAuthorization = false
        waitingForLocation = false
        requestID = UUID()
        request?.cancel()
        request = nil
        lastSuccess = nil
        lastFailure = nil
        snapshot = nil
        state = .locationDenied
      @unknown default:
        snapshot = nil
        state = .unavailable
      }
    }

    private func locationManager() -> CLLocationManager {
      if let manager { return manager }
      let manager = CLLocationManager()
      manager.desiredAccuracy = kCLLocationAccuracyKilometer
      manager.delegate = self
      self.manager = manager
      return manager
    }

    public nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
      let id = ObjectIdentifier(manager)
      Task { @MainActor [weak self] in
        guard let self, self.enabled, let current = self.manager, ObjectIdentifier(current) == id
        else { return }
        self.lastFailure = nil
        self.update(enabled: true)
      }
    }

    public nonisolated func locationManager(
      _ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]
    ) {
      let id = ObjectIdentifier(manager)
      Task { @MainActor [weak self] in
        guard let self, self.enabled, self.waitingForLocation, let current = self.manager,
          ObjectIdentifier(current) == id, let location = current.location
        else { return }
        self.waitingForLocation = false
        self.fetch(location)
      }
    }

    public nonisolated func locationManager(
      _ manager: CLLocationManager, didFailWithError error: Error
    ) {
      let id = ObjectIdentifier(manager)
      Task { @MainActor [weak self] in
        guard let self, self.enabled, let current = self.manager, ObjectIdentifier(current) == id
        else { return }
        self.waitingForLocation = false
        self.lastFailure = Date()
        self.snapshot = nil
        self.state =
          current.authorizationStatus == .denied || current.authorizationStatus == .restricted
          ? .locationDenied : .unavailable
      }
    }

    private func fetch(_ location: CLLocation) {
      let id = UUID()
      requestID = id
      request = Task { @MainActor [weak self] in
        guard let self else { return }
        do {
          let service = WeatherService.shared
          async let attribution = service.attribution
          let (current, daily, hourly) = try await service.weather(
            for: location, including: .current, .daily, .hourly)
          let legal = try await attribution
          guard
            let day = daily.first(where: {
              Calendar.current.isDate($0.date, inSameDayAs: current.date)
            })
          else { throw WeatherError.unknown }
          let hours = hourly.filter { $0.date >= current.date }.prefix(12).map { hour in
            WeatherSnapshot.Hour(
              date: hour.date, temperatureCelsius: hour.temperature.converted(to: .celsius).value,
              symbol: hour.symbolName,
              precipitationProbability: Int((hour.precipitationChance * 100).rounded()))
          }
          guard self.enabled, self.requestID == id, !Task.isCancelled else { return }
          self.snapshot = WeatherSnapshot(
            location: "Current location",
            temperatureCelsius: current.temperature.converted(to: .celsius).value,
            apparentTemperatureCelsius: current.apparentTemperature.converted(to: .celsius).value,
            highCelsius: day.highTemperature.converted(to: .celsius).value,
            lowCelsius: day.lowTemperature.converted(to: .celsius).value,
            condition: current.condition.description, symbol: current.symbolName,
            precipitationProbability: Int((day.precipitationChance * 100).rounded()),
            updatedAt: current.date, hours: hours,
            attribution: TodayCore.WeatherAttribution(
              lightMark: legal.combinedMarkLightURL, darkMark: legal.combinedMarkDarkURL,
              legalURL: legal.legalPageURL))
          self.lastSuccess = Date()
          self.lastFailure = nil
          self.state = .ready
        } catch {
          guard self.enabled, self.requestID == id, !Task.isCancelled else { return }
          self.snapshot = nil
          self.lastFailure = Date()
          self.state = .unavailable
        }
        if self.requestID == id { self.request = nil }
      }
    }
  }
#endif
