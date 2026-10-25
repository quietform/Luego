import SwiftUI

struct DiscoveryPostPlaceholderList: View {
    let showsSelection: Bool

    // Redacted text keeps each row's length, so the placeholders share the real rows' varied rag.
    private static let posts = [
        ("small-web.example", "A short title for a post", "A one line summary of what the post is about"),
        ("journal.example", "Notes from a slow weekend spent walking around town", "Thoughts on things worth keeping"),
        ("blog.example", "Why simple tools last longer", "An excerpt that runs a little longer than the others"),
        ("garden-notes.example", "Planting season begins again", "A brief summary"),
        ("weekly.example", "A longer title that wraps onto a second line in the list", "What the writer has been reading lately"),
        ("letters.example", "On writing every day", "A quiet summary of the essay"),
        ("field-notes.example", "Small things that made this week better", "A few lines about the week"),
        ("photos.example", "Light in late autumn", "A summary that fills most of the line")
    ].map { domain, title, excerpt in
        DiscoveryPost(url: URL(string: "https://\(domain)")!, title: title, publishedDate: nil, excerpt: excerpt)
    }

    var body: some View {
        List(Self.posts) { post in
            DiscoveryPostRow(post: post)
                .redacted(reason: .placeholder)
                .shimmer()
                .listRowSeparator(showsSelection ? .hidden : .automatic)
                .listRowBackground(showsSelection ? Color.clear : nil)
        }
        .scrollContentBackground(.hidden)
        .scrollDisabled(true)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading posts")
    }
}
