import Foundation
import MachO

func decode(_ text: String) throws -> Config {
    try JSONDecoder().decode(Config.self, from: Data(text.utf8))
}

func fixture() -> Data {
    var data = Data(repeating: 0, count: 512)
    func put<T>(_ value: T, _ offset: Int) {
        var v = value
        withUnsafeBytes(of: &v) { data.replaceSubrange(offset..<(offset + $0.count), with: $0) }
    }
    put(UInt32(MH_MAGIC_64), 0)
    put(UInt32(CPU_TYPE_ARM64), 4)
    put(UInt32(1), 16)
    put(UInt32(72), 20)
    put(UInt32(LC_SEGMENT_64), 32)
    put(UInt32(72), 36)
    put(UInt64(0x100000000), 56)
    put(UInt64(512), 64)
    put(UInt64(0), 72)
    put(UInt64(512), 80)
    data.replaceSubrange(256..<264, with: [1,2,3,4,5,6,7,8])
    return data
}

let old = try decode(#"{"version":"old","targets":[]}"#)
assert(old.binaryPath == "Contents/MacOS/WeChat")
let new = try decode(#"{"version":"270091","binary":"Contents/Resources/wechat.dylib","targets":[]}"#)
assert(new.binaryPath == "Contents/Resources/wechat.dylib")
do {
    _ = try decode(#"{"version":"bad","binary":"../../outside","targets":[]}"#)
    fatalError("Unrecognized binary path accepted")
} catch {}
let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: dir) }
let binary = dir.appendingPathComponent("synthetic-macho")
let original = fixture()
let matching = try decode(#"{"version":"test","targets":[{"identifier":"multiInstance","entries":[{"arch":"arm64","addr":"100000100","asm":"20008052c0035fd6","expected":"0102030405060708"}]}]}"#)
try original.write(to: binary)
try Patcher.patch(binary: binary, config: matching)
let patched = try Data(contentsOf: binary)
assert(Array(patched[256..<264]) == [0x20,0,0x80,0x52,0xc0,3,0x5f,0xd6])
assert(patched.prefix(256) == original.prefix(256))
assert(patched.suffix(from: 264) == original.suffix(from: 264))
// Repeated application is harmless.
try Patcher.patch(binary: binary, config: matching)
try original.write(to: binary)
let mismatch = try decode(#"{"version":"test","targets":[{"identifier":"multiInstance","entries":[{"arch":"arm64","addr":"100000100","asm":"20008052c0035fd6","expected":"ffffffffffffffff"}]}]}"#)
do {
    try Patcher.patch(binary: binary, config: mismatch)
    fatalError("Mismatched original bytes accepted")
} catch {}
let afterMismatch = try Data(contentsOf: binary)
assert(afterMismatch == original)
let mismatchLater = try decode(#"{"version":"test","targets":[{"identifier":"revoke","entries":[{"arch":"arm64","addr":"100000100","asm":"82000014","expected":"01020304"},{"arch":"arm64","addr":"100000110","asm":"7fe600f9","expected":"ffffffff"}]}]}"#)
try original.write(to: binary)
do {
    try Patcher.patch(binary: binary, config: mismatchLater)
    fatalError("Later mismatched entry accepted")
} catch {}
let afterLaterMismatch = try Data(contentsOf: binary)
guard afterLaterMismatch == original else {
    print("FAIL: a later mismatch must prevent all writes")
    exit(1)
}
print("PASS: legacy config, target allowlist, patch mapping, idempotence, original-byte rejection")

// A universal executable must patch within its ARM64 slice, not the fat header.
var fat = Data(repeating: 0, count: 4096)
@MainActor func putBE(_ value: UInt32, at offset: Int) {
    var v = value.bigEndian
    withUnsafeBytes(of: &v) { fat.replaceSubrange(offset..<(offset + 4), with: $0) }
}
putBE(UInt32(FAT_MAGIC), at: 0)
putBE(1, at: 4)
putBE(UInt32(CPU_TYPE_ARM64), at: 8)
putBE(4096, at: 16)
putBE(UInt32(original.count), at: 20)
putBE(12, at: 24)
fat.append(original)
try fat.write(to: binary)
try Patcher.patch(binary: binary, config: matching)
let patchedFat = try Data(contentsOf: binary)
assert(patchedFat.prefix(4096) == fat.prefix(4096))
assert(Array(patchedFat[(4096+256)..<(4096+264)]) == [0x20,0,0x80,0x52,0xc0,3,0x5f,0xd6])

for invalid in ["GG", "0", "0102", ""] {
    let json = "{\"version\":\"test\",\"targets\":[{\"identifier\":\"x\",\"entries\":[{\"arch\":\"arm64\",\"addr\":\"100000100\",\"asm\":\"20008052c0035fd6\",\"expected\":\"\(invalid)\"}]}]}"
    do {
        _ = try decode(json)
        fatalError("Invalid expected bytes accepted")
    } catch {}
}
let bundled = URL(fileURLWithPath: CommandLine.arguments[1])
let allConfigs = try JSONDecoder().decode([Config].self, from: Data(contentsOf: bundled.appendingPathComponent("config.json")))
func configuration(_ version: String, _ mode: String? = nil) throws -> Config {
    guard let raw = allConfigs.first(where: { $0.version == version }) else {
        fatalError("Missing build \(version)")
    }
    return try raw.selecting(mode: mode)
}
let supported = try configuration("270091", "silent")
assert(supported.targets.map(\.identifier) == ["revoke", "multiInstance"])
assert(supported.binaryPath == "Contents/Resources/wechat.dylib")
assert(supported.targets[0].entries[0].addr == 0x4bbea28)
assert(supported.targets[0].entries[0].asm == Data([0x82,0,0,0x14]))
let legacyConfigs = allConfigs.filter { !["270091", "270135"].contains($0.version) }
assert(legacyConfigs.count == 5)
assert(legacyConfigs.allSatisfy { $0.binaryPath == "Contents/MacOS/WeChat" })
assert(allConfigs.count == 7 && Set(allConfigs.map(\.version)).count == 7)
print("PASS: fat slice isolation, malformed expected bytes, legacy configs, unique version blocks")

let syntheticApp = dir.appendingPathComponent("Synthetic.app")
let resourceBinary = syntheticApp.appendingPathComponent("Contents/Resources/wechat.dylib")
let mainBinary = syntheticApp.appendingPathComponent("Contents/MacOS/WeChat")
try FileManager.default.createDirectory(at: resourceBinary.deletingLastPathComponent(), withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: mainBinary.deletingLastPathComponent(), withIntermediateDirectories: true)
try original.write(to: resourceBinary)
try Data("untouched launcher".utf8).write(to: mainBinary)
let routed = try decode(#"{"version":"test","binary":"Contents/Resources/wechat.dylib","targets":[{"identifier":"multiInstance","entries":[{"arch":"arm64","addr":"100000100","asm":"20008052c0035fd6","expected":"0102030405060708"}]}]}"#)
try await Command.patch(app: syntheticApp, config: routed)
let routedBytes = try Data(contentsOf: resourceBinary)
let launcherBytes = try Data(contentsOf: mainBinary)
assert(routedBytes == patched)
assert(launcherBytes == Data("untouched launcher".utf8))
print("PASS: Command.patch selects the configured resource binary and preserves the launcher")

// Exercise the delivered 270091 configurations at their real offsets in a
// sparse, entirely synthetic file. No WeChat program is executed or modified.
var largeHeader = fixture()
func set64(_ data: inout Data, _ offset: Int, _ value: UInt64) {
    var v = value.littleEndian
    withUnsafeBytes(of: &v) { data.replaceSubrange(offset..<(offset + 8), with: $0) }
}
set64(&largeHeader, 56, 0)
set64(&largeHeader, 64, 0x5000000)
set64(&largeHeader, 80, 0x5000000)
let largeBinary = dir.appendingPathComponent("synthetic-270091")
try largeHeader.write(to: largeBinary)
let largeFile = try FileHandle(forUpdating: largeBinary)
defer { try? largeFile.close() }
try largeFile.truncate(atOffset: 0x5000000)
let pristinePoints: [(UInt64, Data)] = [
    (0x4bbea28, Data([0x40,0x10,0,0x34])),
    (0x4bbf1c8, Data([0x60,0xe6,0,0xf9])),
    (0x26dfa8, Data([0xff,3,6,0xd1,0xfc,0x6f,0x14,0xa9]))
]
for (offset, bytes) in pristinePoints {
    try largeFile.seek(toOffset: offset)
    try largeFile.write(contentsOf: bytes)
}
func readAt(_ fh: FileHandle, _ offset: UInt64, _ count: Int) throws -> Data {
    try fh.seek(toOffset: offset)
    return try fh.read(upToCount: count) ?? Data()
}
try Patcher.patch(binary: largeBinary, config: supported)
let silentBranch = try readAt(largeFile, 0x4bbea28, 4)
let untouchedTipStore = try readAt(largeFile, 0x4bbf1c8, 4)
let multiStub = try readAt(largeFile, 0x26dfa8, 8)
assert(silentBranch == Data([0x82,0,0,0x14]))
assert(untouchedTipStore == pristinePoints[1].1)
assert(multiStub == Data([0x20,0,0x80,0x52,0xc0,3,0x5f,0xd6]))
let oldTip = try configuration("270091", "tip")
try Patcher.patch(binary: largeBinary, config: oldTip)
let restoredBranch = try readAt(largeFile, 0x4bbea28, 4)
let zeroedIDStore = try readAt(largeFile, 0x4bbf1c8, 4)
assert(restoredBranch == pristinePoints[0].1)
assert(zeroedIDStore == Data([0x7f,0xe6,0,0xf9]))
try Patcher.patch(binary: largeBinary, config: oldTip)
print("PASS: delivered 270091 silent anti-revoke + multi, native-tip variant, silent-to-tip transition, repeat application")

try Patcher.patch(binary: largeBinary, config: supported)
let oldSilentBranch = try readAt(largeFile, 0x4bbea28, 4)
let oldRestoredStore = try readAt(largeFile, 0x4bbf1c8, 4)
assert(oldSilentBranch == Data([0x82,0,0,0x14]))
assert(oldRestoredStore == pristinePoints[1].1)
try Patcher.patch(binary: largeBinary, config: supported)
print("PASS: 270091 tip-to-silent restores ID store and supports repeat application")

let latest = try configuration("270135", "silent")
assert(latest.targets.map(\.identifier) == ["revoke", "multiInstance"])
assert(latest.targets[0].entries[0].addr == 0x4d1fb48)
assert(latest.targets[1].entries[0].addr == 0x286154)
try largeHeader.write(to: largeBinary)
let latestFile = try FileHandle(forUpdating: largeBinary)
defer { try? latestFile.close() }
try latestFile.truncate(atOffset: 0x5000000)
for (offset, bytes) in [(UInt64(0x4d202e8), Data([0x60,0xe6,0,0xf9])), (UInt64(0x353919c), Data([0xa0,0x12,0,0x34])), (UInt64(0x4d1fb48), Data([0x40,0x10,0,0x34])), (UInt64(0x286154), Data([0xff,3,6,0xd1,0xfc,0x6f,0x14,0xa9]))] {
    try latestFile.seek(toOffset: offset)
    try latestFile.write(contentsOf: bytes)
}
try Patcher.patch(binary: largeBinary, config: latest)
let latestBranch = try readAt(latestFile, 0x4d1fb48, 4)
let latestMulti = try readAt(latestFile, 0x286154, 8)
assert(latestBranch == Data([0x82,0,0,0x14]))
assert(latestMulti == Data([0x20,0,0x80,0x52,0xc0,3,0x5f,0xd6]))
print("PASS: current 270135 delivered config at actual offsets")

let latestTip = try configuration("270135", "private-tip")
let latestRestore = try configuration("270135", "silent")
assert(latestTip.version == "270135" && latestRestore.version == "270135")
assert(latestTip.targets.map(\.identifier) == ["revoke-keeptip", "multiInstance"])
let originalStore = Data([0x60,0xe6,0,0xf9])
let zeroStore = Data([0x7f,0xe6,0,0xf9])
try latestFile.seek(toOffset: 0x4d202e8)
try latestFile.write(contentsOf: originalStore)
for mode in [latestTip, latestTip, latestRestore, latestTip] {
    try Patcher.patch(binary: largeBinary, config: mode)
    let isTip = mode.targets[0].identifier == "revoke-keeptip"
    let branch = try readAt(latestFile, 0x4d1fb48, 4)
    let store = try readAt(latestFile, 0x4d202e8, 4)
    let multi = try readAt(latestFile, 0x286154, 8)
    assert(branch == (isTip ? Data([0x40,0x10,0,0x34]) : Data([0x82,0,0,0x14])))
    assert(store == (isTip ? zeroStore : originalStore))
    assert(multi == latestMulti)
}
// The same configuration must accept a pristine parser branch too.
try latestFile.seek(toOffset: 0x4d202e8)
try latestFile.write(contentsOf: originalStore)
try Patcher.patch(binary: largeBinary, config: latestTip)
let pristineToTip = try readAt(latestFile, 0x4d202e8, 4)
assert(pristineToTip == zeroStore)
print("PASS: 270135 native-tip pristine/silent transition, repeat apply, silent rollback, multi preserved")

let groupMode = try configuration("270135", "tip")
let groupRestore = try configuration("270135", "private-tip")
let groupSilent = try configuration("270135", "silent")
let defaultMode = try configuration("270135")
assert(defaultMode.targets[0].identifier == groupMode.targets[0].identifier)
let groupOriginal = Data([0xa0,0x12,0,0x34])
let groupPatched = Data([0x95,0,0,0x14])
try latestFile.seek(toOffset: 0x353919c)
try latestFile.write(contentsOf: groupOriginal)
for (mode, expectedGuard, expectedBranch, expectedStore) in [
    (groupMode, groupPatched, Data([0x40,0x10,0,0x34]), zeroStore),
    (groupMode, groupPatched, Data([0x40,0x10,0,0x34]), zeroStore),
    (groupRestore, groupOriginal, Data([0x40,0x10,0,0x34]), zeroStore),
    (groupMode, groupPatched, Data([0x40,0x10,0,0x34]), zeroStore),
    (groupSilent, groupOriginal, Data([0x82,0,0,0x14]), originalStore)
] {
    try Patcher.patch(binary: largeBinary, config: mode)
    let actualGuard = try readAt(latestFile, 0x353919c, 4)
    let actualBranch = try readAt(latestFile, 0x4d1fb48, 4)
    let actualStore = try readAt(latestFile, 0x4d202e8, 4)
    let actualMulti = try readAt(latestFile, 0x286154, 8)
    assert(actualGuard == expectedGuard)
    assert(actualBranch == expectedBranch)
    assert(actualStore == expectedStore)
    assert(actualMulti == latestMulti)
}
try latestFile.seek(toOffset: 0x4d1fb48)
try latestFile.write(contentsOf: Data([0x40,0x10,0,0x34]))
try Patcher.patch(binary: largeBinary, config: groupMode)
let pristineGroup = try readAt(latestFile, 0x353919c, 4)
let pristineStore = try readAt(latestFile, 0x4d202e8, 4)
assert(pristineGroup == groupPatched && pristineStore == zeroStore)
print("PASS: group native-tip switching, repeat application, private-tip/silent rollback, pristine parser, multi preserved")
