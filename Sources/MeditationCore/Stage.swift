import Foundation

/// The owner's five files are mapped explicitly. Never infer order from a directory listing.
public struct Stage: Identifiable, Equatable, Sendable {
    public let id: Int
    public let title: String
    public let context: String
    public let transliteration: String
    public let fileName: String

    public var label: String { context.isEmpty ? title : "\(title) — \(context)" }
    public var assetID: String { String(format: "stage_%02d", id) }

    public static let all: [Stage] = [
        Stage(id: 1, title: "बीज रूप", context: "परमधाम में",
              transliteration: "Beej roop paramdham me", fileName: "pic_1.png"),
        Stage(id: 2, title: "विश्व महाराजन", context: "सतयुग में",
              transliteration: "Vishwa Maharajan satyug me", fileName: "pic_2.jpg"),
        Stage(id: 3, title: "पूज्य स्वरूप", context: "द्वापर युग में",
              transliteration: "Pujya Swaroop dwapar yug me", fileName: "pic_3.png"),
        Stage(id: 4, title: "परम पवित्र ब्राह्मण", context: "कलियुग में",
              transliteration: "Param Pavitra Brahmin Kalyug me", fileName: "pic_4.png"),
        Stage(id: 5, title: "फरिश्ता स्वरूप", context: "",
              transliteration: "Farishta swaroop", fileName: "pic_5.png")
    ]
}
