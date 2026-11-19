import CoreTransferable
import UniformTypeIdentifiers

/// A photo or video handed to the share sheet. The original file is only written when
/// the user picks where it goes.
struct SharedPhoto: Transferable {
    let id: String
    let isVideo: Bool
    let client: any PhotoLibraryClient

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .movie) { photo in
            SentTransferredFile(try await photo.client.exportOriginal(id: photo.id))
        }
        .exportingCondition { $0.isVideo }
        FileRepresentation(exportedContentType: .image) { photo in
            SentTransferredFile(try await photo.client.exportOriginal(id: photo.id))
        }
        .exportingCondition { !$0.isVideo }
    }
}
