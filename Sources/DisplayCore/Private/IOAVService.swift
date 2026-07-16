import CoreGraphics
import Darwin
import Foundation
import IOKit

/// DDC/CI trên Apple Silicon qua private API IOAVService* (nạp runtime).
/// Mỗi màn hình ngoài có một DCPAVServiceProxy trong IORegistry; map với
/// CGDirectDisplayID bằng EDID UUID. Giao thức DDC: chip 0x37, data addr 0x51,
/// checksum XOR với 0x6E (theo m1ddc/MonitorControl).
enum IOAVServiceDDC {
    private typealias CreateWithServiceFn =
        @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<AnyObject>?
    private typealias I2CFn =
        @convention(c) (AnyObject?, UInt32, UInt32, UnsafeMutableRawPointer?, UInt32) -> IOReturn
    private static let coreDisplay: UnsafeMutableRawPointer? =
        dlopen("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_NOW)

    private static func symbol<T>(_ name: String, as _: T.Type) -> T? {
        guard let sym = dlsym(coreDisplay, name) ?? dlsym(dlopen(nil, RTLD_NOW), name) else { return nil }
        return unsafeBitCast(sym, to: T.self)
    }

    private static let createWithService =
        symbol("IOAVServiceCreateWithService", as: CreateWithServiceFn.self)
    private static let writeI2C = symbol("IOAVServiceWriteI2C", as: I2CFn.self)
    private static let readI2C = symbol("IOAVServiceReadI2C", as: I2CFn.self)

    static var isAvailable: Bool {
        createWithService != nil && writeI2C != nil && readI2C != nil
    }

    // MARK: - Map CGDirectDisplayID → IOAVService

    /// Ghép proxy ↔ màn hình bằng cách đọc EDID qua chính kênh I2C của proxy
    /// (chip 0x50, chuẩn DDC2) rồi so vendor/model/serial với CoreGraphics.
    /// Bền hơn dựa vào property của IORegistry ("EDID UUID" đã biến mất khỏi
    /// DCPAVServiceProxy từ macOS 26).
    /// Hạn chế đã biết: 2 màn hình cùng model + cùng serial thì không phân biệt được.
    static func avService(for displayID: CGDirectDisplayID) -> AnyObject? {
        guard let createWithService else { return nil }
        let vendor = CGDisplayVendorNumber(displayID)
        let model = CGDisplayModelNumber(displayID)
        let serial = CGDisplaySerialNumber(displayID)

        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault, IOServiceMatching("DCPAVServiceProxy"), &iterator) == KERN_SUCCESS
        else { return nil }
        defer { IOObjectRelease(iterator) }

        // Màn hình đang standby thường không trả lời cả lệnh đọc EDID —
        // gom các proxy "im lặng" lại; nếu không match được ai và chỉ có đúng
        // một proxy im lặng thì đó gần như chắc chắn là màn hình đang cần đánh thức.
        var silent: [AnyObject] = []

        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            defer { IOObjectRelease(service) }

            guard let location = registryString(service, "Location"), location == "External",
                  let av = createWithService(kCFAllocatorDefault, service)?.takeRetainedValue()
            else { continue }

            guard let edid = readEDID(av) else {
                silent.append(av)
                continue
            }

            // EDID: byte 8-9 vendor (big-endian), 10-11 product (little-endian),
            // 12-15 serial (little-endian) — khớp CGDisplayVendor/Model/SerialNumber.
            let edidVendor = UInt32(edid[8]) << 8 | UInt32(edid[9])
            let edidModel = UInt32(edid[10]) | UInt32(edid[11]) << 8
            let edidSerial = UInt32(edid[12]) | UInt32(edid[13]) << 8
                | UInt32(edid[14]) << 16 | UInt32(edid[15]) << 24
            if edidVendor == vendor, edidModel == model, edidSerial == serial {
                return av
            }
        }
        return silent.count == 1 ? silent[0] : nil
    }

    /// Đọc 128 byte EDID cơ bản qua I2C chip 0x50, xác thực header chuẩn.
    private static func readEDID(_ av: AnyObject) -> Data? {
        guard let readI2C else { return nil }
        var buffer = [UInt8](repeating: 0, count: 128)
        for attempt in 0..<3 {
            if attempt > 0 { usleep(20_000) }
            let ok = buffer.withUnsafeMutableBytes {
                readI2C(av, 0x50, 0x00, $0.baseAddress, 128) == KERN_SUCCESS
            }
            // Header EDID: 00 FF FF FF FF FF FF 00
            if ok, buffer[0] == 0x00, buffer[1] == 0xFF, buffer[6] == 0xFF, buffer[7] == 0x00 {
                return Data(buffer)
            }
        }
        return nil
    }

    private static func registryString(_ service: io_service_t, _ key: String) -> String? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? String
    }

    // MARK: - DDC/CI

    /// Ghi giá trị VCP (Set VCP Feature). Retry vì DDC hay lỗi vặt.
    static func writeVCP(_ service: AnyObject, code: UInt8, value: UInt16) -> Bool {
        guard let writeI2C else { return false }
        var packet: [UInt8] = [0x84, 0x03, code, UInt8(value >> 8), UInt8(value & 0xFF), 0]
        packet[5] = 0x6E ^ 0x51 ^ packet[0] ^ packet[1] ^ packet[2] ^ packet[3] ^ packet[4]
        for attempt in 0..<3 {
            if attempt > 0 { usleep(20_000) }
            let ok = packet.withUnsafeMutableBytes {
                writeI2C(service, 0x37, 0x51, $0.baseAddress, UInt32($0.count)) == KERN_SUCCESS
            }
            if ok { return true }
        }
        return false
    }

    /// Đọc giá trị VCP (Get VCP Feature). Trả về nil nếu màn hình không trả lời
    /// hợp lệ — dùng làm phép thử "có hỗ trợ DDC hay không".
    static func readVCP(_ service: AnyObject, code: UInt8) -> (current: UInt16, max: UInt16)? {
        guard let writeI2C, let readI2C else { return nil }
        var request: [UInt8] = [0x82, 0x01, code, 0]
        request[3] = 0x6E ^ 0x51 ^ request[0] ^ request[1] ^ request[2]
        for attempt in 0..<3 {
            if attempt > 0 { usleep(20_000) }
            let wrote = request.withUnsafeMutableBytes {
                writeI2C(service, 0x37, 0x51, $0.baseAddress, 4) == KERN_SUCCESS
            }
            guard wrote else { continue }
            usleep(40_000)
            var reply = [UInt8](repeating: 0, count: 12)
            let read = reply.withUnsafeMutableBytes {
                readI2C(service, 0x37, 0x51, $0.baseAddress, 12) == KERN_SUCCESS
            }
            // reply: [2]=0x02 (VCP reply), [3]=0 (NoError), [4]=vcp code,
            // [6..7]=max, [8..9]=current
            if read, reply[2] == 0x02, reply[3] == 0x00, reply[4] == code {
                return (UInt16(reply[8]) << 8 | UInt16(reply[9]),
                        UInt16(reply[6]) << 8 | UInt16(reply[7]))
            }
        }
        return nil
    }
}
