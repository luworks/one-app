import AppIntents
import One

struct TodayIntentsPackage: AppIntentsPackage {
  static var includedPackages: [any AppIntentsPackage.Type] { [OneIntentsPackage.self] }
}
