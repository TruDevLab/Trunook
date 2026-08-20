import Foundation
import Testing
@testable import Trunook

@Suite("Город для погоды")
struct WeatherPlaceTests {
    private func data(_ json: String) -> Data { Data(json.utf8) }

    @Test("Город разбирается целиком")
    func городРазбирается() throws {
        let found = WeatherPlaceSearch.parse(data("""
        {"results":[{"name":"Москва","latitude":55.75222,"longitude":37.61556,
                     "country":"Россия","admin1":"Москва"}]}
        """))
        let place = try #require(found.first)
        #expect(place.name == "Москва")
        #expect(place.title == "Москва, Москва, Россия")
        #expect(place.latitude == 55.75222)
    }

    /// У мелких мест сервис не заполняет ни область, ни страну. Название
    /// без них — всё ещё название, а не повод выбросить строку.
    @Test("Место без области и страны остаётся в списке")
    func безОбласти() throws {
        let found = WeatherPlaceSearch.parse(data("""
        {"results":[{"name":"Пустошка","latitude":56.3,"longitude":29.36}]}
        """))
        let place = try #require(found.first)
        #expect(place.region == nil)
        #expect(place.title == "Пустошка")
    }

    /// Тёзки — главная причина, по которой выбор сохраняется вместе
    /// с координатами: по одному названию их не различить.
    @Test("Тёзки различаются и не схлопываются")
    func тёзкиРазличаются() {
        let found = WeatherPlaceSearch.parse(data("""
        {"results":[
          {"name":"Ростов","latitude":57.18,"longitude":39.41,"country":"Россия","admin1":"Ярославская область"},
          {"name":"Ростов","latitude":47.23,"longitude":39.71,"country":"Россия","admin1":"Ростовская область"}
        ]}
        """))
        #expect(found.count == 2)
        #expect(found[0].id != found[1].id)
        #expect(found[0].title != found[1].title)
    }

    @Test("Строка без координат отбрасывается")
    func безКоординат() {
        let found = WeatherPlaceSearch.parse(data("""
        {"results":[{"name":"Ниоткуда","country":"Россия"},
                    {"name":"Тверь","latitude":56.86,"longitude":35.9}]}
        """))
        #expect(found.map(\.name) == ["Тверь"])
    }

    @Test("Пустой и негодный ответ не роняют поиск")
    func негодныйОтвет() {
        #expect(WeatherPlaceSearch.parse(data("{}")).isEmpty)
        #expect(WeatherPlaceSearch.parse(data("{\"results\":[]}")).isEmpty)
        #expect(WeatherPlaceSearch.parse(data("не json вовсе")).isEmpty)
    }

    /// Выбор переживает запись в настройки: координаты хранятся вместе
    /// с названием, иначе повторный поиск однажды выбрал бы другого тёзку.
    @Test("Город переживает запись и чтение")
    func кодирование() throws {
        let place = WeatherPlace(name: "Ростов", region: "Ярославская область, Россия",
                                 latitude: 57.18, longitude: 39.41)
        let restored = try JSONDecoder().decode(
            WeatherPlace.self, from: JSONEncoder().encode(place)
        )
        #expect(restored == place)
    }
}
