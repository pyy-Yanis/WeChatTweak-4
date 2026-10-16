import Foundation

@main
struct ResignerChecks {
    static func main() throws {
        let profile: [String: Any] = [
            "com.apple.application-identifier": "5A4RE8SF68.com.tencent.xinWeChat",
            "com.apple.security.app-sandbox": true,
            "com.apple.security.application-groups": ["5A4RE8SF68.com.tencent.xinWeChat"],
            "com.apple.security.device.camera": true,
            "com.apple.security.device.audio-input": true,
            "com.apple.developer.team-identifier": "5A4RE8SF68"
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: profile, format: .xml, options: 0)
        let modified = Resigner.inject(data)!
        let result = try PropertyListSerialization.propertyList(from: modified, options: [], format: nil) as! [String: Any]
        for key in profile.keys where !key.hasPrefix("com.apple.developer.") {
            assert((result[key] as! NSObject).isEqual(profile[key]))
        }
        assert(result["com.apple.developer.team-identifier"] == nil)
        assert(result["com.apple.security.cs.disable-library-validation"] as? Bool == true)
        assert(result["com.apple.security.cs.allow-unsigned-executable-memory"] as? Bool == true)
        assert(Resigner.inject(nil) == nil)
        assert(Resigner.plistsEqual(modified, Resigner.inject(modified)!))
        print("PASS: preserve sandbox/app-group/camera/mic, allow ad-hoc libraries/JIT, drop restricted developer entitlement, idempotent profiles")
    }
}
