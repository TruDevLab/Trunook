#!/usr/bin/env swift
// Рисует щелчок деления шкалы таймера в Resources/tick.wav.
//
// Синтезируется по той же причине, что мурчание и сигнал: системные звуки
// macOS берутся по имени, а имя может пропасть в следующей версии — и щелчок
// молча онемеет.
//
// Что это за звук и почему такой:
//
//   • очень короткий, двенадцать миллисекунд. Шкалу тянут через десятки
//     делений подряд, и звук длиннее сразу превращается в кашу: следующий
//     щелчок начинается раньше, чем догорел предыдущий.
//   • шум, а не тон. Тон на такой длине читается как «пи» и на каждом
//     делении складывается в мелодию. Щелчок настоящего колёсика — это
//     удар, у него нет высоты.
//   • шум полосовой, а не белый. Голый белый шум звучит как помеха; здесь
//     он пропущен через резонанс на двух килогерцах — получается сухой
//     щелчок, а не шипение.
//   • атака мгновенная, спад за шесть миллисекунд. Мягкая атака у щелчка
//     съедает как раз то, ради чего он нужен.
//
// Громкость задаёт приложение (`TickPlayer`), здесь — форма.
//
//   swift scripts/make-tick.swift      (или make tick)
//   afplay Resources/tick.wav          — послушать

import Foundation

let rate = 44_100.0
/// Двенадцать миллисекунд. Больше — и щелчки при быстром вращении наезжают
/// друг на друга.
let seconds = 0.012
let count = Int(rate * seconds)

/// Середина полосы. Две тысячи герц — там, где щелчок слышен на динамиках
/// ноутбука и не спорит с музыкой.
let center = 2_000.0
/// Насколько узка полоса. Уже — ближе к тону, шире — ближе к шипению.
let resonance = 2.2

/// Шум берётся из своего генератора с постоянным зерном, а не из `random`:
/// файл должен получаться одинаковым при каждой пересборке, иначе звук
/// приложения незаметно меняется от сборки к сборке.
var seed: UInt64 = 0x5DEE_CE66
func noise() -> Double {
    seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
    return Double(Int64(bitPattern: seed >> 11)) / Double(1 << 52) - 1
}

// Резонансный фильтр второго порядка: два прошлых отсчёта на выходе задают
// колебание, вход подмешивает в него шум.
let omega = 2 * .pi * center / rate
let decayPerSample = exp(-omega / (2 * resonance))
let a1 = 2 * decayPerSample * cos(omega)
let a2 = -decayPerSample * decayPerSample

var previous = 0.0
var beforePrevious = 0.0
var samples = [Double](repeating: 0, count: count)
for index in 0..<count {
    let time = Double(index) / rate
    // Возбуждение живёт первую миллисекунду: дальше фильтр звенит сам.
    let excitation = time < 0.001 ? noise() : 0
    let value = excitation + a1 * previous + a2 * beforePrevious
    beforePrevious = previous
    previous = value
    // Спад за шесть миллисекунд плюс срез к самому концу файла, чтобы
    // он не обрывался вторым щелчком.
    let envelope = exp(-time / 0.006) * min(1, (seconds - time) / 0.002)
    samples[index] = value * envelope
}

let peak = samples.map(abs).max() ?? 1
/// Запас до предела. Щелчок и должен быть тише сигнала окончания.
let headroom = 0.7
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

let output = URL(fileURLWithPath: "Resources/tick.wav")
do {
    try wav.write(to: output)
    print("щелчок записан: \(output.path), \(String(format: "%.3f", seconds)) с, \(wav.count) байт")
} catch {
    print("не удалось записать \(output.path): \(error.localizedDescription)")
    exit(1)
}
