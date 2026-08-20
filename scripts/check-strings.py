#!/usr/bin/env python3
"""Сверяет переводы с тем, что реально вызывается в коде.

    python3 scripts/check-strings.py          # что не переведено, что лишнее
    python3 scripts/check-strings.py --add    # дописать недостающие ключи заглушками

Ключ перевода — сама русская строка из вызова t(…) или tf(…), поэтому
отдельного файла для русского нет: там ключ и есть ответ.

Заглушка — та же русская строка. В интерфейсе это видно сразу, а значит
непереведённое не потеряется молча.
"""

import pathlib
import plistlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCES = ROOT / 'Sources' / 'Trunook'
TABLES = {
    'en': ROOT / 'Resources' / 'en.lproj' / 'Localizable.strings',
    'zh': ROOT / 'Resources' / 'zh-Hans.lproj' / 'Localizable.strings',
}

CALL = re.compile(r'(?<![A-Za-z0-9_.])tf?\("((?:[^"\\]|\\.)*)"')

SWIFT_ESCAPES = {'n': '\n', 't': '\t', '"': '"', '\\': '\\', "'": "'", '0': '\0'}

# Спецификатор формата целиком: позиция, флаги, ширина, точность, длина, вид.
# Сверять надо позицию, длину и вид — ширина с точностью косметические,
# и переводчик вправе их поменять. `%%` — это просто знак процента, аргумента
# за ним нет, поэтому в сравнение он не идёт.
SPECIFIER = re.compile(r'''
    %
    (?:(\d+)\$)?            # позиция: %1$@
    [-+ #0]*                # флаги
    (?:\d+|\*)?             # ширина
    (?:\.(?:\d+|\*))?       # точность
    (hh|h|ll|l|q|L|z|t|j)?  # длина
    ([diouxXeEfgGaAcsp@%])  # вид
''', re.VERBOSE)


def unescape(literal: str) -> str:
    """Строка так, как её увидит Swift: \\n в исходнике — это перевод строки,
    а plutil отдаёт уже разобранное значение. Без этого совпадающие ключи
    выглядят разными."""
    out, index = [], 0
    while index < len(literal):
        char = literal[index]
        if char == '\\' and index + 1 < len(literal):
            out.append(SWIFT_ESCAPES.get(literal[index + 1], literal[index + 1]))
            index += 2
        else:
            out.append(char)
            index += 1
    return ''.join(out)


def keys_in_code() -> list[str]:
    """Порядок сохраняем: так у файлов перевода осмысленные диффы."""
    found, seen = [], set()
    for path in sorted(SOURCES.rglob('*.swift')):
        for line in path.read_text().splitlines():
            if line.strip().startswith('//') or 'DebugLog.write' in line:
                continue
            for match in CALL.finditer(line):
                key = unescape(match.group(1))
                if key not in seen:
                    seen.add(key)
                    found.append(key)
    return found


def specifiers(text: str) -> dict[int, str]:
    """Аргументы строки формата: номер по порядку — вид значения.

    Номер явный, если переводчик расставил позиции (%1$@), иначе — порядковый.
    Поэтому перестановка с позициями считается правильной (переводчику она
    и нужна: в другом языке порядок слов другой), а без позиций — ошибкой,
    какой она и является.
    """
    found, position = {}, 0
    for index, length, kind in SPECIFIER.findall(text):
        if kind == '%':
            continue
        position = int(index) if index else position + 1
        found[position] = (length or '') + kind
    return found


def format_problems(keys: list[str], table: dict[str, str]) -> list[str]:
    """Расхождения между подстановками оригинала и перевода.

    `tf` отдаёт строку в `String(format:)`, а тот читает аргументы по самой
    строке. Перевод, где `%d` превратился в `%@`, прочитает число как ссылку
    на объект — это мусор на экране или падение, и только у того, у кого
    включён этот язык. Полнота перевода такое не ловит: строка на месте.
    """
    problems = []
    for key in keys:
        value = table.get(key)
        if value is None:
            continue
        want, got = specifiers(key), specifiers(value)
        if want != got:
            problems.append(f'    {key!r}\n        нужно {want}, а в переводе {got}: {value!r}')
    return problems


def load(path: pathlib.Path) -> dict[str, str]:
    raw = subprocess.run(
        ['plutil', '-convert', 'xml1', '-o', '-', str(path)],
        capture_output=True, check=True,
    ).stdout
    return plistlib.loads(raw)


def escape(value: str) -> str:
    return value.replace('\\', '\\\\').replace('"', '\\"').replace('\\\\n', '\\n')


def write(path: pathlib.Path, keys: list[str], table: dict[str, str]) -> None:
    lines = ['/* Trunook — перевод интерфейса. Ключ — исходная русская строка. */', '']
    lines += [f'"{escape(k)}" = "{escape(table[k])}";' for k in keys]
    path.write_text('\n'.join(lines) + '\n', encoding='utf-8')


def main() -> int:
    add = '--add' in sys.argv
    keys = keys_in_code()
    problems = 0
    # Считаются отдельно: пропуск перевода `--add` закрывает заглушкой,
    # а расхождение подстановок — нет, его правят руками. Молчать про него
    # из-за того, что заглушки дописаны, нельзя.
    broken_total = 0

    for name, path in TABLES.items():
        table = load(path)
        missing = [k for k in keys if k not in table]
        extra = [k for k in table if k not in keys]

        if missing:
            problems += 1
            print(f'{name}: не переведено — {len(missing)}')
            for key in missing:
                print(f'    {key!r}')
        if extra:
            print(f'{name}: лишнее (в коде больше не встречается) — {len(extra)}')
            for key in extra:
                print(f'    {key!r}')

        broken = format_problems(keys, table)
        if broken:
            broken_total += 1
            print(f'{name}: подстановки не сходятся — {len(broken)}')
            print('\n'.join(broken))

        if add and (missing or extra):
            for key in missing:
                table[key] = key
            write(path, keys, table)
            print(f'{name}: файл переписан, {len(keys)} строк')

    if not problems and not broken_total:
        print(f'переводы полные: {len(keys)} строк, подстановки сходятся')
    return 1 if broken_total or (problems and not add) else 0


sys.exit(main())
