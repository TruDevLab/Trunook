import Foundation

/// Вектор смысла заметки и всё, что с ним делают.
///
/// Смысл — не совпадение слов. Заметка «раскрытие панели по наведению»
/// и заметка «жест на чёлке» об одном, но общих слов у них нет ни одного,
/// и поиск по подстроке их не свяжет никогда. Вектор — это и есть ответ
/// на «о том же ли»: близкие по смыслу тексты дают близкие векторы,
/// а близость двух векторов считается умножением, без единого обращения
/// к модели.
///
/// Поэтому связи и устроены в два шага: вектор считается один раз на заметку
/// и только при её правке, а кандидаты потом отбираются мгновенно.
enum Embedding {
    /// Упаковка для хранения: четыре байта на число, порядок младшим вперёд.
    ///
    /// Хранить вектор строкой из тысячи чисел через запятую было бы вчетверо
    /// дороже и требовало бы разбора при каждом чтении. BLOB читается как
    /// есть.
    static func data(from vector: [Float]) -> Data {
        let bits = vector.map { $0.bitPattern.littleEndian }
        return bits.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    static func vector(from data: Data) -> [Float] {
        let step = MemoryLayout<UInt32>.size
        let count = data.count / step
        guard count > 0 else { return [] }

        var result = [Float]()
        result.reserveCapacity(count)
        for index in 0..<count {
            let start = data.startIndex + index * step
            var bits: UInt32 = 0
            _ = withUnsafeMutableBytes(of: &bits) { raw in
                data.copyBytes(to: raw, from: start..<(start + step))
            }
            result.append(Float(bitPattern: UInt32(littleEndian: bits)))
        }
        return result
    }

    /// Косинусная близость: 1 — об одном и том же, 0 — ни о чём общем.
    ///
    /// Именно косинус, а не расстояние: длина вектора зависит от длины текста,
    /// и по расстоянию короткая заметка оказывалась бы далека от длинной,
    /// даже когда обе про одно.
    ///
    /// Векторы разной длины — это ответы разных моделей. Сравнивать их
    /// бессмысленно, и честный ноль здесь лучше подгонки по длине.
    static func similarity(_ one: [Float], _ other: [Float]) -> Double {
        guard one.count == other.count, !one.isEmpty else { return 0 }

        var dot = 0.0
        var oneLength = 0.0
        var otherLength = 0.0
        for index in 0..<one.count {
            let left = Double(one[index])
            let right = Double(other[index])
            dot += left * right
            oneLength += left * left
            otherLength += right * right
        }
        guard oneLength > 0, otherLength > 0 else { return 0 }
        return dot / (oneLength.squareRoot() * otherLength.squareRoot())
    }

    /// Текст, по которому считается вектор.
    ///
    /// Имя идёт впереди и целиком: оно короткое и почти всегда по делу.
    /// Тело обрезается — у моделей эмбеддингов окно небольшое, а смысл
    /// заметки виден по первым абзацам; хвост длинной заметки лишь размывает
    /// вектор, притягивая её ко всему подряд.
    static let textLimit = 2000

    static func text(for note: Note) -> String {
        let body = note.plain.trimmingCharacters(in: .whitespacesAndNewlines)
        return note.title + "\n" + String(body.prefix(textLimit))
    }
}
