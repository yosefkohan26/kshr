import AppKit
import Carbon
import os.lock

class KeyboardLayout {
    /// Test-only override for the current input source ID.
    #if DEBUG
    static var debugInputSourceIdOverride: String?
    #endif

    // MARK: - Cached input-source ID

    /// Low-overhead lock protecting `_cachedId`. Using os_unfair_lock
    /// because this is read on every keystroke and must be fast.
    private static let _lock = OSAllocatedUnfairLock(initialState: String?.none)

    /// Seed the cache and register for input-source change notifications.
    /// Called lazily on first access to `id`.
    private static let _startObserving: Void = {
        // Seed with current value.
        _lock.withLock { $0 = queryCurrentId() }

        // Update cache when the user switches keyboard layouts.
        NotificationCenter.default.addObserver(
            forName: NSTextInputContext.keyboardSelectionDidChangeNotification,
            object: nil,
            queue: nil   // deliver on posting thread (main run loop)
        ) { _ in
            let newId = queryCurrentId()
            _lock.withLock { $0 = newId }
        }
    }()

    /// Return the cached input-source ID (no Carbon query per call).
    static var id: String? {
        #if DEBUG
        if let override = debugInputSourceIdOverride { return override }
        #endif
        _ = _startObserving   // ensure observer is registered
        return _lock.withLock { $0 }
    }

    /// Perform the actual Carbon query. Called once at init and once per
    /// input-source change notification.
    private static func queryCurrentId() -> String? {
        if let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
           let sourceIdPointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) {
            let sourceId = Unmanaged<CFString>.fromOpaque(sourceIdPointer).takeUnretainedValue()
            return sourceId as String
        }
        return nil
    }

    /// Translate a physical keyCode to the character AppKit would use for shortcut matching,
    /// preserving command-aware layouts such as "Dvorak - QWERTY Command".
    /// Some CJK input sources lack kTISPropertyUnicodeKeyLayoutData, and others (Korean
    /// 두벌식) have it but UCKeyTranslate still returns non-ASCII characters. In either
    /// case we fall back to TISCopyCurrentASCIICapableKeyboardInputSource().
    static func character(
        forKeyCode keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags = []
    ) -> String? {
        if let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
           let result = characterFromInputSource(source, forKeyCode: keyCode, modifierFlags: modifierFlags),
           result.allSatisfy(\.isASCII) {
            return result
        }
        // Current input source has no Unicode layout data or returned a non-ASCII
        // character (e.g. Korean 두벌식 has layout data but UCKeyTranslate still
        // produces Hangul). Fall back to the ASCII-capable source so shortcut
        // matching still works.
        if let asciiSource = TISCopyCurrentASCIICapableKeyboardInputSource()?.takeRetainedValue(),
           let result = characterFromInputSource(asciiSource, forKeyCode: keyCode, modifierFlags: modifierFlags) {
            return result
        }
        return nil
    }

    /// Return the ASCII-normalized equivalent of `event.charactersIgnoringModifiers`,
    /// falling back through the ASCII-capable input source for non-Latin input methods.
    /// Use this wherever code compares raw event characters against Latin shortcut keys.
    static func normalizedCharacters(for event: NSEvent) -> String {
        let raw = (event.charactersIgnoringModifiers ?? "").lowercased()
        if raw.allSatisfy(\.isASCII) { return raw }
        if let layoutChar = character(forKeyCode: event.keyCode, modifierFlags: []) {
            return layoutChar
        }
        return raw
    }

    private static func characterFromInputSource(
        _ source: TISInputSource,
        forKeyCode keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags
    ) -> String? {
        guard let layoutDataPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }

        let layoutData = unsafeBitCast(layoutDataPointer, to: CFData.self)
        guard let bytes = CFDataGetBytePtr(layoutData) else { return nil }
        let keyboardLayout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)

        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0

        let status = UCKeyTranslate(
            keyboardLayout,
            keyCode,
            UInt16(kUCKeyActionDisplay),
            translationModifierKeyState(for: modifierFlags),
            UInt32(LMGetKbdType()),
            UInt32(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            chars.count,
            &length,
            &chars
        )

        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length).lowercased()
    }

    private static func translationModifierKeyState(for modifierFlags: NSEvent.ModifierFlags) -> UInt32 {
        let normalized = modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .intersection([.shift, .command])

        var carbonModifiers: Int = 0
        if normalized.contains(.shift) {
            carbonModifiers |= shiftKey
        }
        if normalized.contains(.command) {
            carbonModifiers |= cmdKey
        }

        return UInt32((carbonModifiers >> 8) & 0xFF)
    }
}
