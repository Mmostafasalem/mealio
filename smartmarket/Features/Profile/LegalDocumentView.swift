import SwiftUI

struct LegalDocumentView: View {
    let resource: String
    let title: String

    private var paragraphs: [String] {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "md"),
              let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return content.components(separatedBy: "\n\n").filter { !$0.isEmpty }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                if paragraphs.isEmpty {
                    ContentUnavailableView("Document unavailable", systemImage: "doc.text",
                                           description: Text("Please try reopening the app."))
                } else {
                    ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                        if paragraph.hasPrefix("#") {
                            Text(paragraph.drop(while: { $0 == "#" || $0 == " " }))
                                .font(.title2.bold())
                                .accessibilityAddTraits(.isHeader)
                        } else {
                            Text(.init(paragraph)).font(.body)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.xl)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
