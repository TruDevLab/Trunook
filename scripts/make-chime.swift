#!/usr/bin/env swift
// Рисует сигнал окончания таймера в Resources/chime.wav.
//
// Синтезируется по той же причине, что и мурчание: готового файла взять
// неоткуда, а системные звуки macOS брать по имени нельзя — имя может
// пропасть в следующей версии, и приложение молча онемеет.
//
// Что это за звук и почему такой:
//
//   • один удар, а не трель. Таймер сообщает о факте, а не требует внимания
//     как будильник. Повторяющийся сигнал в вырезе, который человек и так
//     видит глазами, раздражал бы.
//   • колокол, а не синус. Голый тон звучит как ошибка системы. Здесь
//     основной тон и три обертона, каждый со своим временем затухания:
//     высокие гаснут первыми, и получается «дзинь», а не «пи».
//   • обертоны чуть смещены от целых кратностей. У настоящего колокола они
//     не гармоничны, и ровные кратности сразу выдают синтез.
//   • мягкая атака в четыре миллисекунды. Мгновенная даёт щелчок динамика.
//
// Низов нет намеренно: динамики ноутбука ниже сотни герц молчат.
//
//   swift scripts/make-chime.swift     (или make chime)
//   afplay Resources/chime.wav         — послушать

import Foundation

let rate = 44_100.0
/// Полсекунды: достаточно, чтобы звук прочитался как колокольчик,
/// и мало, чтобы не начать мешать.
let seconds = 0.55
let count = Int(rate * seconds)

/// Основной тон. Ля пятой октавы — высоко, чтобы пробиться сквозь музыку,
/// но не пронзительно.
let fundamental = 880.0

/// Обертоны колокола: кратность, громкость и время затухания.
/// Высокие гаснут быстрее — из-за этого удар и «звенит», а не гудит.
let partials: [(ratio: Double, gain: Double, decay: Double)] = [
    (1.00, 1.00, 0.30),
    (2.02, 0.45, 0.18),
    (2.98, 0.22, 0.11),
    (5.41, 0.09, 0.06),
]

/// Мягкая атака: мгновенная даёт щелчок динамика.
let attack = 0.004

var samples = [Double](repeating: 0, count: count)
for index in 0..<count {
    let time = Double(index) / rate
    var value = 0.0
    for partial in partials {
        let envelope = exp(-time / partial.decay)
        value += partial.gain * envelope * sin(2 * .pi * fundamental * partial.ratio * time)
    }
    // Нарастание и общий спад к самому концу, чтобы файл не обрывался щелчком.
    let rise = min(1, time / attack)
    let tail = min(1, (seconds - time) / 0.02)
    samples[index] = value * rise * tail
}

// Приводим к общему потолку: сумма обертонов сама по себе больше единицы.
let peak = samples.map(abs).max() ?? 1
/// Запас до предела. Громкость сигнала задаёт приложение, здесь — форма.
let headroom = 0.85
if peak > 0 {
    for index in samples.indices { samples[index] *= headroom / peak }
}

var pcm = Data(capacity: samples.count * 2)
for sample in samples {
    let clipped = max(-1, min(1, sample))
    let value = Int16(clipped * Double(Int16.max))
    withUnsafeBytes(of: value.littleEndian) { pcm.append(contentsOf: $0) }
}

func chunk(_ name: String) -> Data { Data(name.utf8) }

func littleEndian<T: FixedWidthInteger>(_ value: T) -> Data {
    var little = value.littleEndian
    return withUnsafeBytes(of: &little) { Data($0) }
}

var wav = Data()
wav += chunk("RIFF")
wav += littleEndian(UInt32(36 + pcm.count))
wav += chunk("WAVE")
wav += chunk("fmt ")
wav += littleEndian(UInt32(16))          // размер блока формата
wav += littleEndian(UInt16(1))           // PCM без сжатия
wav += littleEndian(UInt16(1))           // моно
wav += littleEndian(UInt32(rate))
wav += littleEndian(UInt32(rate * 2))    // байт в секунду
wav += littleEndian(UInt16(2))           // байт на кадр
wav += littleEndian(UInt16(16))          // бит на отсчёт
wav += chunk("data")
wav += littleEndian(UInt32(pcm.count))
wav += pcm

let output = URL(fileURLWithPath: "Resources/chime.wav")
do {
    try wav.write(to: output)
    print("сигнал записан: \(output.path), \(String(format: "%.2f", seconds)) с, \(wav.count) байт")
} catch {
    print("не удалось записать \(output.path): \(error.localizedDescription)")
    exit(1)
}
