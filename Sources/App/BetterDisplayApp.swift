import AppKit
import DisplayCore
import SwiftUI

@main
struct BetterDisplayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuView().environmentObject(state)
        } label: {
            Image(nsImage: Self.menuBarIcon)
            // Icon đổi trạng thái: hiện số màn hình đang tắt.
            if state.offCount > 0 {
                Text("\(state.offCount)")
            }
        }
        .menuBarExtraStyle(.window)
    }

    // Logo app thu nhỏ làm icon menu bar; size tính theo point nên
    // NSImage tự chọn bản @2x trên màn Retina.
    private static let menuBarIcon: NSImage = {
        let image = Bundle.module.image(forResource: "MenuBarIcon") ?? NSImage()
        image.size = NSSize(width: 18, height: 18)
        return image
    }()
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
