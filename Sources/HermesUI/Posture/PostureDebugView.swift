#if canImport(UIKit)
    import SwiftUI

    /// Prints everything the shell decides from: posture, hinge status and angle, size classes, size, safe area
    /// and reserved regions. Open it with the launch argument `-HermesScreen postureDebug`.
    public struct PostureDebugView: View {
        private let monitor: DevicePostureMonitor
        @Environment(\.horizontalSizeClass) private var horizontal
        @Environment(\.verticalSizeClass) private var vertical

        public init(monitor: DevicePostureMonitor) {
            self.monitor = monitor
        }

        public var body: some View {
            GeometryReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        group("Posture") {
                            row("posture", monitor.posture.rawValue)
                            row("hinge.status", monitor.hinge.map { "\($0.status)" } ?? "none")
                            row("hinge.angle", monitor.hinge.map { String(format: "%.1f°", $0.angleDegrees) } ?? "none")
                            row("posture.source", monitor.override != nil ? "forced" : "hinge")
                        }
                        group("Screen") {
                            row("size", "\(Int(proxy.size.width)) × \(Int(proxy.size.height)) pt")
                            row("sizeClass.horizontal", name(horizontal))
                            row("sizeClass.vertical", name(vertical))
                            row("orientation", proxy.size.width > proxy.size.height ? "landscape" : "portrait")
                            row("safeArea", insets(proxy.safeAreaInsets))
                        }
                        group("Reserved regions") {
                            row("regions.count", "\(monitor.reservedRegions.count)")
                            ForEach(monitor.reservedRegions) { region in
                                Text("\(region.kind)\(region.isActive ? "" : " (inactive)"): \(rect(region.frame))")
                                    .font(.footnote.monospaced())
                            }
                        }
                    }
                    .padding()
                }
                .navigationTitle("Posture")
            }
        }

        private func group(_ title: String, @ViewBuilder content: () -> some View) -> some View {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.headline)
                content()
            }
        }

        private func row(_ key: String, _ value: String) -> some View {
            HStack {
                Text(key).foregroundStyle(.secondary)
                Spacer()
                Text(value).font(.body.monospaced()).accessibilityIdentifier("posture.\(key)")
            }
            .accessibilityElement(children: .contain)
        }

        private func name(_ sizeClass: UserInterfaceSizeClass?) -> String {
            switch sizeClass {
            case .compact: "compact"
            case .regular: "regular"
            default: "unknown"
            }
        }

        private func insets(_ value: EdgeInsets) -> String {
            "t\(Int(value.top)) l\(Int(value.leading)) b\(Int(value.bottom)) r\(Int(value.trailing))"
        }

        private func rect(_ value: CGRect) -> String {
            "x\(Int(value.minX)) y\(Int(value.minY)) w\(Int(value.width)) h\(Int(value.height))"
        }
    }
#endif
