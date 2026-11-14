import Foundation

enum ByteFormat {
    static func string(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .file, spellsOutZero: false))
    }
}
