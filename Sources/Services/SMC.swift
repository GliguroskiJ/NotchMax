import Foundation
import IOKit

// MARK: - C rozložení struktur AppleSMC
//
// Zrcadlí SMCKeyData_t z AppleSMC (smc.h):
//
// typedef struct {
//     UInt32               key;         // offset  0
//     SMCKeyData_vers_t    vers;        // offset  4 (6 B: 4× UInt8 + UInt16)
//     SMCKeyData_pLimitData_t pLimitData; // offset 12 (16 B)
//     SMCKeyData_keyInfo_t keyInfo;     // offset 28 (9 B dat + 3 B výplně v C)
//     UInt8                result;      // offset 40
//     UInt8                status;      // offset 41
//     UInt8                data8;       // offset 42
//     UInt32               data32;      // offset 44
//     SMCBytes_t           bytes;       // offset 48 (32 B)
// } SMCKeyData_t;                       // velikost 80 B
//
// Pozor: Swift na rozdíl od C umisťuje další pole hned za `size` vnořené struktury (ne za `stride`),
// takže za `keyInfo` (size 9, stride 12) musí být explicitní 3 bajty výplně, aby `result` vyšel na offset 40.

struct SMCVersion {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

struct SMCPLimitData {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}

struct SMCKeyInfoData {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
}

typealias SMCBytes = (
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
)

/// MemoryLayout<SMCKeyData>.size == 80 (ověřeno za běhu v `SMCClient.layoutIsValid`).
struct SMCKeyData {
    var key: UInt32 = 0                                   // 0
    var vers = SMCVersion()                               // 4
    var pLimitData = SMCPLimitData()                      // 12
    var keyInfo = SMCKeyInfoData()                        // 28 (size 9)
    var keyInfoPadding: (UInt8, UInt8, UInt8) = (0, 0, 0) // 37 – výplň jako v C
    var result: UInt8 = 0                                 // 40
    var status: UInt8 = 0                                 // 41
    var data8: UInt8 = 0                                  // 42
    var data32: UInt32 = 0                                // 44
    var bytes: SMCBytes = (
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    )                                                     // 48 … 80
}

// MARK: - Klient

/// Minimalistický klient AppleSMC přes IOKit. Není thread-safe – používat z jedné fronty.
/// Při jakékoli chybě vrací `nil`, nikdy nespadne.
final class SMCClient {
    private enum Command: UInt8 {
        case readKey = 5
        case getKeyFromIndex = 8
        case getKeyInfo = 9
    }

    /// Selektor `kSMCHandleYPCEvent` uživatelského klienta AppleSMC.
    private static let kernelIndex: UInt32 = 2

    /// Ověří, že Swift struktura přesně odpovídá C rozložení (jinak SMC vůbec nepoužijeme).
    static let layoutIsValid: Bool = {
        MemoryLayout<SMCKeyData>.size == 80
            && MemoryLayout<SMCKeyData>.offset(of: \SMCKeyData.pLimitData) == 12
            && MemoryLayout<SMCKeyData>.offset(of: \SMCKeyData.keyInfo) == 28
            && MemoryLayout<SMCKeyData>.offset(of: \SMCKeyData.result) == 40
            && MemoryLayout<SMCKeyData>.offset(of: \SMCKeyData.data32) == 44
            && MemoryLayout<SMCKeyData>.offset(of: \SMCKeyData.bytes) == 48
    }()

    private var connection: io_connect_t = 0
    private var keyInfoCache: [UInt32: SMCKeyInfoData] = [:]

    init?() {
        guard SMCClient.layoutIsValid else { return nil }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var conn: io_connect_t = 0
        let result = IOServiceOpen(service, mach_task_self_, 0, &conn)
        guard result == kIOReturnSuccess, conn != 0 else { return nil }
        connection = conn
    }

    deinit {
        if connection != 0 {
            IOServiceClose(connection)
            connection = 0
        }
    }

    // MARK: FourCC

    static func fourCC(_ string: String) -> UInt32 {
        var value: UInt32 = 0
        let bytes = Array(string.utf8.prefix(4))
        for i in 0..<4 {
            let byte: UInt8 = i < bytes.count ? bytes[i] : 0x20
            value = (value << 8) | UInt32(byte)
        }
        return value
    }

    static func string(fromFourCC value: UInt32) -> String {
        let bytes: [UInt8] = [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF)
        ]
        return String(decoding: bytes, as: UTF8.self)
    }

    // MARK: Nízkoúrovňové volání

    private func call(_ input: SMCKeyData) -> SMCKeyData? {
        guard connection != 0 else { return nil }
        var inputStruct = input
        var outputStruct = SMCKeyData()
        var outputSize = MemoryLayout<SMCKeyData>.stride
        let result = withUnsafePointer(to: &inputStruct) { inPtr -> kern_return_t in
            withUnsafeMutablePointer(to: &outputStruct) { outPtr -> kern_return_t in
                IOConnectCallStructMethod(
                    connection,
                    SMCClient.kernelIndex,
                    UnsafeRawPointer(inPtr),
                    MemoryLayout<SMCKeyData>.stride,
                    UnsafeMutableRawPointer(outPtr),
                    &outputSize
                )
            }
        }
        guard result == kIOReturnSuccess, outputStruct.result == 0 else { return nil }
        return outputStruct
    }

    func keyInfo(_ key: UInt32) -> SMCKeyInfoData? {
        if let cached = keyInfoCache[key] { return cached }
        var input = SMCKeyData()
        input.key = key
        input.data8 = Command.getKeyInfo.rawValue
        guard let output = call(input), output.keyInfo.dataSize > 0 else { return nil }
        keyInfoCache[key] = output.keyInfo
        return output.keyInfo
    }

    /// Surová data klíče (typ + bajty o délce `dataSize`).
    func readRaw(_ key: String) -> (info: SMCKeyInfoData, bytes: [UInt8])? {
        let code = SMCClient.fourCC(key)
        guard let info = keyInfo(code) else { return nil }
        var input = SMCKeyData()
        input.key = code
        input.keyInfo.dataSize = info.dataSize
        input.data8 = Command.readKey.rawValue
        guard let output = call(input) else { return nil }
        let size = min(Int(info.dataSize), 32)
        let all: [UInt8] = withUnsafeBytes(of: output.bytes) { Array($0) }
        return (info, Array(all.prefix(size)))
    }

    /// Hodnota klíče převedená na číslo podle datového typu; `nil`, pokud klíč chybí nebo typ neznáme.
    func readValue(_ key: String) -> Double? {
        guard let raw = readRaw(key) else { return nil }
        return SMCClient.decode(type: raw.info.dataType, bytes: raw.bytes)
    }

    /// Počet klíčů (`#KEY`).
    func keyCount() -> Int {
        guard let raw = readRaw("#KEY"), raw.bytes.count >= 4 else { return 0 }
        let b = raw.bytes
        let value = (UInt32(b[0]) << 24) | (UInt32(b[1]) << 16) | (UInt32(b[2]) << 8) | UInt32(b[3])
        return Int(value)
    }

    /// Klíč na daném indexu (pro výčet všech klíčů).
    func key(at index: Int) -> String? {
        var input = SMCKeyData()
        input.data8 = Command.getKeyFromIndex.rawValue
        input.data32 = UInt32(truncatingIfNeeded: index)
        guard let output = call(input), output.key != 0 else { return nil }
        return SMCClient.string(fromFourCC: output.key)
    }

    /// Datový typ klíče jako řetězec (např. "flt ", "sp78").
    func dataType(of key: String) -> String? {
        guard let info = keyInfo(SMCClient.fourCC(key)) else { return nil }
        return SMCClient.string(fromFourCC: info.dataType)
    }

    // MARK: Dekódování

    static func decode(type: UInt32, bytes b: [UInt8]) -> Double? {
        switch string(fromFourCC: type) {
        case "flt ":
            // Apple Silicon: Float32 little endian.
            guard b.count >= 4 else { return nil }
            let bits = UInt32(b[0]) | (UInt32(b[1]) << 8) | (UInt32(b[2]) << 16) | (UInt32(b[3]) << 24)
            let value = Double(Float(bitPattern: bits))
            return value.isFinite ? value : nil
        case "sp78":
            guard b.count >= 2 else { return nil }
            let raw = Int16(bitPattern: (UInt16(b[0]) << 8) | UInt16(b[1]))
            return Double(raw) / 256.0
        case "fpe2":
            guard b.count >= 2 else { return nil }
            let raw = (UInt16(b[0]) << 8) | UInt16(b[1])
            return Double(raw) / 4.0
        case "ui8 ":
            guard b.count >= 1 else { return nil }
            return Double(b[0])
        case "ui16":
            guard b.count >= 2 else { return nil }
            return Double((UInt16(b[0]) << 8) | UInt16(b[1]))
        case "ui32":
            guard b.count >= 4 else { return nil }
            let raw = (UInt32(b[0]) << 24) | (UInt32(b[1]) << 16) | (UInt32(b[2]) << 8) | UInt32(b[3])
            return Double(raw)
        default:
            return nil
        }
    }
}
