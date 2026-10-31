import SwiftUI
import UIKit
import UniformTypeIdentifiers
import ZemuCore

#if os(tvOS)

// The screens are shared with iOS. These no-ops stand in for the pointer, keyboard and file APIs
// tvOS doesn't have, so the screens stay almost line-for-line the same.

enum TVKeyShortcut { case defaultAction, cancelAction, `return` }

extension View {
    func onHover(perform action: @escaping (Bool) -> Void) -> some View { self }
    func onDrop(of types: [UTType], isTargeted: Binding<Bool>?, perform action: @escaping ([NSItemProvider]) -> Bool) -> some View { self }
    func fileImporter(isPresented: Binding<Bool>, allowedContentTypes: [UTType], onCompletion: @escaping (Result<URL, Error>) -> Void) -> some View { self }
    func keyboardShortcut(_ key: TVKeyShortcut, modifiers: [Never] = []) -> some View { self }
    func textSelection(_ selectable: TVTextSelection) -> some View { self }
    func statusBarHidden() -> some View { self }
}

enum TVTextSelection { case enabled }

extension TextFieldStyle where Self == DefaultTextFieldStyle {
    static var roundedBorder: DefaultTextFieldStyle { .init() }
}
#endif

extension Meta {
    /** The trailer to offer. tvOS has no web view, so it needs the YouTube app; without it, no trailer buttons. */
    @MainActor var offeredTrailerId: String? {
        #if os(tvOS)
        guard let url = URL(string: "youtube://"), UIApplication.shared.canOpenURL(url) else { return nil }
        #endif
        return trailerId
    }
}
