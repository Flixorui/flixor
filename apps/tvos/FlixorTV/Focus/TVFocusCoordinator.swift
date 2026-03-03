import Foundation

@MainActor
final class TVFocusCoordinator: ObservableObject {
    static let shared = TVFocusCoordinator()

    @Published private var memoryByScreen: [String: TVFocusMemory] = [:]

    func remember(screen: String, sectionID: String, itemID: String?) {
        var memory = memoryByScreen[screen] ?? TVFocusMemory()
        memory.lastSectionID = sectionID
        if let itemID, !itemID.isEmpty {
            memory.lastItemIDsBySection[sectionID] = itemID
        }
        memoryByScreen[screen] = memory
    }

    func remember(screen: TVScreenID, sectionID: String, itemID: String?) {
        remember(screen: screen.rawValue, sectionID: sectionID, itemID: itemID)
    }

    func lastFocusedSection(screen: String) -> String? {
        memoryByScreen[screen]?.lastSectionID
    }

    func lastFocusedSection(screen: TVScreenID) -> String? {
        lastFocusedSection(screen: screen.rawValue)
    }

    func lastFocusedItem(screen: String, sectionID: String) -> String? {
        memoryByScreen[screen]?.lastItemIDsBySection[sectionID]
    }

    func lastFocusedItem(screen: TVScreenID, sectionID: String) -> String? {
        lastFocusedItem(screen: screen.rawValue, sectionID: sectionID)
    }

    func clear(screen: String) {
        memoryByScreen[screen] = nil
    }

    func clear(screen: TVScreenID) {
        clear(screen: screen.rawValue)
    }
}
