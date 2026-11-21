import Foundation
import Observation

/// Lets one tab ask another to open something (e.g. Discover → a chat).
@Observable
final class AppRouter {
    var tab = 0
    var pendingPersonaID: UUID?
}
