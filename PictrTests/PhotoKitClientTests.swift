import Foundation
import Photos
import Testing
@testable import Pictr

@Suite struct PhotoKitClientTests {
    @Test func recognisesUserCancel() {
        #expect(PhotoKitClient.isUserCancel(PHPhotosError(.userCancelled)))
        #expect(PhotoKitClient.isUserCancel(NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)))
        #expect(!PhotoKitClient.isUserCancel(NSError(domain: NSCocoaErrorDomain, code: 4)))
    }

    @Test func idFetchOptionsIncludeBurstExtras() {
        #expect(PhotoKitClient.idFetchOptions().includeAllBurstAssets)
    }
}
