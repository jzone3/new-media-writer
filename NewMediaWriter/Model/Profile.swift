import SwiftUI

enum ProfileKeys {
    static let name = "profile.name"
    static let handle = "profile.handle"
    static let headline = "profile.headline"
    static let avatarPath = "profile.avatarPath"
    static let slackChannel = "profile.slackChannel"
    static let xPremium = "x.premium"
}

struct Profile {
    var name: String
    var handle: String
    var headline: String
    var avatarPath: String
    var slackChannel: String

    var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map { String($0).uppercased() }
        return letters.isEmpty ? "?" : letters.joined()
    }

    var avatarImage: NSImage? {
        guard !avatarPath.isEmpty else { return nil }
        return ImageCache.shared.image(for: URL(fileURLWithPath: avatarPath))
    }
}

/// Reads the profile from AppStorage so every preview updates live when Settings change.
struct ProfileReader<Content: View>: View {
    @AppStorage(ProfileKeys.name) private var name = "Test Account"
    @AppStorage(ProfileKeys.handle) private var handle = "testaccount"
    @AppStorage(ProfileKeys.headline) private var headline = "Builder · Writer"
    @AppStorage(ProfileKeys.avatarPath) private var avatarPath = ""
    @AppStorage(ProfileKeys.slackChannel) private var slackChannel = "general"

    let content: (Profile) -> Content

    var body: some View {
        content(Profile(name: name, handle: handle, headline: headline, avatarPath: avatarPath, slackChannel: slackChannel))
    }
}
