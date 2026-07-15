import XCTest
@testable import DisplayCore

final class DisplayCoreTests: XCTestCase {

    private func makeDisplay(
        id: CGDirectDisplayID, name: String = "Test", isEnabled: Bool = true
    ) -> DisplayInfo {
        DisplayInfo(
            id: id,
            persistentKey: "v1-m2-s\(id)",
            name: name,
            isBuiltin: false,
            isMain: id == 1,
            resolution: CGSize(width: 1920, height: 1080),
            refreshRate: 60,
            isEnabled: isEnabled,
            isMirrored: false)
    }

    // MARK: - persistentKey

    func testPersistentKeyFormat() {
        XCTAssertEqual(
            DisplayManager.persistentKey(vendor: 1552, model: 41147, serial: 0),
            "v1552-m41147-s0")
    }

    // MARK: - SafetyGuard

    func testSafetyGuardBlocksLastActiveDisplay() {
        let only = makeDisplay(id: 1, name: "EK241Y")
        XCTAssertThrowsError(try SafetyGuard.validateTurnOff(target: only, all: [only])) { error in
            XCTAssertEqual(
                error as? PowerControlError,
                .wouldDisableLastDisplay("EK241Y"))
        }
    }

    func testSafetyGuardAllowsWhenAnotherDisplayActive() {
        let a = makeDisplay(id: 1)
        let b = makeDisplay(id: 2)
        XCTAssertNoThrow(try SafetyGuard.validateTurnOff(target: a, all: [a, b]))
    }

    func testSafetyGuardBlocksWhenOtherDisplaysAlreadyOff() {
        let a = makeDisplay(id: 1)
        let b = makeDisplay(id: 2, isEnabled: false)
        XCTAssertThrowsError(try SafetyGuard.validateTurnOff(target: a, all: [a, b]))
    }

    func testSafetyGuardSkipsAlreadyDisabledTarget() {
        let a = makeDisplay(id: 1, isEnabled: false)
        XCTAssertNoThrow(try SafetyGuard.validateTurnOff(target: a, all: [a]))
    }

    // MARK: - StateStore

    func testStateStoreRoundtrip() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("displayctl-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = StateStore(directory: dir)
        store.recordDisabled(DisabledRecord(
            displayID: 42, persistentKey: "v1-m2-s3", strategy: .disconnect, date: Date()))

        // Mở lại từ đĩa — phải đọc được đúng record đã ghi.
        let reloaded = StateStore(directory: dir)
        let record = reloaded.disabledRecord(for: 42)
        XCTAssertEqual(record?.persistentKey, "v1-m2-s3")
        XCTAssertEqual(record?.strategy, .disconnect)

        reloaded.removeDisabled(displayID: 42)
        XCTAssertNil(StateStore(directory: dir).disabledRecord(for: 42))
    }

    func testStateStoreOverwritesSameDisplay() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("displayctl-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = StateStore(directory: dir)
        store.recordDisabled(DisabledRecord(
            displayID: 7, persistentKey: "k", strategy: .gamma, date: Date()))
        store.recordDisabled(DisabledRecord(
            displayID: 7, persistentKey: "k", strategy: .disconnect, date: Date()))

        XCTAssertEqual(store.allDisabled().count, 1)
        XCTAssertEqual(store.disabledRecord(for: 7)?.strategy, .disconnect)
    }
}
