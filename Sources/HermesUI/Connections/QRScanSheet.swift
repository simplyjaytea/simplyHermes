#if canImport(UIKit)
    import HermesKit
    import SwiftUI
    import VisionKit

    /// Scans a connection QR code with the camera, or takes the code's text pasted in (simulator, no camera).
    public struct QRScanSheet: View {
        private let onCode: (ConnectionQRCode) -> Void
        @Environment(\.dismiss) private var dismiss
        @State private var pasted = ""
        @State private var problem: String?

        public init(onCode: @escaping (ConnectionQRCode) -> Void) {
            self.onCode = onCode
        }

        public var body: some View {
            NavigationStack {
                VStack(spacing: 16) {
                    if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                        QRScannerView { text in handle(text) }
                            .clipShape(RoundedRectangle(cornerRadius: HermesMetrics.cardRadius, style: .continuous))
                            .frame(maxHeight: 420)
                    } else {
                        ContentUnavailableView(
                            "Camera not available", systemImage: "camera",
                            description: Text("Paste the code's text below instead."))
                    }
                    TextField("Or paste the code's text", text: $pasted)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit { handle(pasted) }
                    if let problem {
                        Text(problem).font(HermesFont.footnote).foregroundStyle(HermesColor.destructive)
                    }
                    Text("Codes hold a gateway URL or an ssh://user@host address, never a password or key.")
                        .font(HermesFont.footnote)
                        .foregroundStyle(HermesColor.secondaryText)
                    Spacer(minLength: 0)
                }
                .padding(20)
                .navigationTitle("Scan QR code")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }

        private func handle(_ text: String) {
            if let code = ConnectionQRCode(scanned: text) {
                onCode(code)
            } else {
                problem = "That code isn't a simplyHermes server code."
            }
        }
    }

    /// VisionKit's live QR scanner.
    struct QRScannerView: UIViewControllerRepresentable {
        let onText: (String) -> Void

        func makeUIViewController(context: Context) -> DataScannerViewController {
            let scanner = DataScannerViewController(
                recognizedDataTypes: [.barcode(symbologies: [.qr])], qualityLevel: .balanced,
                isHighlightingEnabled: true)
            scanner.delegate = context.coordinator
            return scanner
        }

        func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
            if !scanner.isScanning { try? scanner.startScanning() }
        }

        static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
            scanner.stopScanning()
        }

        func makeCoordinator() -> Coordinator { Coordinator(onText: onText) }

        @MainActor
        final class Coordinator: NSObject, DataScannerViewControllerDelegate {
            let onText: (String) -> Void
            private var delivered = false

            init(onText: @escaping (String) -> Void) {
                self.onText = onText
            }

            func dataScanner(
                _ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem],
                allItems: [RecognizedItem]
            ) {
                let texts = addedItems.compactMap { item -> String? in
                    guard case .barcode(let barcode) = item else { return nil }
                    return barcode.payloadStringValue
                }
                guard !delivered, let text = texts.first else { return }
                delivered = true
                onText(text)
            }
        }
    }
#endif
