import Testing
import Foundation
@testable import MacGamingLauncher

@Suite("VDF Parser Tests")
struct VDFParserTests {

    @Test("Parse simple key values")
    func testSimpleVDF() throws {
        let vdf = """
        "AppState"
        {
            "appid" "814380"
            "name" "Sekiro™: Shadows Die Twice"
            "SizeOnDisk" "14960771294"
        }
        """

        let result = try VDFParser.parse(string: vdf)
        let appState = try #require(result["AppState"]?.dictionaryValue)

        #expect(appState["appid"]?.stringValue == "814380")
        #expect(appState["name"]?.stringValue == "Sekiro™: Shadows Die Twice")
        #expect(appState["SizeOnDisk"]?.stringValue == "14960771294")
    }

    @Test("Parse nested libraryfolders")
    func testNestedLibraryFolders() throws {
        let vdf = """
        "libraryfolders"
        {
            "0"
            {
                "path" "C:\\\\Program Files (x86)\\\\Steam"
                "apps"
                {
                    "814380" "14960771294"
                    "2344520" "173483678463"
                }
            }
        }
        """

        let result = try VDFParser.parse(string: vdf)
        let folders = try #require(result["libraryfolders"]?.dictionaryValue)
        let folder0 = try #require(folders["0"]?.dictionaryValue)
        let apps = try #require(folder0["apps"]?.dictionaryValue)

        #expect(apps["814380"]?.stringValue == "14960771294")
        #expect(apps["2344520"]?.stringValue == "173483678463")
    }
}

@Suite("Engine and Bottle Discovery Tests")
struct DiscoveryTests {

    @Test("Discover local bottles")
    func testBottleDiscovery() {
        let bottles = BottleService.shared.discoverBottles()
        // If the user has bottles, verify parsing
        if let steamBottle = bottles.first(where: { $0.name == "Steam" }) {
            #expect(steamBottle.hasSteamInstalled == true)
        }
    }

    @Test("Discover local engines")
    func testEngineDiscovery() {
        let engines = EngineService.shared.discoverEngines()
        // Should find CrossOver on this machine
        #expect(!engines.isEmpty)
        if let first = engines.first {
            #expect(first.hasMSync == true)
            #expect(first.hasD3DMetal == true)
        }
    }
}
