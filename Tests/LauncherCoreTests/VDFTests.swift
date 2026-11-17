import Foundation
import Testing
@testable import LauncherCore

@Suite("VDF parser")
struct VDFTests {
    @Test func parsesAppManifest() throws {
        let root = try VDF.parse("""
        "AppState"
        {
            "appid"		"814380"
            "name"		"Sekiro™: Shadows Die Twice"
            "StateFlags"		"4"
            "SizeOnDisk"		"14960771294"
        }
        """)
        let state = try #require(root["AppState"])
        #expect(state["appid"]?.string == "814380")
        #expect(state["name"]?.string == "Sekiro™: Shadows Die Twice")
        #expect(state["SizeOnDisk"]?.string == "14960771294")
    }

    @Test func keysAreCaseInsensitive() throws {
        let root = try VDF.parse(#""AppState" { "appID" "10" }"#)
        #expect(root["appstate"]?["APPID"]?.string == "10")
    }

    @Test func decodesEscapes() throws {
        let root = try VDF.parse(#""k" { "path" "C:\\Program Files (x86)\\Steam" "q" "say \"hi\"" "nl" "a\nb" }"#)
        #expect(root["k"]?["path"]?.string == #"C:\Program Files (x86)\Steam"#)
        #expect(root["k"]?["q"]?.string == #"say "hi""#)
        #expect(root["k"]?["nl"]?.string == "a\nb")
    }

    @Test func handlesCommentsDirectivesAndConditions() throws {
        let root = try VDF.parse("""
        #base "other.vdf"
        // comment
        "a" { "b" "c" [$WIN32] // trailing
          "/usr/x" "1" }
        """)
        #expect(root["a"]?["b"]?.string == "c")
        #expect(root["a"]?["/usr/x"]?.string == "1")
    }

    /// Regression: the old tokenizer looped forever (and allocated GBs) on a bare token at end of input.
    @Test(.timeLimit(.minutes(1))) func bareTokenAtEndOfInputTerminates() throws {
        let root = try VDF.parse(#""j" bare"#)
        #expect(root["j"]?.string == "bare")
        let truncated = try VDF.parse(#""a" { "b" "c""#)
        #expect(truncated["a"]?["b"]?.string == "c")
    }

    @Test func nestedLibraryFolders() throws {
        let root = try VDF.parse("""
        "libraryfolders"
        {
            "0" { "path" "C:\\\\Program Files (x86)\\\\Steam" "apps" { "814380" "14960771294" } }
            "1" { "path" "D:\\\\SteamLibrary" }
        }
        """)
        let folders = try #require(root["libraryfolders"]?.object)
        #expect(folders.entries.count == 2)
        #expect(folders.entries[1].node["path"]?.string == #"D:\SteamLibrary"#)
        #expect(folders.entries[0].node["apps"]?["814380"]?.string == "14960771294")
    }

    @Test func strayClosingBraceAtRootThrows() {
        #expect(throws: VDFError.self) { try VDF.parse("}") }
    }

    @Test func skipsByteOrderMark() throws {
        let root = try VDF.parse("\u{FEFF}\"a\" \"b\"")
        #expect(root["a"]?.string == "b")
    }
}
