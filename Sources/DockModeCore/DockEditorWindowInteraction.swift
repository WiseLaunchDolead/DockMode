import AppKit

public enum DockEditorWindowInteraction {
    @MainActor
    public static func configure(_ window: NSWindow) {
        // A full-size translucent window otherwise treats the preview as a
        // draggable background and intercepts item drag-and-drop gestures.
        window.isMovableByWindowBackground = false
    }
}
