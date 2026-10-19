#if canImport(UIKit)
    import Foundation
    import HermesKit
    import PhotosUI
    import SwiftUI
    import UniformTypeIdentifiers

    /// The message composer in bubble style: an attach menu, then a rounded field with the attached files above the
    /// text and an inline send button (plan Q21). Without `attachments` the composer has no attach menu.
    public struct Composer: View {
        @Binding private var text: String
        private let placeholder: String
        private let attachments: Binding<[ComposerAttachment]>?
        private let completer: CompletionLookup?
        private let onSend: () -> Void
        private let onSteer: (() -> Void)?
        private let voice: VoiceInputModel?

        @State private var sendCount = 0
        @State private var selection = NSRange(location: 0, length: 0)
        @State private var completions = ComposerCompletions()
        @State private var isPhotosPresented = false
        @State private var photoItems: [PhotosPickerItem] = []
        @State private var isFilesPresented = false
        @State private var isCameraPresented = false
        @State private var problem: String?

        /// - Parameters:
        ///   - attachments: The files waiting in the composer. Nil hides the attach menu.
        ///   - completer: Looks up the completions of a `/` command or an `@` mention. Nil turns completions off.
        public init(
            text: Binding<String>,
            placeholder: String = "Message Hermes",
            attachments: Binding<[ComposerAttachment]>? = nil,
            completer: CompletionLookup? = nil,
            onSend: @escaping () -> Void,
            onSteer: (() -> Void)? = nil,
            voice: VoiceInputModel? = nil
        ) {
            _text = text
            self.placeholder = placeholder
            self.attachments = attachments
            self.completer = completer
            self.onSend = onSend
            self.onSteer = onSteer
            self.voice = voice
        }

        public var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                if !completions.items.isEmpty {
                    CompletionPopover(items: completions.items, onPick: pick)
                }
                HStack(alignment: .bottom, spacing: 8) {
                    if let attachments {
                        attachMenu(attachments)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        if let attachments, !attachments.wrappedValue.isEmpty {
                            AttachmentStrip(attachments: attachments)
                                .padding(.top, 8)
                                .padding(.horizontal, 8)
                        }
                        HStack(alignment: .bottom, spacing: 4) {
                            // Voice turns the field into a waveform bar while the microphone is open (plan Q41).
                            if let voice, voice.isActive {
                                VoiceWaveBar(voice: voice)
                                    .padding(.vertical, 6)
                                    .padding(.leading, 14)
                            } else {
                                field
                                if let voice {
                                    VoiceMicButton(voice: voice)
                                }
                            }
                            sendButton
                        }
                        if let voice, !voice.isActive, let problem = voice.problem {
                            VoiceProblemLine(problem: problem)
                        }
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(HermesColor.separator)
                    )
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .hermesFeedback(.send, trigger: sendCount)
            .alert(
                "Could not attach the file",
                isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(problem ?? "")
            }
            .onChange(of: text) { _, _ in refreshCompletions() }
            .onChange(of: selection) { _, _ in refreshCompletions() }
        }

        /// The text view, with the placeholder shown while it is empty.
        private var field: some View {
            ZStack(alignment: .topLeading) {
                ComposerTextView(text: $text, selection: $selection)
                if text.isEmpty {
                    Text(placeholder)
                        .font(HermesFont.body)
                        .foregroundStyle(HermesColor.secondaryText)
                        .padding(.vertical, 11)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .padding(.leading, 14)
        }

        private func refreshCompletions() {
            guard let completer else { return }
            completions.update(text: text, caret: selection.location, using: completer)
        }

        /// Puts a picked completion into the text and moves the caret after it.
        private func pick(_ item: CompletionItem) {
            guard let result = completions.accept(item, in: text) else { return }
            text = result.text
            selection = NSRange(location: result.caret, length: 0)
        }

        /// Photos, Files, Camera and Paste. Each adds to the attachments; nothing uploads until the message is sent.
        private func attachMenu(_ files: Binding<[ComposerAttachment]>) -> some View {
            Menu {
                Button("Photos", systemImage: "photo.on.rectangle") { isPhotosPresented = true }
                Button("Files", systemImage: "doc") { isFilesPresented = true }
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button("Camera", systemImage: "camera") { isCameraPresented = true }
                }
                Button("Paste Image", systemImage: "doc.on.clipboard") { pasteImage(into: files) }
                    .disabled(!UIPasteboard.general.hasImages)
            } label: {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(HermesColor.primaryText)
                    .frame(width: HermesMetrics.minTapTarget, height: HermesMetrics.minTapTarget)
                    .background(HermesColor.fill, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Attach"))
            .accessibilityIdentifier("composer.attach")
            .photosPicker(
                isPresented: $isPhotosPresented, selection: $photoItems, maxSelectionCount: 5, matching: .images
            )
            .onChange(of: photoItems) { _, items in
                guard !items.isEmpty else { return }
                photoItems = []
                Task { await addPhotos(items, to: files) }
            }
            .fileImporter(
                isPresented: $isFilesPresented, allowedContentTypes: [.item], allowsMultipleSelection: true
            ) { result in
                addFiles(result, to: files)
            }
            .sheet(isPresented: $isCameraPresented) {
                CameraPicker { image in
                    guard let jpeg = AttachmentImage.jpeg(from: image) else {
                        problem = "The photo could not be read."
                        return
                    }
                    files.wrappedValue.append(
                        ComposerAttachment(kind: .image, name: "Photo \(files.wrappedValue.count + 1).jpg", data: jpeg))
                }
                .ignoresSafeArea()
            }
        }

        private func addPhotos(_ items: [PhotosPickerItem], to files: Binding<[ComposerAttachment]>) async {
            for item in items {
                guard let data = try? await item.loadTransferable(type: Data.self),
                    let image = UIImage(data: data),
                    let jpeg = AttachmentImage.jpeg(from: image)
                else {
                    problem = "One of the photos could not be read."
                    continue
                }
                files.wrappedValue.append(
                    ComposerAttachment(kind: .image, name: "Photo \(files.wrappedValue.count + 1).jpg", data: jpeg))
            }
        }

        private func addFiles(_ result: Result<[URL], any Error>, to files: Binding<[ComposerAttachment]>) {
            guard case .success(let urls) = result else { return }
            for url in urls {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                guard let data = try? Data(contentsOf: url) else {
                    problem = "\(url.lastPathComponent) could not be read."
                    continue
                }
                guard data.count <= ComposerAttachment.maxBytes else {
                    problem = "\(url.lastPathComponent) is larger than 20 MB."
                    continue
                }
                let type = UTType(filenameExtension: url.pathExtension)
                let photo =
                    type?.conforms(to: .image) == true ? UIImage(data: data).flatMap(AttachmentImage.jpeg(from:)) : nil
                if let photo {
                    let stem = url.deletingPathExtension().lastPathComponent
                    files.wrappedValue.append(ComposerAttachment(kind: .image, name: "\(stem).jpg", data: photo))
                } else if type?.conforms(to: .pdf) == true {
                    files.wrappedValue.append(ComposerAttachment(kind: .pdf, name: url.lastPathComponent, data: data))
                } else {
                    files.wrappedValue.append(ComposerAttachment(kind: .file, name: url.lastPathComponent, data: data))
                }
            }
        }

        private func pasteImage(into files: Binding<[ComposerAttachment]>) {
            guard let image = UIPasteboard.general.image, let jpeg = AttachmentImage.jpeg(from: image) else {
                problem = "There is no image on the clipboard."
                return
            }
            files.wrappedValue.append(ComposerAttachment(kind: .image, name: "Pasted image.jpg", data: jpeg))
        }

        private var sendButton: some View {
            Button {
                sendCount += 1
                onSend()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.body.weight(.bold))
                    // The idle button uses text-safe colors: white on system gray is below 4.5:1.
                    .foregroundStyle(canSend ? HermesColor.onAccent : HermesColor.secondaryText)
                    .frame(width: 32, height: 32)
                    .background(canSend ? HermesColor.accent : HermesColor.fill, in: Circle())
                    .padding(6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .accessibilityLabel(Text("Send"))
            .popoverTip(onSteer == nil ? nil : SteerTip())
            // Long-press: steer the running reply instead of queueing (plan Q23).
            .contextMenu {
                if let onSteer {
                    Button("Steer the reply now", systemImage: "arrow.turn.up.right") { onSteer() }
                        .disabled(!canSend)
                }
            }
        }

        private var canSend: Bool {
            let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return hasText || !(attachments?.wrappedValue.isEmpty ?? true)
        }
    }
#endif
