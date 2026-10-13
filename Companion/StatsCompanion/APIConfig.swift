import Foundation

enum APIConfig {
    static let apiHost = URL(string: "https://api.system-stats.com")!
    static let authHost = URL(string: "https://oauth.system-stats.com")!
    static let appHost = URL(string: "https://app.system-stats.com")!
    static let oauthClientID = "stats"
    static let keychainService = "eu.exelban.stats.companion"
}
