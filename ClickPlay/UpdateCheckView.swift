import SwiftUI

enum UpdateCheckViewState {
    case checking
    case updateAvailable(UpdateCheckResult)
    case upToDate(UpdateCheckResult)
    case failed(String)
}

@MainActor
final class UpdateCheckViewModel: ObservableObject {
    @Published private(set) var state: UpdateCheckViewState

    private let checker: UpdateChecker
    private let onResult: (UpdateCheckResult) -> Void
    private let onSkip: (UpdateCheckResult) -> Void
    private var hasStarted = false

    init(
        checker: UpdateChecker = .shared,
        initialState: UpdateCheckViewState = .checking,
        onResult: @escaping (UpdateCheckResult) -> Void = { _ in },
        onSkip: @escaping (UpdateCheckResult) -> Void = { _ in }
    ) {
        self.checker = checker
        self.state = initialState
        self.onResult = onResult
        self.onSkip = onSkip
    }

    func startIfNeeded() {
        guard !hasStarted else {
            return
        }

        if case .checking = state {
            start()
        }
    }

    func start() {
        hasStarted = true
        state = .checking

        Task {
            do {
                let result = try await checker.checkForUpdates()
                onResult(result)
                state = result.isUpdateAvailable ? .updateAvailable(result) : .upToDate(result)
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    func skip(_ result: UpdateCheckResult) {
        checker.skipVersion(result.latestVersion)
        onSkip(result)
    }
}

struct UpdateCheckView: View {
    @ObservedObject var viewModel: UpdateCheckViewModel
    let onDismiss: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 18)
                .padding(.top, 32)
                .padding(.bottom, 24)
        }
        .frame(width: 460)
        .frame(minHeight: 280)
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Color(nsColor: .windowBackgroundColor).opacity(0.62)
            }
            .ignoresSafeArea()
        }
        .task {
            viewModel.startIfNeeded()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .checking:
            VStack(spacing: 18) {
                ProgressView()
                    .controlSize(.large)

                title("Checking for Updates")

                Text("Looking for the latest Click Play release.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        case let .updateAvailable(result):
            resultView(
                systemImage: "arrow.up.circle.fill",
                tint: .accentColor,
                title: "Update Available",
                message: "Click Play \(result.latestVersion) is available. You have \(result.currentVersion)."
            ) {
                Button("Check Again") {
                    viewModel.start()
                }

                Button("Later") {
                    onDismiss()
                }

                Button("Skip This Version") {
                    viewModel.skip(result)
                    onDismiss()
                }

                Button("Open Release Page") {
                    openURL(result.releaseURL)
                    onDismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        case let .upToDate(result):
            resultView(
                systemImage: "checkmark.circle.fill",
                tint: .green,
                title: "You're Up to Date",
                message: "Click Play \(result.currentVersion) is the latest available version."
            ) {
                Button("Check Again") {
                    viewModel.start()
                }

                Button("Done") {
                    onDismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        case let .failed(message):
            resultView(
                systemImage: "exclamationmark.triangle.fill",
                tint: .orange,
                title: "Could Not Check for Updates",
                message: message
            ) {
                Button("Try Again") {
                    viewModel.start()
                }

                Button("Done") {
                    onDismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func resultView<Buttons: View>(
        systemImage: String,
        tint: Color,
        title: String,
        message: String,
        @ViewBuilder buttons: () -> Buttons
    ) -> some View {
        VStack(spacing: 18) {
            Image(systemName: systemImage)
                .font(.system(size: 48, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)

            VStack(spacing: 8) {
                self.title(title)

                Text(message)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            HStack(spacing: 10) {
                Spacer()
                buttons()
            }
        }
    }

    private func title(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 24, weight: .semibold, design: .rounded))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }
}
