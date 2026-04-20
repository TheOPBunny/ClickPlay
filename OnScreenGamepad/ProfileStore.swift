import Foundation

/// Persists profiles to ~/Library/Application Support/OnScreenGamepad/profiles.json
/// Posts `profilesDidChange` notification when anything changes.
final class ProfileStore {

    static let shared = ProfileStore()
    static let profilesDidChange = Notification.Name("profilesDidChange")

    private(set) var profiles: [Profile] = []
    private(set) var activeProfileID: UUID

    var activeProfile: Profile {
        profiles.first { $0.id == activeProfileID } ?? profiles[0]
    }

    private let fileURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("OnScreenGamepad")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("profiles.json")
    }()

    private init() {
        let def = Profile.makeDefault()
        activeProfileID = def.id
        load(defaultProfile: def)
    }

    // MARK: - Persistence

    private func load(defaultProfile: Profile) {
        guard let data = try? Data(contentsOf: fileURL),
              let saved = try? JSONDecoder().decode(SavedData.self, from: data) else {
            profiles = [defaultProfile]
            activeProfileID = defaultProfile.id
            return
        }
        profiles = saved.profiles.isEmpty ? [defaultProfile] : saved.profiles
        activeProfileID = saved.activeProfileID ?? profiles[0].id
    }

    func save() {
        let saved = SavedData(profiles: profiles, activeProfileID: activeProfileID)
        if let data = try? JSONEncoder().encode(saved) {
            try? data.write(to: fileURL)
        }
        NotificationCenter.default.post(name: ProfileStore.profilesDidChange, object: nil)
    }

    // MARK: - Mutations

    func setActive(_ id: UUID) {
        activeProfileID = id
        save()
    }

    func upsert(_ profile: Profile) {
        if let idx = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[idx] = profile
        } else {
            profiles.append(profile)
        }
        save()
    }

    func delete(_ id: UUID) {
        guard profiles.count > 1 else { return }
        profiles.removeAll { $0.id == id }
        if activeProfileID == id { activeProfileID = profiles[0].id }
        save()
    }

    func duplicate(_ id: UUID) {
        guard var src = profiles.first(where: { $0.id == id }) else { return }
        src.id = UUID()
        src.name = src.name + " Copy"
        profiles.append(src)
        save()
    }

    func updateActiveProfileSize(width: Double, height: Double) {
        guard let idx = profiles.firstIndex(where: { $0.id == activeProfileID }) else { return }
        profiles[idx].padWidth = width
        profiles[idx].padHeight = height
        save()
    }

    // MARK: -

    private struct SavedData: Codable {
        var profiles: [Profile]
        var activeProfileID: UUID?
    }
}
