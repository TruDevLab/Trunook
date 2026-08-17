// Вызывает плашку события в запущенном Trunook.
//
//   swift scripts/debug-event.swift lowBattery
//
// Работает только когда включён журнал отладки (~/Library/Logs/Trunook.debug).
//
// notifyutil здесь не годится: он работает с notify(3), а приложение слушает
// DistributedNotificationCenter — это разные механизмы.

import Foundation

let known = ["powerConnected", "powerDisconnected", "lowBattery", "trackChanged",
             "settings", "meeting", "links", "nextTrack", "reminder", "dump", "thingsRaw", "notifications",
             "commands", "runslot1", "ollama", "meetingButtons", "meetingHand", "meetingLink", "meetingProbe",
             "welcome", "purr", "shot", "shotSettings", "shotNotch", "clipboard", "clipboardUse", "openEvent", "assistant", "expand",
             "shelf", "hub"]

guard CommandLine.arguments.count > 1, known.contains(CommandLine.arguments[1]) else {
    print("Использование: swift scripts/debug-event.swift <\(known.joined(separator: "|"))>")
    exit(1)
}

let event = CommandLine.arguments[1]
DistributedNotificationCenter.default().postNotificationName(
    Notification.Name("com.trunook.debug.\(event)"),
    object: nil,
    userInfo: nil,
    deliverImmediately: true
)
print("отправлено: com.trunook.debug.\(event)")
