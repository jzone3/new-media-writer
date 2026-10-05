import SwiftUI

struct SettingsView: View {
    @AppStorage(ProfileKeys.name) private var name = "Test Account"
    @AppStorage(ProfileKeys.handle) private var handle = "testaccount"
    @AppStorage(ProfileKeys.headline) private var headline = "Builder · Writer"
    @AppStorage(ProfileKeys.avatarPath) private var avatarPath = ""
    @AppStorage(ProfileKeys.slackChannel) private var slackChannel = "general"

    var body: some View {
        Form {
            Section("Profile shown in previews") {
                HStack(spacing: 16) {
                    AvatarView(profile: Profile(name: name, handle: handle, headline: headline, avatarPath: avatarPath, slackChannel: slackChannel), size: 56)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Button("Choose Avatar…", action: chooseAvatar)
                            if !avatarPath.isEmpty {
                                Button("Remove") { avatarPath = "" }
                            }
                        }
                        Text(avatarPath.isEmpty ? "Uses your initials until you pick a photo." : (avatarPath as NSString).lastPathComponent)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                TextField("Name", text: $name)
                TextField("Handle", text: $handle, prompt: Text("without the @"))
                TextField("LinkedIn headline", text: $headline)
                TextField("Slack channel", text: $slackChannel, prompt: Text("general"))
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .padding(.bottom, 8)
    }

    private func chooseAvatar() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            ImageCache.shared.invalidate(url)
            avatarPath = url.path
        }
    }
}
