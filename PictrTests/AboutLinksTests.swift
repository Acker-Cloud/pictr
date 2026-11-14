import Foundation
import Testing
@testable import Pictr

@Suite struct AboutLinksTests {
    @Test func everyLinkPointsAtPictrsOwnPages() {
        let web = [AboutLinks.home, AboutLinks.privacy, AboutLinks.terms, AboutLinks.help]
        #expect(web.allSatisfy { $0.scheme == "https" && $0.host == "acker.cloud" && $0.path.hasPrefix("/pictr") })
        let code = [AboutLinks.source, AboutLinks.issues, AboutLinks.license]
        #expect(code.allSatisfy { $0.scheme == "https" && $0.host == "github.com" && $0.path.hasPrefix("/Acker-Cloud/pictr") })
        #expect(AboutLinks.support.absoluteString == "mailto:support@acker.cloud")
    }
}
