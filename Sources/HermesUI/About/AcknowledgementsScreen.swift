#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// Settings › About › Acknowledgements (row 132): simplyHermes's MIT license, then every third-party package in
    /// the app with its license text and, for Apache-2.0 packages that have one, its NOTICE file.
    struct AcknowledgementsScreen: View {
        @State private var list: Acknowledgements?
        @State private var failed = false
        @Environment(\.hermesPalette) private var palette

        var body: some View {
            List {
                if let list {
                    Section {
                        NavigationLink {
                            LicenseTextScreen(entry: list.app)
                        } label: {
                            row(list.app)
                        }
                        .accessibilityIdentifier("acknowledgements.app")
                    } footer: {
                        Text("simplyHermes is open source under the MIT license.")
                    }
                    .hermesListRows()
                    Section {
                        ForEach(list.sortedPackages) { entry in
                            NavigationLink {
                                LicenseTextScreen(entry: entry)
                            } label: {
                                row(entry)
                            }
                            .accessibilityIdentifier("acknowledgements.\(entry.name)")
                        }
                    } header: {
                        Text("Open-source software")
                    } footer: {
                        Text("simplyHermes is built with these packages. Each keeps its own license.")
                    }
                    .hermesListRows()
                } else if failed {
                    Text("The acknowledgements could not be read.")
                        .foregroundStyle(palette.secondaryText)
                }
            }
            .hermesThemedList()
            .navigationTitle("Acknowledgements")
            .task {
                do {
                    list = try Acknowledgements.bundled()
                } catch {
                    failed = true
                }
            }
        }

        private func row(_ entry: Acknowledgements.Entry) -> some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .foregroundStyle(palette.primaryText)
                Text([entry.license, entry.version].compactMap { $0 }.joined(separator: " · "))
                    .font(HermesFont.footnote)
                    .foregroundStyle(palette.secondaryText)
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// One package's license text, then its NOTICE file. Plain, selectable text.
    private struct LicenseTextScreen: View {
        let entry: Acknowledgements.Entry
        @Environment(\.hermesPalette) private var palette

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let url = entry.url {
                        Text(url)
                            .font(HermesFont.footnote)
                            .foregroundStyle(palette.secondaryText)
                    }
                    Text(verbatim: entry.licenseText)
                        .font(HermesFont.code)
                        .accessibilityIdentifier("acknowledgements.licenseText")
                    if let notice = entry.notice {
                        Text("NOTICE")
                            .font(HermesFont.footnote.weight(.semibold))
                        Text(verbatim: notice)
                            .font(HermesFont.code)
                            .accessibilityIdentifier("acknowledgements.notice")
                    }
                }
                .foregroundStyle(palette.primaryText)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .navigationTitle(entry.name)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
#endif
