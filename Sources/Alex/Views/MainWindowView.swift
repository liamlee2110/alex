import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject private var vault: Vault
    /// `--select <vault path>` preselects a file at launch, for snapshots.
    @State private var selection: String? = Launch.value(after: "--select")

    var body: some View {
        if vault.root == nil {
            WelcomeView()
        } else {
            NavigationSplitView {
                SidebarView(selection: $selection)
                    .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 400)
            } detail: {
                DetailView(path: selection)
            }
            .navigationTitle(vault.name)
        }
    }
}

struct WelcomeView: View {
    @EnvironmentObject private var vault: Vault

    var body: some View {
        VStack(spacing: Space.m) {
            Text("Alex")
                .font(Typography.display)
            Text("A canvas over a folder of plain files. Open one to begin.")
                .font(Typography.body)
                .foregroundStyle(Ink.muted)
            Button("Open a vault…") { VaultPicker.choose(into: vault) }
                .keyboardShortcut(.defaultAction)
                .padding(.top, Space.s)
            if let trouble = vault.trouble {
                Text(trouble)
                    .font(Typography.label)
                    .foregroundStyle(Ink.muted)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SidebarView: View {
    @EnvironmentObject private var vault: Vault
    @Binding var selection: String?

    var body: some View {
        List(selection: $selection) {
            OutlineGroup(vault.tree, children: \.children) { node in
                Label(node.entry.name, systemImage: node.entry.kind.symbol)
                    .tag(node.entry.path)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(vault.root?.path ?? "")
                    .font(Typography.label)
                    .foregroundStyle(Ink.faint)
                    .lineLimit(1)
                    .truncationMode(.head)
                Text("\(vault.fileCount) files")
                    .font(Typography.label)
                    .foregroundStyle(Ink.faint)
                if let trouble = vault.trouble {
                    Text(trouble)
                        .font(Typography.label)
                        .foregroundStyle(Ink.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.m)
            .background(.bar)
        }
    }
}
