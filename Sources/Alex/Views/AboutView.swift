import SwiftUI

/// A rare brand surface: enough warmth to identify Alex, with none of the
/// mascot carried into the working canvas or its navigation.
struct AboutView: View {
    private var version: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    var body: some View {
        VStack(spacing: Space.m) {
            Image("alex-mini", bundle: .module)
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)

            VStack(spacing: Space.xs) {
                Text("Alex")
                    .font(Typography.display)
                    .foregroundStyle(Ink.primary)
                Text("Make space for thought.")
                    .font(Typography.body)
                    .foregroundStyle(Ink.muted)
            }

            Text("A native macOS canvas over plain files.")
                .font(Typography.meta)
                .foregroundStyle(Ink.muted)

            if let version {
                Text("Version \(version)")
                    .font(Typography.micro)
                    .foregroundStyle(Ink.faint)
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, Space.xl * 2)
        .padding(.vertical, Space.xl)
        .frame(width: 360)
        .background(Ink.card)
        .accessibilityElement(children: .contain)
    }
}
