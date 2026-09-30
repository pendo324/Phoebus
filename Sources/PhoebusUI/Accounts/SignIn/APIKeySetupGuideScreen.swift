import SwiftUI

/// Reborn's "Giphy & Image Chest API Key Setup" disclosure, reachable from the
/// "Sign-In" section of Accounts & API Keys. Content follows Reborn's markdown.
public struct APIKeySetupGuideScreen: View {
    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Giphy API Key")
                    .font(.headline)
                step(1, "Go to developers.giphy.com and create an account if you do not have one.")
                Link("developers.giphy.com", destination: URL(string: "https://developers.giphy.com/")!)
                    .font(.subheadline)
                step(2, "After signing in, click Create an API Key at the top of the page.")
                step(3, "Choose SDK (not API).")
                VStack(alignment: .leading, spacing: 4) {
                    stepText(4, "Fill in the form:")
                    bullet("App name: Apollo Reborn (any name is fine)")
                    bullet("Platform: iOS")
                    bullet("App description: Phoebus API Key (or anything brief)")
                }
                step(5, "Check the box to agree to the terms, then click Create API Key.")
                step(6, "On your dashboard, click your new API key to copy it.")
                step(7, "Paste it into Giphy API Key under Apollo Reborn → Accounts & API Keys.")

                Divider()

                Text("Image Chest API Key")
                    .font(.headline)
                step(1, "Go to imgchest.com and click Register to create an account.")
                Link("imgchest.com", destination: URL(string: "https://imgchest.com/")!)
                    .font(.subheadline)
                step(2, "After signing in, open the menu from your profile picture and choose API.")
                step(3, "Click Create API Token, give it a name, then click Create.")
                step(4, "Copy the token and paste it into Image Chest API Key under Apollo Reborn → Accounts & API Keys.")
            }
            .padding()
        }
        .navigationTitle("Giphy & Image Chest API Key Setup")
    }

    private func step(_ number: Int, _ text: String) -> some View {
        stepText(number, text)
    }

    private func stepText(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number).")
                .font(.subheadline.bold())
            Text(text)
                .font(.subheadline)
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•").font(.subheadline)
            Text(text).font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(.leading, 20)
    }
}
