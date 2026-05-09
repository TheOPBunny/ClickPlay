import AppKit
import AVKit
import SwiftUI

enum FirstRunOnboardingStep {
    case welcome
    case customization
    case accessibility
}

struct FirstRunOnboardingView: View {
    let onFinishedIntro: () -> Void
    let onGrantPermission: () -> Void
    let onLearnMore: () -> Void

    @State private var step: FirstRunOnboardingStep

    init(
        initialStep: FirstRunOnboardingStep,
        onFinishedIntro: @escaping () -> Void,
        onGrantPermission: @escaping () -> Void,
        onLearnMore: @escaping () -> Void
    ) {
        self.onFinishedIntro = onFinishedIntro
        self.onGrantPermission = onGrantPermission
        self.onLearnMore = onLearnMore
        _step = State(initialValue: initialStep)
    }

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 48)
                .padding(.top, 36)
                .padding(.bottom, 24)

            HStack {
                Spacer()
                footerButtons
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            .background {
                ZStack {
                    Rectangle().fill(.ultraThinMaterial)
                    Color(nsColor: .controlBackgroundColor).opacity(0.14)
                }
            }
        }
        .frame(width: 560, height: 620)
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Color(nsColor: .windowBackgroundColor).opacity(0.36)
            }
            .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome:
            introScreen(
                title: "Click Play",
                message: "Click Play allows you to play many games with just your mouse.",
                videoName: "FirstRunIntro1",
                icon: .appIcon
            )
        case .customization:
            introScreen(
                title: "Endless Customization",
                message: "Customize everything. Exactly to your preference.",
                videoName: "FirstRunIntro2",
                icon: nil,
                videoTopPadding: 56
            )
        case .accessibility:
            accessibilityScreen
        }
    }

    private func introScreen(
        title: String,
        message: String,
        videoName: String,
        icon: HeaderIcon?,
        videoTopPadding: CGFloat = 0
    ) -> some View {
        VStack(spacing: 20) {
            header(title: title, icon: icon)

            Text(message)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            LoopingVideoView(resourceName: videoName)
                .frame(maxWidth: .infinity)
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .padding(.top, videoTopPadding)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Spacer(minLength: 0)
        }
    }

    private var accessibilityScreen: some View {
        VStack(spacing: 18) {
            header(title: "Accessibility Permission", icon: .system("accessibility"))

            Text("Click Play requires accessibility permissions to make inputs.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }

    private func header(title: String, icon: HeaderIcon?) -> some View {
        VStack(spacing: 12) {
            if let icon {
                iconView(icon)
            }

            Text(title)
                .font(.system(size: 36, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func iconView(_ icon: HeaderIcon) -> some View {
        switch icon {
        case .appIcon:
            Image(nsImage: Self.clickPlayIcon())
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 86, height: 86)
        case let .system(name):
            Image(systemName: name)
                .font(.system(size: 54, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accentColor)
                .frame(width: 86, height: 86)
        }
    }

    @ViewBuilder
    private var footerButtons: some View {
        switch step {
        case .welcome:
            Button("Next") {
                step = .customization
            }
            .keyboardShortcut(.defaultAction)
        case .customization:
            Button("Next") {
                onFinishedIntro()
                step = .accessibility
            }
            .keyboardShortcut(.defaultAction)
        case .accessibility:
            Button("Learn More") {
                onLearnMore()
            }

            Button("Grant Permission") {
                onGrantPermission()
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    private static func clickPlayIcon() -> NSImage {
        if let url = Bundle.main.url(
            forResource: "Click-Play-Icon",
            withExtension: "svg",
            subdirectory: "ClickPlay.icon/Assets"
        ),
           let image = NSImage(contentsOf: url) {
            return image
        }

        return NSApp.applicationIconImage
    }
}

private enum HeaderIcon {
    case appIcon
    case system(String)
}

private struct LoopingVideoView: NSViewRepresentable {
    let resourceName: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        configure(view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ view: PlayerContainerView, context: Context) {
        configure(view, coordinator: context.coordinator)
    }

    static func dismantleNSView(_ nsView: PlayerContainerView, coordinator: Coordinator) {
        coordinator.stop()
    }

    private func configure(_ view: PlayerContainerView, coordinator: Coordinator) {
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "mp4") else {
            view.showMissingVideo()
            return
        }

        coordinator.configure(url: url)
        view.player = coordinator.player
        coordinator.play()
    }

    final class Coordinator {
        let player = AVQueuePlayer()
        private var looper: AVPlayerLooper?
        private var currentURL: URL?

        func configure(url: URL) {
            guard currentURL != url else { return }

            currentURL = url
            player.removeAllItems()
            player.isMuted = true
            player.actionAtItemEnd = .none

            let item = AVPlayerItem(url: url)
            looper = AVPlayerLooper(player: player, templateItem: item)
        }

        func play() {
            player.play()
        }

        func stop() {
            player.pause()
            player.removeAllItems()
            looper = nil
            currentURL = nil
        }
    }
}

private final class PlayerContainerView: NSView {
    private let playerLayer = AVPlayerLayer()
    private let missingLabel = NSTextField(labelWithString: "Video unavailable")

    var player: AVPlayer? {
        didSet {
            missingLabel.isHidden = player != nil
            playerLayer.player = player
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        playerLayer.videoGravity = .resizeAspect
        layer?.addSublayer(playerLayer)

        missingLabel.textColor = .secondaryLabelColor
        missingLabel.alignment = .center
        missingLabel.translatesAutoresizingMaskIntoConstraints = false
        missingLabel.isHidden = true
        addSubview(missingLabel)

        NSLayoutConstraint.activate([
            missingLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            missingLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }

    func showMissingVideo() {
        player = nil
        missingLabel.isHidden = false
    }
}
