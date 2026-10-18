#if canImport(UIKit)
    import SwiftUI

    /// The Tools tab (plan Q38): a list of tools. Terminal is here; Git review, Kanban, Memory, Skills and Logs add rows
    /// as their work packages land.
    struct ToolsHome: View {
        let connections: ConnectionsModel?
        let terminals: TerminalModel
        let addToChat: (String) -> Void

        var body: some View {
            List {
                NavigationLink {
                    TerminalScreen(connections: connections, terminals: terminals, addToChat: addToChat)
                } label: {
                    Label("Terminal", systemImage: "terminal")
                }
            }
            .navigationTitle(AppSection.tools.title)
        }
    }
#endif
