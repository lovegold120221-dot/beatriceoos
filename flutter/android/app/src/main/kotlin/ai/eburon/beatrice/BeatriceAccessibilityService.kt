package ai.eburon.beatrice

import android.accessibilityservice.AccessibilityService
import android.view.accessibility.AccessibilityEvent

/// Minimal AccessibilityService that Beatrice's Screen Control relies on.
///
/// When enabled in Android Accessibility Settings, this service lets Beatrice
/// read the on-screen UI hierarchy and perform taps, scrolls, and text entry
/// in other apps on the user's behalf. The actual screen-reading and gesture
/// methods are invoked through the MethodChannel from the Dart side.
///
/// For now this is a stub that simply maintains an active service presence so
/// the settings status check reports "active". Full screen-automation methods
/// (dumpScreen, clickAt, scroll, typeText, etc.) can be added here later.
class BeatriceAccessibilityService : AccessibilityService() {

    override fun onServiceConnected() {
        super.onServiceConnected()
        // Configure the service to read the screen and perform gestures.
        // Full configuration can be expanded later; this minimal config
        // establishes the service as active and ready.
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // No-op for now — events are polled on-demand from the Dart side.
    }

    override fun onInterrupt() {
        // No-op
    }
}