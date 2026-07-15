import CoreGraphics
import Foundation

/// Theo dõi sự kiện cắm/rút/đổi cấu hình màn hình qua
/// CGDisplayRegisterReconfigurationCallback. Một lần cắm màn hình sinh nhiều
/// callback liên tiếp nên có debounce trước khi báo ra ngoài.
public final class EventMonitor {
    public var onChange: (() -> Void)?

    private let debounceInterval: TimeInterval
    private var pending: DispatchWorkItem?
    private var started = false

    public init(debounce: TimeInterval = 0.3) {
        self.debounceInterval = debounce
    }

    public func start() {
        guard !started else { return }
        started = true
        CGDisplayRegisterReconfigurationCallback(
            reconfigurationCallback, Unmanaged.passUnretained(self).toOpaque())
    }

    public func stop() {
        guard started else { return }
        started = false
        CGDisplayRemoveReconfigurationCallback(
            reconfigurationCallback, Unmanaged.passUnretained(self).toOpaque())
    }

    deinit { stop() }

    fileprivate func scheduleNotify() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange?() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: work)
    }
}

private func reconfigurationCallback(
    displayID: CGDirectDisplayID,
    flags: CGDisplayChangeSummaryFlags,
    userInfo: UnsafeMutableRawPointer?
) {
    guard let userInfo else { return }
    Unmanaged<EventMonitor>.fromOpaque(userInfo).takeUnretainedValue().scheduleNotify()
}
