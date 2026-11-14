import AppKit
import Carbon
import Foundation

struct HotKeySpec: Equatable, Codable {
    var keyCode: UInt32
    var modifiers: UInt32

    /// Control-Option-Space.
    static let defaultSpec = HotKeySpec(keyCode: 0x31, modifiers: (1 << 12) | (1 << 11))

    var display: String {
        var parts: [String] = []
        if modifiers & (1 << 12) != 0 { parts.append("⌃") }
        if modifiers & (1 << 11) != 0 { parts.append("⌥") }
        if modifiers & (1 << 9) != 0 { parts.append("⇧") }
        if modifiers & (1 << 8) != 0 { parts.append("⌘") }
        parts.append(Self.keyName(keyCode))
        return parts.joined()
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var value: UInt32 = 0
        if flags.contains(.control) { value |= 1 << 12 }
        if flags.contains(.option) { value |= 1 << 11 }
        if flags.contains(.shift) { value |= 1 << 9 }
        if flags.contains(.command) { value |= 1 << 8 }
        return value
    }

    static func isModifierOnly(_ keyCode: UInt32) -> Bool {
        [0x37, 0x38, 0x39, 0x3A, 0x3B, 0x3C, 0x3D, 0x3E, 0x3F].contains(keyCode)
    }

    static func keyName(_ keyCode: UInt32) -> String {
        names[keyCode] ?? String(format: "Key %u", keyCode)
    }

    private static let names: [UInt32: String] = [
        0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F", 0x04: "H", 0x05: "G", 0x06: "Z", 0x07: "X",
        0x08: "C", 0x09: "V", 0x0B: "B", 0x0C: "Q", 0x0D: "W", 0x0E: "E", 0x0F: "R", 0x10: "Y",
        0x11: "T", 0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4", 0x16: "6", 0x17: "5", 0x18: "=",
        0x19: "9", 0x1A: "7", 0x1B: "-", 0x1C: "8", 0x1D: "0", 0x1E: "]", 0x1F: "O", 0x20: "U",
        0x21: "[", 0x22: "I", 0x23: "P", 0x24: "Return", 0x25: "L", 0x26: "J", 0x27: "'",
        0x28: "K", 0x29: ";", 0x2A: "\\", 0x2B: ",", 0x2C: "/", 0x2D: "N", 0x2E: "M", 0x2F: ".",
        0x30: "Tab", 0x31: "Space", 0x32: "`", 0x33: "Delete", 0x35: "Esc",
        0x7B: "←", 0x7C: "→", 0x7D: "↓", 0x7E: "↑"
    ]
}

/// One application-wide Carbon hotkey. The handler is a free function because Carbon calls a C function pointer.
final class HotKeyCenter {
    var onPress: (() -> Void)?
    private(set) var lastError: String?
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let signature: OSType = {
        var result: OSType = 0
        for byte in [UInt8]("CXAS".utf8) {
            result = (result << 8) + OSType(byte)
        }
        return result
    }()

    init() {
        HotKeyBridge.center = self
    }

    func register(_ spec: HotKeySpec) {
        unregister()
        installHandlerIfNeeded()
        var eventHotKey: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: signature, id: 1)
        let status = RegisterEventHotKey(
            spec.keyCode,
            spec.modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &eventHotKey
        )
        if status == noErr {
            hotKey = eventHotKey
            lastError = nil
            AssistantLog.hotkey.info("Registered global shortcut \(spec.display, privacy: .public)")
        } else {
            lastError = "Could not register \(spec.display) (OSStatus \(status)). Another app may already be using it."
            AssistantLog.hotkey.error("Hotkey registration failed: \(status)")
        }
    }

    func unregister() {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
    }

    fileprivate func handle(_ event: EventRef) -> OSStatus {
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            UInt32(kEventParamDirectObject),
            UInt32(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr, hotKeyID.signature == signature, hotKeyID.id == 1 else {
            return OSStatus(eventNotHandledErr)
        }
        DispatchQueue.main.async { [weak self] in
            self?.onPress?()
        }
        return noErr
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var eventSpec = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        ]
        var installed: EventHandlerRef?
        eventSpec.withUnsafeBufferPointer { buffer in
            InstallEventHandler(
                GetEventDispatcherTarget(),
                contextAssistantHotKeyHandler,
                1,
                buffer.baseAddress,
                nil,
                &installed
            )
        }
        handler = installed
    }
}

private enum HotKeyBridge {
    static weak var center: HotKeyCenter?
}

private func contextAssistantHotKeyHandler(
    eventHandlerCall: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }
    return HotKeyBridge.center?.handle(event) ?? OSStatus(eventNotHandledErr)
}
