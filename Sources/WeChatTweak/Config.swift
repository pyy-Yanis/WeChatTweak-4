//
//  Config.swift
//  WeChatTweak
//
//  Created by Sunny Young on 2025/12/5.
//

import Foundation
import MachO

struct Config: Decodable {
    enum Binary: String, Decodable {
        case main = "Contents/MacOS/WeChat"
        case resources = "Contents/Resources/wechat.dylib"
    }

    enum Arch: String, Decodable {
        case arm64
        case x86_64

        var cpu: UInt32 {
            switch self {
            case .arm64:
                return UInt32(CPU_TYPE_ARM64)
            case .x86_64:
                return UInt32(CPU_TYPE_X86_64)
            }
        }
    }

    struct Entry: Decodable {
        let arch: Arch
        let addr: UInt64
        let asm: Data
        let expected: Data?

        private enum CodingKeys: CodingKey {
            case arch
            case addr
            case asm
            case expected
        }

        init(from decoder: any Decoder) throws {
            let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
            self.arch = try container.decode(Arch.self, forKey: .arch)
            self.addr = try {
                let hex = try container.decode(String.self, forKey: .addr)
                guard let value = UInt64(hex, radix: 16) else {
                    throw DecodingError.dataCorruptedError(
                        forKey: CodingKeys.addr,
                        in: container,
                        debugDescription: "Invalid Entry.addr"
                    )
                }
                return value
            }()
            self.asm = try {
                let hex = try container.decode(String.self, forKey: .asm)
                guard let value = Data(hex: hex) else {
                    throw DecodingError.dataCorruptedError(
                        forKey: CodingKeys.asm,
                        in: container,
                        debugDescription: "Invalid Entry.asm"
                    )
                }
                return value
            }()
            if let hex = try container.decodeIfPresent(String.self, forKey: .expected) {
                guard let value = Data(hex: hex), !value.isEmpty, value.count == asm.count else {
                    throw DecodingError.dataCorruptedError(
                        forKey: CodingKeys.expected,
                        in: container,
                        debugDescription: "Entry.expected must match the patch length"
                    )
                }
                self.expected = value
            } else {
                self.expected = nil
            }
        }
    }

    struct Target: Decodable {
        let identifier: String
        let entries: [Entry]

        private enum CodingKeys: CodingKey {
            case identifier
            case entries
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.identifier = try container.decode(String.self, forKey: .identifier)
            self.entries = try container.decode([Entry].self, forKey: .entries)
        }
    }

    let version: String
    let binary: Binary?
    let targets: [Target]

    let defaultMode: String?
    let modes: [String: [Target]]?

    enum ModeError: LocalizedError {
        case unsupported(version: String, mode: String, available: [String])
        var errorDescription: String? {
            switch self {
            case let .unsupported(version, mode, available):
                return "Mode '\(mode)' is not supported for build \(version). Available: \(available.joined(separator: ", "))"
            }
        }
    }

    var availableModes: [String] { modes?.keys.sorted() ?? ["silent"] }

    func selecting(mode: String?) throws -> Config {
        guard let modes else {
            guard mode == nil || mode == "silent" else {
                throw ModeError.unsupported(version: version, mode: mode!, available: availableModes)
            }
            return self
        }
        let selected = mode ?? defaultMode ?? "silent"
        guard let selectedTargets = modes[selected], !selectedTargets.isEmpty else {
            throw ModeError.unsupported(version: version, mode: selected, available: availableModes)
        }
        return Config(version: version, binary: binary, targets: selectedTargets + targets, defaultMode: nil, modes: nil)
    }

    var binaryPath: String { (binary ?? .main).rawValue }

    static func load(url: URL) async throws -> [Config] {
        if url.isFileURL {
            return try JSONDecoder().decode(
                [Config].self,
                from: Data(contentsOf: url)
            )
        } else {
            return try JSONDecoder().decode(
                [Config].self,
                from: try await URLSession.shared.data(from: url).0
            )
        }
    }
}

private extension Data {
    init?(hex: String) {
        let chars = Array(hex.utf8)
        guard chars.count % 2 == 0 else { return nil }

        self.init()
        self.reserveCapacity(chars.count / 2)

        func nibble(_ c: UInt8) -> UInt8? {
            switch c {
            case 48...57:  return c - 48       // '0'...'9'
            case 65...70:  return c - 55       // 'A'...'F'
            case 97...102: return c - 87       // 'a'...'f'
            default:       return nil
            }
        }

        var i = 0
        while i < chars.count {
            guard let hi = nibble(chars[i]),
                  let lo = nibble(chars[i + 1]) else { return nil }
            append(hi << 4 | lo)
            i += 2
        }
    }
}
