// MagicPad iOS haptic bridge (optional native shell)
// Safari cannot drive the Taptic Engine. Drop this into a WKWebView app:
//
//   contentController.add(self, name: "magicpadHaptic")
//   // page JS: window.webkit.messageHandlers.magicpadHaptic.postMessage({kind:"light"})
//
// This Mac does not have Xcode.app — sources only. No Bluetooth / no LLM.

import UIKit
import WebKit

final class MagicPadHapticBridge: NSObject, WKScriptMessageHandler {
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private let soft = UIImpactFeedbackGenerator(style: .soft)
    private let notify = UINotificationFeedbackGenerator()
    private let selection = UISelectionFeedbackGenerator()

    func prepare() {
        light.prepare()
        medium.prepare()
        heavy.prepare()
        soft.prepare()
        notify.prepare()
        selection.prepare()
    }

    func play(kind: String) {
        switch kind {
        case "light", "tap", "click", "pulse":
            light.impactOccurred()
        case "medium", "right", "smartzoom", "mission", "recordStart":
            medium.impactOccurred()
        case "heavy", "arm", "recordStop":
            heavy.impactOccurred()
        case "soft", "scrollArm":
            soft.impactOccurred()
        case "success", "select", "send":
            notify.notificationOccurred(.success)
        case "warning", "warn":
            notify.notificationOccurred(.warning)
        case "selection":
            selection.selectionChanged()
        default:
            light.impactOccurred()
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "magicpadHaptic" else { return }
        let kind: String
        if let dict = message.body as? [String: Any] {
            kind = (dict["kind"] as? String) ?? (dict["name"] as? String) ?? "light"
        } else if let s = message.body as? String {
            kind = s
        } else {
            kind = "light"
        }
        DispatchQueue.main.async { self.play(kind: kind) }
    }
}
