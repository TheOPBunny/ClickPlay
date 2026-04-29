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

    var activeResolvedProfile: Profile {
        resolvedProfile(for: activeProfile)
    }

    var activeResolvedProfileTitle: String {
        resolvedProfileTitle(for: activeProfile)
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
            profiles = [reconciledSubProfileSwitchButtons(in: defaultProfile.asTopLevelContainer())]
            activeProfileID = defaultProfile.id
            return
        }
        profiles = (saved.profiles.isEmpty ? [defaultProfile] : saved.profiles).map {
            reconciledSubProfileSwitchButtons(in: $0.asTopLevelContainer())
        }
        activeProfileID = saved.activeProfileID ?? profiles[0].id
        if !profiles.contains(where: { $0.id == activeProfileID }) {
            activeProfileID = profiles[0].id
        }
    }

    func save() {
        profiles = profiles.map { reconciledSubProfileSwitchButtons(in: $0.normalizedActiveSubProfileSelection()) }
        let saved = SavedData(profiles: profiles, activeProfileID: activeProfileID)
        if let data = try? JSONEncoder().encode(saved) {
            try? data.write(to: fileURL)
        }
        NotificationCenter.default.post(name: ProfileStore.profilesDidChange, object: nil)
    }

    func resolvedProfile(for profile: Profile) -> Profile {
        guard !profile.subProfiles.isEmpty else {
            return profile
        }

        if let activeSubProfileID = profile.activeSubProfileID,
           let activeSubProfile = profile.subProfiles.first(where: { $0.id == activeSubProfileID }) {
            return activeSubProfile
        }

        return profile.subProfiles[0]
    }

    func resolvedProfileTitle(for profile: Profile) -> String {
        guard !profile.subProfiles.isEmpty else {
            return profile.name
        }

        return "\(profile.name) / \(resolvedProfile(for: profile).name)"
    }

    func parentProfile(containingSubProfileID subProfileID: UUID) -> Profile? {
        profiles.first { profile in
            profile.subProfiles.contains { $0.id == subProfileID }
        }
    }

    func selectedEditorProfile() -> Profile {
        activeResolvedProfile
    }

    // MARK: - Mutations

    func setActive(_ id: UUID) {
        guard profiles.contains(where: { $0.id == id }) else {
            NSLog("[ProfileStore] Ignoring setActive for unknown profile id \(id.uuidString)")
            return
        }

        guard activeProfileID != id else {
            return
        }

        activeProfileID = id
        save()
    }

    func upsert(_ profile: Profile) {
        let profile = reconciledSubProfileSwitchButtons(in: profile.asTopLevelContainer())
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

    @discardableResult
    func duplicate(_ id: UUID) -> Profile? {
        guard let sourceProfile = profiles.first(where: { $0.id == id }) else { return nil }
        let src = sourceProfile.copyWithNewIDs()
        profiles.append(src)
        save()
        return src
    }

    func updateActiveProfileDisplaySize(width: Double, height: Double) {
        guard let idx = profiles.firstIndex(where: { $0.id == activeProfileID }) else { return }
        if let subProfileIndex = activeSubProfileIndex(in: profiles[idx]) {
            profiles[idx].subProfiles[subProfileIndex].displayPadWidth = width
            profiles[idx].subProfiles[subProfileIndex].displayPadHeight = height
        } else {
            profiles[idx].displayPadWidth = width
            profiles[idx].displayPadHeight = height
        }
        save()
    }

    func setActiveSubProfile(_ subProfileID: UUID, in parentProfileID: UUID) {
        guard let parentIndex = profiles.firstIndex(where: { $0.id == parentProfileID }) else {
            NSLog("[ProfileStore] Ignoring setActiveSubProfile for unknown parent id \(parentProfileID.uuidString)")
            return
        }

        guard profiles[parentIndex].subProfiles.contains(where: { $0.id == subProfileID }) else {
            NSLog("[ProfileStore] Ignoring setActiveSubProfile for unknown sub-profile id \(subProfileID.uuidString)")
            return
        }

        let parentChanged = activeProfileID != parentProfileID
        let childChanged = profiles[parentIndex].activeSubProfileID != subProfileID
        guard parentChanged || childChanged else {
            return
        }

        activeProfileID = parentProfileID
        profiles[parentIndex].activeSubProfileID = subProfileID
        save()
    }

    func setActiveSubProfile(_ subProfileID: UUID) {
        guard let parentProfile = parentProfile(containingSubProfileID: subProfileID) else {
            NSLog("[ProfileStore] Ignoring setActiveSubProfile for unknown sub-profile id \(subProfileID.uuidString)")
            return
        }

        setActiveSubProfile(subProfileID, in: parentProfile.id)
    }

    func upsertSubProfile(_ subProfile: Profile, in parentProfileID: UUID) {
        guard let parentIndex = profiles.firstIndex(where: { $0.id == parentProfileID }) else { return }
        let previousNames = subProfileNames(in: profiles[parentIndex])
        var savedSubProfile = subProfile
        savedSubProfile.subProfiles = []
        savedSubProfile.activeSubProfileID = nil

        if let childIndex = profiles[parentIndex].subProfiles.firstIndex(where: { $0.id == savedSubProfile.id }) {
            profiles[parentIndex].subProfiles[childIndex] = savedSubProfile
        } else {
            profiles[parentIndex].subProfiles.append(savedSubProfile)
        }

        profiles[parentIndex] = reconciledSubProfileSwitchButtons(
            in: profiles[parentIndex].normalizedActiveSubProfileSelection(),
            previousNames: previousNames
        )
        if profiles[parentIndex].activeSubProfileID == nil {
            profiles[parentIndex].activeSubProfileID = savedSubProfile.id
        }
        save()
    }

    @discardableResult
    func addSubProfile(to parentProfileID: UUID, fromTemplate: Bool) -> Profile? {
        guard let parentIndex = profiles.firstIndex(where: { $0.id == parentProfileID }) else { return nil }
        let nextIndex = profiles[parentIndex].subProfiles.count + 1
        var subProfile = fromTemplate
            ? Profile.makeStarterTemplate(name: "Layer \(nextIndex)")
            : Profile.makeBlank(name: "Layer \(nextIndex)")
        subProfile.subProfiles = []
        subProfile.activeSubProfileID = nil
        profiles[parentIndex].subProfiles.append(subProfile)
        profiles[parentIndex].activeSubProfileID = subProfile.id
        profiles[parentIndex] = reconciledSubProfileSwitchButtons(in: profiles[parentIndex])
        activeProfileID = parentProfileID
        save()
        return subProfile
    }

    @discardableResult
    func duplicateSubProfile(_ subProfileID: UUID, in parentProfileID: UUID) -> Profile? {
        guard let parentIndex = profiles.firstIndex(where: { $0.id == parentProfileID }),
              let sourceSubProfile = profiles[parentIndex].subProfiles.first(where: { $0.id == subProfileID }) else {
            return nil
        }

        let duplicatedSubProfile = sourceSubProfile.copyWithNewIDs()
        profiles[parentIndex].subProfiles.append(duplicatedSubProfile)
        profiles[parentIndex].activeSubProfileID = duplicatedSubProfile.id
        profiles[parentIndex] = reconciledSubProfileSwitchButtons(in: profiles[parentIndex])
        activeProfileID = parentProfileID
        save()
        return duplicatedSubProfile
    }

    func deleteSubProfile(_ subProfileID: UUID, in parentProfileID: UUID) {
        guard let parentIndex = profiles.firstIndex(where: { $0.id == parentProfileID }),
              profiles[parentIndex].subProfiles.count > 1 else {
            return
        }

        profiles[parentIndex].subProfiles.removeAll { $0.id == subProfileID }
        if profiles[parentIndex].activeSubProfileID == subProfileID {
            profiles[parentIndex].activeSubProfileID = profiles[parentIndex].subProfiles[0].id
        }
        profiles[parentIndex] = reconciledSubProfileSwitchButtons(in: profiles[parentIndex])
        activeProfileID = parentProfileID
        save()
    }

    private func reconciledSubProfileSwitchButtons(
        in profile: Profile,
        previousNames: [UUID: String] = [:]
    ) -> Profile {
        var reconciledProfile = profile.normalizedActiveSubProfileSelection()
        guard !reconciledProfile.subProfiles.isEmpty else {
            return reconciledProfile
        }

        let subProfiles = reconciledProfile.subProfiles
        let validTargetIDs = Set(subProfiles.map(\.id))

        reconciledProfile.subProfiles = subProfiles.map { subProfile in
            var reconciledSubProfile = subProfile
            var buttons = reconciledSubProfile.buttons

            for key in buttons.keys {
                let button = GamepadButton(key)
                guard button.isSubProfileSwitch else {
                    continue
                }

                guard let targetID = button.subProfileSwitchTargetID,
                      validTargetIDs.contains(targetID) else {
                    buttons.removeValue(forKey: key)
                    continue
                }
            }

            for (index, targetSubProfile) in subProfiles.enumerated() {
                let button = GamepadButton.subProfileSwitch(targetID: targetSubProfile.id)
                var config = buttons[button.rawValue] ?? defaultSubProfileSwitchButtonConfig(
                    targetSubProfile: targetSubProfile,
                    index: index,
                    count: subProfiles.count,
                    in: reconciledSubProfile
                )

                if shouldRefreshSwitchLabel(config.label, targetID: targetSubProfile.id, previousNames: previousNames) {
                    config.label = targetSubProfile.name
                }

                config.enabled = true
                config.action = .subProfileSwitch(targetSubProfile.id)
                config.interactionMode = .momentary
                config.multiKeyActivationMode = .sequential
                buttons[button.rawValue] = config
            }

            reconciledSubProfile.buttons = buttons
            return reconciledSubProfile
        }

        return reconciledProfile
    }

    private func defaultSubProfileSwitchButtonConfig(
        targetSubProfile: Profile,
        index: Int,
        count: Int,
        in profile: Profile
    ) -> ButtonConfig {
        let buttonWidth = 78.0
        let buttonHeight = 30.0
        let gap = 8.0
        let rowWidth = (Double(count) * buttonWidth) + (Double(max(0, count - 1)) * gap)
        let startX = (profile.padWidth - rowWidth) / 2 + (buttonWidth / 2)
        let x = min(max(startX + Double(index) * (buttonWidth + gap), buttonWidth / 2), max(buttonWidth / 2, profile.padWidth - buttonWidth / 2))
        let y = max(buttonHeight / 2, profile.padHeight - 24)

        return ButtonConfig(
            x: x / max(profile.padWidth, 1),
            y: y / max(profile.padHeight, 1),
            width: buttonWidth / max(profile.padWidth, 1),
            height: buttonHeight / max(profile.padHeight, 1),
            editorWidth: buttonWidth,
            editorHeight: buttonHeight,
            colorHex: "#3B3B3B",
            keyCode: 49,
            keyModifiers: 0,
            label: targetSubProfile.name,
            labelFontSize: 11,
            labelBold: true,
            labelItalic: false,
            shape: .roundedRectangle,
            enabled: true,
            interactionMode: .momentary,
            action: .subProfileSwitch(targetSubProfile.id)
        )
    }

    private func shouldRefreshSwitchLabel(
        _ label: String,
        targetID: UUID,
        previousNames: [UUID: String]
    ) -> Bool {
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLabel.isEmpty else {
            return true
        }

        guard let previousName = previousNames[targetID] else {
            return false
        }

        return trimmedLabel == previousName
    }

    private func subProfileNames(in profile: Profile) -> [UUID: String] {
        Dictionary(uniqueKeysWithValues: profile.subProfiles.map { ($0.id, $0.name) })
    }

    private func activeSubProfileIndex(in profile: Profile) -> Int? {
        guard !profile.subProfiles.isEmpty else {
            return nil
        }

        if let activeSubProfileID = profile.activeSubProfileID,
           let index = profile.subProfiles.firstIndex(where: { $0.id == activeSubProfileID }) {
            return index
        }

        return 0
    }

    private struct SavedData: Codable {
        var profiles: [Profile]
        var activeProfileID: UUID?
    }
}
