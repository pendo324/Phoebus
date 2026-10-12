import SwiftUI
import PhoebusCore

/// The half-height update sheet: the icon, "Update available", the notes,
/// and Update / Later / Skip this version. Update opens the installer chosen
/// in Settings, or a chooser of sideloaders. Reborn "In-App Update Prompt" (#1343).
struct AppUpdateSheet: View {
    let prompt: AppUpdateCoordinator.Prompt
    let coordinator: AppUpdateCoordinator
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var choosing = false
    @State private var failedInstaller: UpdateInstaller?

    private var update: AppUpdate { prompt.update }

    var body: some View {
        Group {
            if choosing { chooser } else { summary }
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .presentationDetentsIfAvailable()
        .accessibilityIdentifier("update.sheet")
    }

    // MARK: Summary

    private var summary: some View {
        VStack(spacing: 16) {
            icon
            VStack(spacing: 4) {
                Text("Update available")
                    .font(.title2.weight(.bold))
                (Text(AppUpdateCoordinator.installedVersionText) + Text(" → ")
                    + Text(update.versionText).fontWeight(.semibold).foregroundColor(.apolloAccent))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if !update.notes.isEmpty || update.notesURL != nil {
                notes
            }
            Spacer(minLength: 0)
            VStack(spacing: 8) {
                Button {
                    startUpdate()
                } label: {
                    Text("Update").font(.headline).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("update.update")
                Button("Later") { dismiss() }
                    .accessibilityIdentifier("update.later")
                if prompt.offerSkip {
                    Button("Skip this version") {
                        coordinator.skip(update)
                        dismiss()
                    }
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("update.skip")
                }
            }
        }
    }

    /// The installer chosen in Settings opens straight away; when it can't
    /// (not installed, or no link for this update) the chooser says why.
    private func startUpdate() {
        guard case .open(let installer, let url) = UpdateHandoff.plan(installer: AppUpdatePolicy.installer.load(), for: update) else {
            choosing = true
            return
        }
        openURL(url) { accepted in
            if !accepted {
                failedInstaller = installer
                choosing = true
            }
        }
    }

    @ViewBuilder
    private var icon: some View {
        if let artwork = AppIconArtwork.current() {
            artwork.resizable().scaledToFit()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else {
            Image(systemName: "arrow.down.app.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.apolloAccent)
        }
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Release Notes")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if !update.notes.isEmpty {
                        Text(update.notes).font(.callout)
                    }
                    if let url = update.notesURL {
                        Link("Open Release Notes", destination: url).font(.callout)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: Chooser

    private var chooser: some View {
        VStack(spacing: 12) {
            HStack {
                Button {
                    choosing = false
                    failedInstaller = nil
                } label: {
                    Image(systemName: "chevron.left").font(.body.weight(.semibold))
                }
                .accessibilityLabel("Back")
                .accessibilityIdentifier("update.chooser.back")
                Spacer()
            }
            .overlay { Text("Update Phoebus").font(.headline) }
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(UpdateInstaller.choices(for: update)) { installer in
                        if let url = installer.handoffURL(for: update) {
                            if installer.sideloader != nil {
                                row("Continue in \(installer.title)", systemImage: "arrow.up.forward.app", id: installer.title.lowercased()) {
                                    openURL(url) { accepted in
                                        if !accepted { failedInstaller = installer }
                                    }
                                }
                            } else {
                                row(installer.title, systemImage: "arrow.down.circle", id: "ipa") { openURL(url) }
                            }
                        }
                    }
                }
            }
            if let failedInstaller, failedInstaller.sideloader != nil {
                Text("Couldn't open \(failedInstaller.title). Is it installed?")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            Button("Cancel") { dismiss() }
                .accessibilityIdentifier("update.chooser.cancel")
        }
    }

    private func row(_ title: String, systemImage: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(Color.apolloAccent)
                    .frame(width: 32)
                Text(title).foregroundStyle(.primary)
                Spacer()
            }
            .padding(14)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("update.chooser.\(id)")
    }
}
