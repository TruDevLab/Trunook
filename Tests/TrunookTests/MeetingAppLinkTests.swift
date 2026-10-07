import Foundation
import Testing
@testable import Trunook

@Suite("Ссылка на встречу — для приложения")
struct MeetingAppLinkTests {
    private func app(_ text: String) -> MeetingLink.NativeApp? {
        MeetingLink.extract(url: URL(string: text), location: nil, notes: nil)?.nativeApp
    }

    @Test("Zoom: номер и пароль — в схеме zoommtg")
    func zoom() {
        let native = app("https://us02web.zoom.us/j/81234567890?pwd=AbC.12_x-Y&uname=spy")
        #expect(native?.url.absoluteString == "zoommtg://us02web.zoom.us/join?action=join&confno=81234567890&pwd=AbC.12_x-Y")
        #expect(native?.requirement.contains("BJ4HAAB9B3") == true)
        #expect(app("https://zoom.us/j/123456789")?.url.absoluteString == "zoommtg://zoom.us/join?action=join&confno=123456789")
    }

    @Test("Zoom: чужой хост и странный пароль — в браузер")
    func zoomRejects() {
        #expect(app("https://zoom.us.example.com/j/81234567890") == nil)
        #expect(app("https://evilzoom.us/j/81234567890") == nil)
        #expect(app("http://zoom.us/j/81234567890") == nil)
        #expect(app("https://zoom.us/j/81234567890?pwd=a%26action%3Dstart") == nil)
        #expect(app("https://zoom.us/my/someone") == nil)
        #expect(app("https://zoom.us/j/12ab") == nil)
    }

    @Test("Teams: та же ссылка в схеме msteams")
    func teams() {
        let text = "https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2/0?context=%7b%22Tid%22%3a%221%22%7d"
        let native = app(text)
        #expect(native?.url.absoluteString == "msteams:/l/meetup-join/19%3ameeting_abc%40thread.v2/0?context=%7b%22Tid%22%3a%221%22%7d")
        #expect(native?.requirement.contains("UBF8T346G9") == true)
        #expect(app("https://teams.microsoft.com.example.com/l/meetup-join/x") == nil)
        #expect(app("https://teams.microsoft.com/l/chat/0/0") == nil)
    }

    @Test("Телемост: как передаёт его сайт — telemost://https//…")
    func telemost() {
        let native = app("https://telemost.yandex.ru/j/6009596680?utm=x")
        #expect(native?.url.absoluteString == "telemost://https//telemost.yandex.ru/j/6009596680")
        #expect(native?.requirement.contains("477EAT77S3") == true)
        #expect(app("https://telemost.360.yandex.ru/j/12345678901234")?.url.absoluteString
                == "telemost://https//telemost.360.yandex.ru/j/12345678901234")
        #expect(app("https://telemost.yandex.ru.example.com/j/6009596680") == nil)
        #expect(app("https://telemost.yandex.ru/j/60095x6680") == nil)
        #expect(app("https://telemost.yandex.ru/some/6009596680") == nil)
    }

    @Test("Остальные сервисы — только браузер")
    func others() {
        #expect(app("https://meet.google.com/abc-defg-hij") == nil)
        #expect(app("https://whereby.com/room") == nil)
    }
}
