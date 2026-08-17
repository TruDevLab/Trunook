#!/usr/bin/env swift
// Рисует звук мурчания в Resources/purr.wav.
//
// Готового файла взять неоткуда, а записывать кота негде — поэтому звук
// синтезируется. Кошка издаёт не тон, а частые толчки, около двадцати пяти
// в секунду; каждый толчок — короткий всплеск шума. Из них и складывается
// «ррр».
//
// Что отличает живое мурчание от ровного жужжания, и что здесь поэтому есть:
//
//   • резонансы. Голая полоса шума звучит как помеха. Всплеск прогоняется
//     через два резонансных фильтра — примерно 240 и 520 Гц; они и дают
//     то самое горловое «р».
//   • неровность. У живого кота ни один толчок не повторяет предыдущий:
//     период гуляет процентов на шесть, громкость — на двадцать. Ровный
//     период немедленно выдаёт машину.
//   • просвет между толчками. Спад короче периода, поэтому слышен не гул,
//     а трещотка.
//   • дыхание. Громкость и частота медленно плывут: на вдохе мурчание
//     чуть тише и чуть быстрее.
//
// Низов в файле намеренно нет: динамики ноутбука ниже сотни герц молчат,
// и вся слышимая часть живёт в полосе 150–700 Гц.
//
//   swift scripts/make-purr.swift      (или make purr)
//   afplay Resources/purr.wav          — послушать

import Foundation

let rate = 44_100.0
/// Длина петли и склейка. Склейка позволяет не подгонять длину под целое
/// число толчков — а без неё неровный период был бы невозможен.
let loopSeconds = 5.0
let blendSeconds = 0.30

let loopCount = Int(rate * loopSeconds)
let blendCount = Int(rate * blendSeconds)

// MARK: - Источник шума

/// Свой генератор, а не системный: файл должен получаться одинаковым
/// при каждом запуске, иначе неясно, менялось ли звучание.
struct Noise {
    private var state: UInt64 = 0x9E37_79B9_7F4A_7C15

    mutating func unit() -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(state >> 11) / Double(1 << 53)
    }

    mutating func bipolar() -> Double { unit() * 2 - 1 }
}

// MARK: - Резонатор

/// Полосовой фильтр Чемберлина. Нужен именно резонансный: он подчёркивает
/// узкую полосу вокруг своей частоты, а от этого шум перестаёт быть шумом
/// и приобретает голос.
struct Resonator {
    let f: Double
    let q: Double
    private var low = 0.0
    private var band = 0.0

    init(hertz: Double, quality: Double) {
        f = 2 * sin(.pi * hertz / rate)
        q = 1 / quality
    }

    mutating func process(_ input: Double) -> Double {
        let high = input - low - q * band
        band += f * high
        low += f * band
        return band
    }
}

// MARK: - Синтез

var noise = Noise()
var throat = Resonator(hertz: 238, quality: 3.6)
var mouth = Resonator(hertz: 524, quality: 2.4)

/// Состояние текущего толчка.
var phase = 1.0          // ≥ 1 — значит на первом же отсчёте начнётся толчок
var pulseGain = 1.0
var pulseStretch = 1.0
var pulseDecay = 0.012

let total = loopCount + blendCount
var samples = [Double](repeating: 0, count: total)

for index in 0..<total {
    let time = Double(index) / rate
    // Дыхание завершает ровно один круг за петлю — на склейке уровень
    // совпадает сам собой.
    let breath = 2 * Double.pi * time / loopSeconds
    let loudness = 0.72 + 0.28 * sin(breath)
    let baseRate = 25.5 + 2.5 * sin(breath + 1.2)

    let pulseRate = baseRate * pulseStretch
    phase += pulseRate / rate
    if phase >= 1 {
        phase -= 1
        // Новый толчок: своя громкость, своя длина, свой спад.
        pulseGain = 0.82 + 0.36 * noise.unit()
        pulseStretch = 0.94 + 0.12 * noise.unit()
        pulseDecay = 0.009 + 0.006 * noise.unit()
    }

    // Время от начала толчка. Резкая атака, экспоненциальный спад —
    // спад короче периода, поэтому между толчками остаётся просвет.
    let elapsed = phase / pulseRate
    let attack = 0.0022
    let envelope: Double
    if elapsed < attack {
        envelope = elapsed / attack
    } else {
        envelope = exp(-(elapsed - attack) / pulseDecay)
    }

    let excitation = noise.bipolar() * envelope * pulseGain
    let voice = throat.process(excitation) + 0.45 * mouth.process(excitation)

    samples[index] = voice * loudness
}

// MARK: - Склейка петли

/// Хвост подмешивается к началу по равной мощности: у шума концы никогда
/// не сойдутся сами, а на склейке был бы слышен щелчок.
for index in 0..<blendCount {
    let position = Double(index) / Double(blendCount)
    let head = sin(position * .pi / 2)
    let tail = cos(position * .pi / 2)
    samples[index] = samples[index] * head + samples[loopCount + index] * tail
}
samples.removeLast(blendCount)

// MARK: - Запись

let peak = samples.map(abs).max() ?? 1
let scale = peak > 0 ? 0.8 / peak : 1

var pcm = Data(capacity: samples.count * 2)
for value in samples {
    let clamped = max(-1, min(1, value * scale))
    var sample = Int16(clamped * 32_767)
    withUnsafeBytes(of: &sample) { pcm.append(contentsOf: $0) }
}

func chunk(_ tag: String) -> Data { Data(tag.utf8) }

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

let output = URL(fileURLWithPath: "Resources/purr.wav")
do {
    try wav.write(to: output)
    let seconds = String(format: "%.2f", Double(samples.count) / rate)
    print("мурчание записано: \(output.path), \(seconds) с, \(wav.count) байт")
} catch {
    print("не удалось записать \(output.path): \(error.localizedDescription)")
    exit(1)
}
