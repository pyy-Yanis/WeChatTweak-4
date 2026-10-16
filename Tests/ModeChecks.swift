import Foundation

@main
struct ModeChecks {
    static func main() throws {
        let json = #"{"version":"test","defaultMode":"tip","targets":[{"identifier":"multiInstance","entries":[]}],"modes":{"silent":[{"identifier":"revoke","entries":[]}],"tip":[{"identifier":"revoke-keeptip-group","entries":[]}]}}"#
        let config = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        let tip = try config.selecting(mode: nil)
        assert(tip.targets.map(\.identifier) == ["revoke-keeptip-group", "multiInstance"])
        let silent = try config.selecting(mode: "silent")
        assert(silent.targets.map(\.identifier) == ["revoke", "multiInstance"])
        do { _ = try config.selecting(mode: "typo"); fatalError("Unknown mode accepted") } catch Config.ModeError.unsupported { }
        let legacy = try JSONDecoder().decode(Config.self, from: Data(#"{"version":"old","targets":[]}"#.utf8))
        let legacyDefault = try legacy.selecting(mode: nil)
        let legacySilent = try legacy.selecting(mode: "silent")
        assert(legacyDefault.targets.isEmpty && legacySilent.targets.isEmpty)
        do { _ = try legacy.selecting(mode: "tip"); fatalError("Unsupported legacy tip accepted") } catch Config.ModeError.unsupported { }
        print("PASS: default tip, explicit silent, shared targets, unknown mode rejection, legacy compatibility")
    }
}
