#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    extension EnvironmentValues {
        /// The model behind Settings > On-device models. The app sets it at the root (plan WP-65c), so the Settings
        /// screen and the offline chat can open ``OnDeviceModelsScreen`` without knowing how downloads work.
        @Entry public var onDeviceModels: OnDeviceModelsModel?
    }

    /// Settings > On-device models (plan WP-65c, Q17, Q45): the switch for on-device features, the Apple model,
    /// and the downloadable models with size, status, download and delete buttons. The size shows before a download
    /// starts, and again in the question the screen asks first.
    ///
    /// The Settings screen owns the switch (plan WP-65b), so it passes it in as a binding.
    public struct OnDeviceModelsView: View {
        private let model: OnDeviceModelsModel
        private let isEnabled: Binding<Bool>

        public init(model: OnDeviceModelsModel, isEnabled: Binding<Bool>) {
            self.model = model
            self.isEnabled = isEnabled
        }

        public var body: some View {
            Form {
                Section {
                    Toggle("On-device features", isOn: isEnabled)
                        .accessibilityIdentifier("onDeviceModels.switch")
                } footer: {
                    Text(
                        """
                        Offline chat, chat titles, summaries and prompt polish run on a model on this device. \
                        Turn this off to stop all of them. Downloaded models stay until you delete them.
                        """)
                }
                Section {
                    AppleModelRow(model: model)
                    ForEach(model.rows) { row in
                        ModelRow(row: row) { action in model.tap(action, on: row) }
                    }
                } header: {
                    Text("Models")
                } footer: {
                    Text(
                        OnDeviceModelsText.footer(
                            suspended: model.isSuspendedByMemoryWarning, canRun: model.canRunDownloadedModels))
                }
                Section {
                    LabeledContent("Used by models", value: OnDeviceModelsText.size(model.usedBytes))
                        .accessibilityIdentifier("onDeviceModels.storageUsed")
                }
                if let errorText = model.errorText {
                    Section {
                        Label(errorText, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(HermesColor.destructive)
                    }
                }
            }
            .navigationTitle("On-device models")
            .navigationBarTitleDisplayMode(.inline)
            .task { await model.run() }
            .confirmationDialog(
                model.question.map { OnDeviceModelsText.title(for: $0) } ?? "", isPresented: questionIsShown,
                titleVisibility: .visible, presenting: model.question
            ) { question in
                Button(
                    OnDeviceModelsText.confirmLabel(for: question),
                    role: question.action == .download ? nil : .destructive
                ) {
                    model.confirm(question)
                }
            } message: { question in
                Text(OnDeviceModelsText.message(for: question))
            }
        }

        private var questionIsShown: Binding<Bool> {
            Binding(
                get: { model.question != nil },
                set: { shown in if !shown { model.question = nil } })
        }
    }

    /// Settings > On-device models, ready to push or present. It reads ``EnvironmentValues/onDeviceModels``, so the
    /// caller only passes the switch for on-device features (plan WP-65b).
    public struct OnDeviceModelsScreen: View {
        @Environment(\.onDeviceModels) private var model
        private let isEnabled: Binding<Bool>

        public init(isEnabled: Binding<Bool>) {
            self.isEnabled = isEnabled
        }

        public var body: some View {
            if let model {
                OnDeviceModelsView(model: model, isEnabled: isEnabled)
            } else {
                ContentUnavailableView(
                    "On-device models are not available", systemImage: "cpu",
                    description: Text("Restart simplyHermes and try again."))
            }
        }
    }

    extension View {
        /// Shows the model list as a sheet when ``OnDeviceModelsModel/presentList()`` is called. Put it on the app's
        /// root view.
        public func onDeviceModelsSheet(_ model: OnDeviceModelsModel, isEnabled: Binding<Bool>) -> some View {
            modifier(OnDeviceModelsSheet(model: model, isEnabled: isEnabled))
        }
    }

    private struct OnDeviceModelsSheet: ViewModifier {
        let model: OnDeviceModelsModel
        let isEnabled: Binding<Bool>

        func body(content: Content) -> some View {
            content.sheet(
                isPresented: Binding(get: { model.isListPresented }, set: { model.isListPresented = $0 })
            ) {
                NavigationStack {
                    OnDeviceModelsView(model: model, isEnabled: isEnabled)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { model.isListPresented = false }
                            }
                        }
                }
            }
        }
    }

    // MARK: Rows

    private struct AppleModelRow: View {
        let model: OnDeviceModelsModel

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Apple on-device model").font(HermesFont.headline)
                    Spacer()
                    if model.appleModelIsInUse { InUseBadge() }
                }
                Text(OnDeviceModelsText.appleDetail(model.appleAvailability))
                    .font(HermesFont.subheadline)
                    .foregroundStyle(HermesColor.secondaryText)
                if !model.appleModelIsInUse {
                    Button("Use this model") { model.useAppleModel() }
                        .buttonStyle(HermesButtonStyle(.primary, fillsWidth: false))
                        .accessibilityLabel("Use the Apple on-device model")
                        .accessibilityIdentifier("onDeviceModels.apple.use")
                }
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("onDeviceModels.row.apple")
        }
    }

    private struct ModelRow: View {
        let row: OnDeviceModelRow
        let perform: (OnDeviceModelRow.Action) -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(row.model.displayName).font(HermesFont.headline)
                    if row.model.isRecommended {
                        Text("Recommended")
                            .font(HermesFont.caption.weight(.semibold))
                            .foregroundStyle(HermesColor.accent)
                    }
                    Spacer()
                    if row.isSelected { InUseBadge() }
                }
                Text(row.model.summary)
                    .font(HermesFont.subheadline)
                    .foregroundStyle(HermesColor.secondaryText)
                Text(OnDeviceModelsText.sizeLine(row))
                    .font(HermesFont.caption)
                    .foregroundStyle(HermesColor.secondaryText)
                Text(OnDeviceModelsText.licenseLine(row.model))
                    .font(HermesFont.caption)
                    .foregroundStyle(HermesColor.secondaryText)
                status
                if row.mayNotFitInMemory {
                    Label(OnDeviceModelsText.memoryCaution(row), systemImage: "memorychip")
                        .font(HermesFont.caption)
                        .foregroundStyle(HermesColor.statusWarning)
                }
                buttons
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("onDeviceModels.row.\(row.id)")
        }

        @ViewBuilder private var status: some View {
            switch row.state {
            case .downloading(let progress), .paused(let progress):
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: progress.fraction)
                        .accessibilityLabel("Download progress")
                        .accessibilityValue(OnDeviceModelsText.percent(progress))
                    if let line = OnDeviceModelsText.statusLine(row) {
                        Text(line).font(HermesFont.caption).foregroundStyle(HermesColor.secondaryText)
                    }
                }
            case .failed:
                if let line = OnDeviceModelsText.statusLine(row) {
                    Label(line, systemImage: "exclamationmark.triangle.fill")
                        .font(HermesFont.caption)
                        .foregroundStyle(HermesColor.statusWarning)
                }
            case .queued:
                if let line = OnDeviceModelsText.statusLine(row) {
                    Text(line).font(HermesFont.caption).foregroundStyle(HermesColor.secondaryText)
                }
            case .notDownloaded, .downloaded:
                EmptyView()
            }
        }

        private var buttons: some View {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { buttonList }
                VStack(alignment: .leading, spacing: 8) { buttonList }
            }
        }

        private var buttonList: some View {
            ForEach(row.actions, id: \.self) { action in
                Button(OnDeviceModelsText.label(for: action, row: row)) { perform(action) }
                    .buttonStyle(HermesButtonStyle(style(of: action), fillsWidth: false))
                    .accessibilityLabel(OnDeviceModelsText.accessibilityLabel(for: action, row: row))
                    .accessibilityIdentifier("onDeviceModels.\(row.id).\(action)")
            }
        }

        private func style(of action: OnDeviceModelRow.Action) -> HermesButtonStyle.Kind {
            switch action {
            case .download, .resume, .retry, .use: .primary
            case .pause, .cancel, .delete: .tinted
            }
        }
    }

    private struct InUseBadge: View {
        var body: some View {
            Label("In use", systemImage: "checkmark.circle.fill")
                .font(HermesFont.caption.weight(.semibold))
                .foregroundStyle(HermesColor.statusConnected)
        }
    }

    // MARK: Previews

    #if DEBUG
        extension OnDeviceModelsModel {
            /// A model with fixed states and no downloads, for previews.
            static func preview(
                states: [String: OnDeviceModelState], used: Int64 = 0, apple: LocalModelAvailability = .available,
                canRun: Bool = true, memory: Int64? = nil
            ) -> OnDeviceModelsModel {
                let storage = OnDeviceModelStorage(
                    root: FileManager.default.temporaryDirectory.appendingPathComponent("preview-on-device-models"))
                let manager = OnDeviceModelManager(storage: storage, downloader: PreviewDownloader())
                let selection = OnDeviceModelSelection(
                    apple: PreviewExecutor(availability: apple), storage: storage,
                    runtime: canRun ? PreviewRuntime() : nil)
                let controller = OnDeviceModelController(
                    manager: manager, selection: selection, availableMemory: { memory })
                let model = OnDeviceModelsModel(controller: controller, storage: storage)
                model.freeze(states: states, usedBytes: used)
                return model
            }
        }

        private struct PreviewExecutor: LocalModelExecutor {
            let availability: LocalModelAvailability

            func respond(instructions: String, prompt: String) async throws -> String { "" }
        }

        private struct PreviewRuntime: OnDeviceModelRuntime {
            func executor(for model: OnDeviceModel, folder: URL) -> (any LocalModelExecutor)? {
                PreviewExecutor(availability: .available)
            }

            func unloadAll() async {}
        }

        private struct PreviewDownloader: ModelFileDownloader {
            func download(
                from url: URL, resumeData: Data?, progress: @escaping @Sendable (Int64) -> Void
            ) async throws -> URL {
                throw ModelFileDownloadError.network("Preview", resumeData: nil)
            }
        }

        @MainActor
        private func previewScreen(_ model: OnDeviceModelsModel, enabled: Bool = true) -> some View {
            NavigationStack {
                OnDeviceModelsView(model: model, isEnabled: .constant(enabled))
            }
        }

        private let previewProgress = OnDeviceModelProgress(receivedBytes: 1_100_000_000, totalBytes: 2_277_297_844)

        private let previewStates: [String: OnDeviceModelState] = [
            "gemma-3-1b-4bit": .downloaded,
            "llama-3.2-3b-4bit": .downloading(previewProgress),
            "qwen3-4b-instruct-4bit": .notDownloaded,
        ]

        #Preview("On-device models, outer", traits: .fixedLayout(width: 466, height: 678)) {
            previewScreen(.preview(states: previewStates, used: 770_000_000))
        }

        #Preview("On-device models, inner portrait", traits: .fixedLayout(width: 626, height: 890)) {
            previewScreen(
                .preview(
                    states: [
                        "gemma-3-1b-4bit": .paused(previewProgress),
                        "llama-3.2-3b-4bit": .failed(.network("Offline"), previewProgress),
                        "qwen3-4b-instruct-4bit": .downloaded,
                    ], used: 2_300_000_000))
        }

        #Preview("On-device models, inner landscape", traits: .fixedLayout(width: 890, height: 626)) {
            previewScreen(
                .preview(
                    states: [
                        "gemma-3-1b-4bit": .queued,
                        "llama-3.2-3b-4bit": .failed(
                            .notEnoughSpace(needed: 2_400_000_000, available: 900_000_000), previewProgress),
                        "qwen3-4b-instruct-4bit": .notDownloaded,
                    ], apple: .unavailable(.disabled), memory: 2_000_000_000))
        }

        #Preview("On-device models, half-fold", traits: .fixedLayout(width: 890, height: 313)) {
            previewScreen(.preview(states: previewStates, used: 770_000_000, canRun: false), enabled: false)
        }

        #Preview("On-device models, dark", traits: .fixedLayout(width: 466, height: 678)) {
            previewScreen(.preview(states: previewStates, used: 770_000_000))
                .preferredColorScheme(.dark)
        }
    #endif
#endif
