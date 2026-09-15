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
             "capture", "captureOpen", "captureDown", "captureModels", "runslot1", "ollama", "meetingButtons", "meetingHand", "meetingLink", "meetingProbe",
             "welcome", "purr", "shot", "shotDemo", "shotSettings", "shotNotch", "shotMirror", "shotMarks", "clipboard", "clipboardUse", "clipboardDown", "openEvent", "assistant", "ask", "expand", "homeAll", "homeReset", "homePinned", "notePin", "noteChecklist", "critter", "critterEyes", "critterTail", "critterRun", "critterEars", "critterPaw", "critterSleep", "critterUpside", "critterYarn", "critterAngry", "critterFist", "critterKiss", "critterChase", "critterHunt", "critterCool", "critterSmoke", "critterWinter", "critterKittens", "critterFlowers", "critterTank", "critterEaster", "critterPumpkin", "critterValentine", "critterRibbon", "critterDragon", "critterRocket", "weatherScene", "weatherChange", "weatherHeavySnow", "weatherBlizzard", "weatherSun", "weatherClouds", "weatherFog", "weatherDrizzle", "weatherRain", "weatherSnow", "weatherThunder", "weatherWind",
             "shelf", "shelfZones", "shelfZip", "shelfUnzip", "shelfShare", "shelfTrash", "windowSlots", "windowLeft", "windowFill", "windowCycle", "countdownNow", "breakRest", "breakWater", "breakStretch", "ringMenu", "timer", "timerRun", "stopwatchRun", "monitor", "feeds", "feedsSites", "digestRun", "digestSuggest", "digestPill", "watchCheck", "watchProbe", "watchPill", "teleprompter", "teleprompterScroll", "teleprompterPrompt", "caffeine", "caffeineExpire", "caffeineOn", "keyboardLock", "keyboardLockRun", "keyboardLockExpire",
             "notes", "notesFill", "notesMiss", "calendar", "ring", "eventEdit", "eventNew", "eventSeries", "eventNotes", "notesAsk", "noteNew", "noteEdit", "noteSave",
             "noteSelection", "noteClipboard", "askLong", "mention", "mentionRun",
             "models", "modelPull", "modelsPair",
             "engine", "engineStart", "engineQuit", "engineVerify", "engineInstall",
             "agentTools", "agentTime", "agentSteps", "answerDown", "followUp", "monday", "agentCard", "agentCardNote", "agentRun", "agentAsk",
             "voice", "voiceAsk", "dictate", "voiceGlow", "voiceSpeak", "voiceAnswer",
             "update", "updatePill", "updateVerify", "updateInstall",
             "releaseNotes", "confetti", "shotConfetti",
             "obsidianScan", "obsidianSync", "obsidianLinks",
             "audioProbe", "devices", "recordStart", "recordStop", "recordNote", "installLanguage", "transcribeLast"]

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
