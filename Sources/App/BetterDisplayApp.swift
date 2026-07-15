import AppKit
import DisplayCore
import SwiftUI

@main
struct BetterDisplayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra("Better Display", systemImage: "display") {
            MenuView().environmentObject(state)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        // Gamma gắn với tiến trình — thoát app là màn hình tự sáng lại,
        // nên bật lại tường minh để state.json không kẹt record mồ côi.
        let store = StateStore()
        let manager = DisplayManager(store: store)
        for record in store.allDisabled() where record.strategy == .gamma {
            _ = try? manager.setPower(true, displayID: record.displayID, preferred: .gamma)
        }
    }
}
