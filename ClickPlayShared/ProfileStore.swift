import Foundation

/// Template category determines whether saved content becomes a full profile, a nested layer, or a grouped selection.
enum ProfileTemplateKind: String, Codable {
    case profile
    case layer
    case group
}

/// Template payload persisted outside the live profile list.
struct ProfileTemplate: Codable, Identifiable {
    var id: UUID
    var name: String
    var kind: ProfileTemplateKind
    var profile: Profile
}

private enum AppStorage {
    static let currentDirectoryName = "Click Play"
    static let legacyDirectoryName = "OnScreenGamepad"

    // Storage lookup also performs the one-time copy from the prototype's old support directory.
    static func fileURL(named fileName: String) -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let currentDir = appSupport.appendingPathComponent(currentDirectoryName)
        let legacyURL = appSupport.appendingPathComponent(legacyDirectoryName).appendingPathComponent(fileName)
        let currentURL = currentDir.appendingPathComponent(fileName)

        do {
            try FileManager.default.createDirectory(at: currentDir, withIntermediateDirectories: true)
        } catch {
            NSLog("[AppStorage] ERROR: Could not create storage directory \(currentDir.path): \(error)")
        }

        if !FileManager.default.fileExists(atPath: currentURL.path),
           FileManager.default.fileExists(atPath: legacyURL.path) {
            do {
                try FileManager.default.copyItem(at: legacyURL, to: currentURL)
            } catch {
                NSLog("[AppStorage] ERROR: Could not copy legacy \(fileName): \(error)")
            }
        }

        return currentURL
    }
}

/// Persists user templates to ~/Library/Application Support/Click Play/templates.json
/// Posts `templatesDidChange` notification when anything changes.
final class ProfileTemplateStore {

    static let shared = ProfileTemplateStore()
    static let templatesDidChange = Notification.Name("templatesDidChange")

    private(set) var templates: [ProfileTemplate] = []

    private let fileURL: URL = {
        AppStorage.fileURL(named: "templates.json")
    }()

    private init() {
        load()
    }

    // MARK: - Template CRUD

    func templates(kind: ProfileTemplateKind) -> [ProfileTemplate] {
        templates.filter { $0.kind == kind }
    }

    @discardableResult
    func saveTemplate(named name: String, kind: ProfileTemplateKind, profile: Profile) -> ProfileTemplate {
        let template = ProfileTemplate(
            id: UUID(),
            name: normalizedName(name, fallback: defaultTemplateName(for: kind)),
            kind: kind,
            profile: storedTemplateProfile(from: profile, kind: kind)
        )
        templates.append(template)
        save()
        return template
    }

    func renameTemplate(id: UUID, to name: String) {
        guard let index = templates.firstIndex(where: { $0.id == id }) else { return }
        templates[index].name = normalizedName(name, fallback: templates[index].name)
        save()
    }

    func deleteTemplate(id: UUID) {
        let previousCount = templates.count
        templates.removeAll { $0.id == id }
        guard templates.count != previousCount else { return }
        save()
    }

    func makeProfile(fromTemplateID id: UUID, name: String) -> Profile? {
        guard let template = templates.first(where: { $0.id == id && $0.kind == .profile }) else { return nil }
        var profile = template.profile.copyWithNewIDs(nameSuffix: "").asTopLevelContainer()
        profile.name = normalizedName(name, fallback: template.name)
        return profile.normalizedActiveSubProfileSelection()
    }

    func makeLayer(fromTemplateID id: UUID, name: String) -> Profile? {
        guard let template = templates.first(where: { $0.id == id && $0.kind == .layer }) else { return nil }
        var layer = template.profile.copyWithNewIDs(nameSuffix: "")
        layer.name = normalizedName(name, fallback: template.name)
        layer.subProfiles = []
        layer.activeSubProfileID = nil
        return layerByRemovingSubProfileSwitches(from: layer).normalizedForSaving()
    }

    func makeGroup(fromTemplateID id: UUID) -> Profile? {
        guard let template = templates.first(where: { $0.id == id && $0.kind == .group }) else { return nil }
        return template.profile.copyWithFreshButtonIDs()
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            templates = []
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let saved = try JSONDecoder().decode(SavedData.self, from: data)
            templates = saved.templates
        } catch {
            NSLog("[ProfileTemplateStore] ERROR: Could not load templates from \(fileURL.path): \(error)")
            templates = []
        }
    }

    private func save() {
        let saved = SavedData(templates: templates)
        do {
            let data = try JSONEncoder().encode(saved)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("[ProfileTemplateStore] ERROR: Could not save templates to \(fileURL.path): \(error)")
        }
        NotificationCenter.default.post(name: ProfileTemplateStore.templatesDidChange, object: nil)
    }

    private func storedTemplateProfile(from profile: Profile, kind: ProfileTemplateKind) -> Profile {
        switch kind {
        case .profile:
            return profile.asTopLevelContainer().normalizedForSaving().normalizedActiveSubProfileSelection()
        case .layer:
            var layer = profile
            layer.subProfiles = []
            layer.activeSubProfileID = nil
            return layerByRemovingSubProfileSwitches(from: layer).normalizedForSaving()
        case .group:
            var groupProfile = layerByRemovingSubProfileSwitches(from: profile)
            groupProfile.subProfiles = []
            groupProfile.activeSubProfileID = nil
            return groupProfile.normalizedForSaving()
        }
    }

    private func layerByRemovingSubProfileSwitches(from profile: Profile) -> Profile {
        var layer = profile
        layer.buttons = profile.buttons.filter { key, config in
            !GamepadButton(key).isSubProfileSwitch && !config.action.isProtectedSwitch
        }
        return layer
    }

    private func normalizedName(_ name: String, fallback: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private func defaultTemplateName(for kind: ProfileTemplateKind) -> String {
        switch kind {
        case .profile:
            return "Profile Template"
        case .layer:
            return "Layer Template"
        case .group:
            return "Group Template"
        }
    }

    private struct SavedData: Codable {
        var templates: [ProfileTemplate]
    }
}

/// Persists profiles to ~/Library/Application Support/Click Play/profiles.json
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
        AppStorage.fileURL(named: "profiles.json")
    }()

    private init() {
        let def = Profile.makeDefault()
        activeProfileID = def.id
        load(defaultProfile: def)
    }

    // MARK: - Persistence

    private func load(defaultProfile: Profile) {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            profiles = [reconciledSubProfileSwitchButtons(in: defaultProfile.asTopLevelContainer())]
            activeProfileID = defaultProfile.id
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let saved = try JSONDecoder().decode(SavedData.self, from: data)
            profiles = (saved.profiles.isEmpty ? [defaultProfile] : saved.profiles).map {
                reconciledSubProfileSwitchButtons(in: $0.asTopLevelContainer())
            }
            activeProfileID = saved.activeProfileID ?? profiles[0].id
            if !profiles.contains(where: { $0.id == activeProfileID }) {
                activeProfileID = profiles[0].id
            }
        } catch {
            NSLog("[ProfileStore] ERROR: Could not load profiles from \(fileURL.path): \(error)")
            profiles = [reconciledSubProfileSwitchButtons(in: defaultProfile.asTopLevelContainer())]
            activeProfileID = defaultProfile.id
        }
    }

    func save() {
        profiles = profiles.map { reconciledSubProfileSwitchButtons(in: $0.normalizedActiveSubProfileSelection()).withSanitizedButtonGroups() }
        let saved = SavedData(profiles: profiles, activeProfileID: activeProfileID)
        do {
            let data = try JSONEncoder().encode(saved)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("[ProfileStore] ERROR: Could not save profiles to \(fileURL.path): \(error)")
        }
        NotificationCenter.default.post(name: ProfileStore.profilesDidChange, object: nil)
    }

    // MARK: - Profile Resolution

    func resolvedProfile(for profile: Profile) -> Profile {
        guard !profile.subProfiles.isEmpty else {
            return profile
        }

        var resolvedProfile: Profile
        if let activeSubProfileID = profile.activeSubProfileID,
           let activeSubProfile = profile.subProfiles.first(where: { $0.id == activeSubProfileID }) {
            resolvedProfile = activeSubProfile
        } else {
            resolvedProfile = profile.subProfiles[0]
        }

        resolvedProfile.displayPadWidth = profile.displayPadWidth
        resolvedProfile.displayPadHeight = profile.displayPadHeight
        return resolvedProfile
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

    // MARK: - Top-Level Profile Mutations

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

    func rename(_ id: UUID, to name: String) {
        guard let idx = profiles.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, profiles[idx].name != trimmed else { return }
        profiles[idx].name = trimmed
        save()
    }

    func delete(_ id: UUID) {
        guard profiles.count > 1 else { return }
        profiles.removeAll { $0.id == id }
        if activeProfileID == id { activeProfileID = profiles[0].id }
        save()
    }

    func restoreProfile(_ profile: Profile, at index: Int, activeProfileID restoredActiveProfileID: UUID) {
        let restoredProfile = profile.asTopLevelContainer()
        profiles.removeAll { $0.id == restoredProfile.id }
        let insertionIndex = min(max(index, 0), profiles.count)
        profiles.insert(restoredProfile, at: insertionIndex)
        activeProfileID = profiles.contains { $0.id == restoredActiveProfileID }
            ? restoredActiveProfileID
            : restoredProfile.id
        save()
    }

    @discardableResult
    func moveProfile(_ id: UUID, to index: Int) -> Bool {
        guard let sourceIndex = profiles.firstIndex(where: { $0.id == id }) else {
            return false
        }

        let movingProfile = profiles.remove(at: sourceIndex)
        let adjustedIndex = index > sourceIndex ? index - 1 : index
        let destinationIndex = min(max(adjustedIndex, 0), profiles.count)
        guard destinationIndex != sourceIndex else {
            profiles.insert(movingProfile, at: sourceIndex)
            return false
        }

        profiles.insert(movingProfile, at: destinationIndex)
        save()
        return true
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
        profiles[idx].displayPadWidth = width
        profiles[idx].displayPadHeight = height
        save()
    }

    // MARK: - Sub-Profile Mutations

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

    func renameSubProfile(_ subProfileID: UUID, in parentProfileID: UUID, to name: String) {
        guard let parentIndex = profiles.firstIndex(where: { $0.id == parentProfileID }),
              let childIndex = profiles[parentIndex].subProfiles.firstIndex(where: { $0.id == subProfileID }) else {
            return
        }

        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, profiles[parentIndex].subProfiles[childIndex].name != trimmed else { return }
        let previousNames = subProfileNames(in: profiles[parentIndex])
        profiles[parentIndex].subProfiles[childIndex].name = trimmed
        profiles[parentIndex] = reconciledSubProfileSwitchButtons(
            in: profiles[parentIndex],
            previousNames: previousNames
        )
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
    func addSubProfile(_ subProfile: Profile, to parentProfileID: UUID) -> Profile? {
        guard let parentIndex = profiles.firstIndex(where: { $0.id == parentProfileID }) else { return nil }
        var savedSubProfile = subProfile
        savedSubProfile.subProfiles = []
        savedSubProfile.activeSubProfileID = nil
        profiles[parentIndex].subProfiles.append(savedSubProfile)
        profiles[parentIndex].activeSubProfileID = savedSubProfile.id
        profiles[parentIndex] = reconciledSubProfileSwitchButtons(in: profiles[parentIndex])
        activeProfileID = parentProfileID
        save()
        return savedSubProfile
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

    @discardableResult
    func moveSubProfile(_ subProfileID: UUID, in parentProfileID: UUID, to index: Int) -> Bool {
        guard let parentIndex = profiles.firstIndex(where: { $0.id == parentProfileID }),
              let sourceIndex = profiles[parentIndex].subProfiles.firstIndex(where: { $0.id == subProfileID }) else {
            return false
        }

        let movingSubProfile = profiles[parentIndex].subProfiles.remove(at: sourceIndex)
        let adjustedIndex = index > sourceIndex ? index - 1 : index
        let destinationIndex = min(max(adjustedIndex, 0), profiles[parentIndex].subProfiles.count)
        guard destinationIndex != sourceIndex else {
            profiles[parentIndex].subProfiles.insert(movingSubProfile, at: sourceIndex)
            return false
        }

        profiles[parentIndex].subProfiles.insert(movingSubProfile, at: destinationIndex)
        profiles[parentIndex] = reconciledSubProfileSwitchButtons(in: profiles[parentIndex])
        activeProfileID = parentProfileID
        save()
        return true
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

    func restoreSubProfile(
        _ subProfile: Profile,
        in parentProfileID: UUID,
        at index: Int,
        activeProfileID restoredActiveProfileID: UUID,
        activeSubProfileID restoredActiveSubProfileID: UUID?
    ) {
        guard let parentIndex = profiles.firstIndex(where: { $0.id == parentProfileID }) else { return }

        var restoredSubProfile = subProfile
        restoredSubProfile.subProfiles = []
        restoredSubProfile.activeSubProfileID = nil
        profiles[parentIndex].subProfiles.removeAll { $0.id == restoredSubProfile.id }
        let insertionIndex = min(max(index, 0), profiles[parentIndex].subProfiles.count)
        profiles[parentIndex].subProfiles.insert(restoredSubProfile, at: insertionIndex)
        profiles[parentIndex].activeSubProfileID = restoredActiveSubProfileID
        profiles[parentIndex] = reconciledSubProfileSwitchButtons(in: profiles[parentIndex])
        activeProfileID = profiles.contains { $0.id == restoredActiveProfileID }
            ? restoredActiveProfileID
            : parentProfileID
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

            guard subProfiles.count > 1 else {
                for key in buttons.keys where GamepadButton(key).isSubProfileSwitch {
                    buttons.removeValue(forKey: key)
                }
                reconciledSubProfile.buttons = buttons
                return reconciledSubProfile
            }

            let hasMissingSwitchButton = subProfiles.contains { targetSubProfile in
                buttons[GamepadButton.subProfileSwitch(targetID: targetSubProfile.id).rawValue] == nil
            }
            let switchRowY: Double
            if hasMissingSwitchButton {
                let prepared = profileByMakingRoomForSwitchRow(reconciledSubProfile)
                reconciledSubProfile = prepared.profile
                buttons = reconciledSubProfile.buttons
                switchRowY = prepared.rowCenterY
            } else {
                switchRowY = max(Self.switchButtonHeight / 2, reconciledSubProfile.padHeight - 24)
            }

            for (index, targetSubProfile) in subProfiles.enumerated() {
                let button = GamepadButton.subProfileSwitch(targetID: targetSubProfile.id)
                var config = buttons[button.rawValue] ?? defaultSubProfileSwitchButtonConfig(
                    targetSubProfile: targetSubProfile,
                    index: index,
                    count: subProfiles.count,
                    in: reconciledSubProfile,
                    rowCenterY: switchRowY
                )

                if shouldRefreshSwitchLabel(config.label, targetID: targetSubProfile.id, previousNames: previousNames) {
                    config.label = targetSubProfile.name
                }

                config.type = .keyboard
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
        in profile: Profile,
        rowCenterY: Double
    ) -> ButtonConfig {
        let rowWidth = (Double(count) * Self.switchButtonWidth) + (Double(max(0, count - 1)) * Self.switchButtonGap)
        let startX = (profile.padWidth - rowWidth) / 2 + (Self.switchButtonWidth / 2)
        let x = min(
            max(startX + Double(index) * (Self.switchButtonWidth + Self.switchButtonGap), Self.switchButtonWidth / 2),
            max(Self.switchButtonWidth / 2, profile.padWidth - Self.switchButtonWidth / 2)
        )
        let y = min(
            max(rowCenterY, Self.switchButtonHeight / 2),
            max(Self.switchButtonHeight / 2, profile.padHeight - Self.switchButtonHeight / 2)
        )

        return ButtonConfig(
            x: x / max(profile.padWidth, 1),
            y: y / max(profile.padHeight, 1),
            width: Self.switchButtonWidth / max(profile.padWidth, 1),
            height: Self.switchButtonHeight / max(profile.padHeight, 1),
            editorWidth: Self.switchButtonWidth,
            editorHeight: Self.switchButtonHeight,
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

    private static let switchButtonWidth = 78.0
    private static let switchButtonHeight = 30.0
    private static let switchButtonGap = 8.0

    private func profileByMakingRoomForSwitchRow(_ profile: Profile) -> (profile: Profile, rowCenterY: Double) {
        var preparedProfile = profile
        let existingContentMaxY = nonSwitchContentMaxY(in: profile)
        let rowCenterY = existingContentMaxY.map {
            $0 + Self.switchButtonGap + (Self.switchButtonHeight / 2)
        } ?? max(Self.switchButtonHeight / 2, profile.padHeight - 24)
        let requiredHeight = rowCenterY + (Self.switchButtonHeight / 2)

        guard requiredHeight > preparedProfile.padHeight else {
            return (preparedProfile, rowCenterY)
        }

        let oldHeight = max(preparedProfile.padHeight, 1)
        let newHeight = requiredHeight
        preparedProfile.padHeight = newHeight

        for key in preparedProfile.buttons.keys {
            guard var config = preparedProfile.buttons[key] else {
                continue
            }

            let absoluteCenterY = config.y * oldHeight
            let absoluteHeight = config.editorHeight > 0 ? config.editorHeight : config.height * oldHeight
            config.y = absoluteCenterY / newHeight
            config.height = absoluteHeight / newHeight
            preparedProfile.buttons[key] = config
        }

        return (preparedProfile, rowCenterY)
    }

    private func nonSwitchContentMaxY(in profile: Profile) -> Double? {
        var maxY: Double?

        for (key, config) in profile.buttons {
            let button = GamepadButton(key)
            guard !button.isSubProfileSwitch, !config.action.isProtectedSwitch, config.enabled else {
                continue
            }

            let height = config.editorHeight > 0 ? config.editorHeight : config.height * profile.padHeight
            let centerY = config.y * profile.padHeight
            let buttonMaxY = centerY + height / 2
            maxY = max(maxY ?? buttonMaxY, buttonMaxY)
        }

        return maxY
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

    private struct SavedData: Codable {
        var profiles: [Profile]
        var activeProfileID: UUID?
    }
}
