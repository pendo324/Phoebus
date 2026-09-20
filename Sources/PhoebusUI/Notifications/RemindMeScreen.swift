import SwiftUI
import PhoebusCore

/// Remind Me: "Or Choose Hours…" / "Or Choose a Date…" quick-pick reminder UI.
public struct RemindMeScreen: View {
    let post: RedditPost
    let onDone: () -> Void

    @State private var selectedHours: Int?
    @State private var customDate = Date().addingTimeInterval(3600)
    @State private var useCustomDate = false
    @State private var errorMessage: String?
    @State private var scheduled = false

    public init(post: RedditPost, onDone: @escaping () -> Void) {
        self.post = post
        self.onDone = onDone
    }

    public var body: some View {
        List {
            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            if scheduled {
                Section {
                    Label("Reminder scheduled!", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }

            Section {
                let quickPicks = RemindMeScheduler.quickPickHours
                ForEach(quickPicks, id: \.self) { hours in
                    Button {
                        selectedHours = hours
                        useCustomDate = false
                    } label: {
                        HStack {
                            Text(hoursLabel(hours))
                            Spacer()
                            if selectedHours == hours && !useCustomDate {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                    // No footer on this section, so every row rules.
                    .apolloPlainSettingsRowInsets()
                }
            } header: {
                Text("Or Choose Hours…")
                    .apolloSectionHeader()
            }

            Section {
                DatePicker("Remind me at", selection: $customDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    .onChange(of: customDate) { _, _ in useCustomDate = true }
            } header: {
                Text("Or Choose a Date…")
                    .apolloSectionHeader()
            }

            Section {
                Button {
                    Task { await schedule() }
                } label: {
                    Text("Set Reminder")
                }
                .disabled(selectedHours == nil && !useCustomDate)
                .apolloPlainSettingsRowInsets(rule: false)
            }
        }
        .apolloFlatListAppearance()
        .navigationTitle("Remind Me")
    }

    private func hoursLabel(_ hours: Int) -> String {
        if hours < 24 { return "\(hours) hour\(hours == 1 ? "" : "s")" }
        let days = hours / 24
        return "\(days) day\(days == 1 ? "" : "s")"
    }

    private func schedule() async {
        errorMessage = nil
        let authorized = await RemindMeScheduler.requestAuthorizationIfNeeded()
        guard authorized else {
            errorMessage = "Notification permission denied. Enable it in Settings to use reminders."
            return
        }
        let fireDate: Date
        if useCustomDate {
            fireDate = customDate
        } else if let hours = selectedHours {
            fireDate = Date().addingTimeInterval(TimeInterval(hours * 3600))
        } else {
            return
        }
        do {
            try await RemindMeScheduler.scheduleReminder(postTitle: post.title, postPermalink: post.permalink, fireDate: fireDate)
            scheduled = true
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }
}
