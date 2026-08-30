import TrunookXPC
import Foundation

/// Куда ставим и можно ли туда ставить.
enum InstallTarget: Equatable {
    case ready(URL)
    case refused(UpdateFailure)
}

/// Подмена работающего приложения новым и перезапуск.
///
/// Само себя приложение подменить не может, поэтому последний шаг делает
/// отдельный процесс: тот, кто зовёт `open`, обязан пережить наш выход.
/// Отдавать ему половину работы, а половину делать самим — значит держать два
/// места, где может сломаться одно.
///
/// Заменить это на `FileManager.replaceItemAt` из самого приложения нельзя
/// ещё и потому, что мы `LSUIElement` с ленивой загрузкой: таблицы перевода,
/// значок, звуки и XPC-служба подтягиваются по адресам внутри бандла уже
/// после запуска. Между подменой и выходом любое из этого прочиталось бы
/// из нового бандла старым кодом.
enum UpdateInstaller {
    /// Решает, годится ли место, откуда мы работаем, для подмены.
    ///
    /// Чистая: ни диска, ни процессов. Ставим туда, откуда работаем,
    /// а не в зашитую `/Applications` — приложение может лежать где угодно.
    static func target(bundleURL: URL, parentIsWritable: Bool) -> InstallTarget {
        let path = bundleURL.path

        // Запущено прямо с образа или из карантина переноса, куда Gatekeeper
        // уносит скачанное. Подменять там нечего: этой копии всё равно не жить.
        if path.contains("/AppTranslocation/")
            || path.hasPrefix("/Volumes/")
            || path.hasPrefix("/private/var/folders/") {
            return .refused(.notInstalled)
        }

        // Пароля не просим никогда. Установщик, работающий от root, — ровно
        // тот механизм, который превращает самоподписанное приложение
        // в лазейку для повышения прав. Отказ понятнее и честнее.
        guard parentIsWritable else { return .refused(.notWritable) }

        return .ready(bundleURL)
    }

    /// Готовит копию рядом с целью и запускает подменщика.
    ///
    /// Возвращает причину отказа или `nil`, если подменщик пошёл. После `nil`
    /// вызывающему остаётся только выйти: дальше работает уже не он.
    static func install(staged: URL, into target: URL) -> UpdateFailure? {
        // Подпись проверяется вплотную перед копированием, без единого шага
        // между. Папка заготовки доступна на запись любому процессу
        // пользователя, и бандл, пролежавший там сутки, — удобное место
        // подложить код, который наш же установщик отнесёт в «Программы»
        // и запустит с нашими разрешениями. Сто миллисекунд закрывают это.
        if case let .rejected(reason) = CodeSignatureCheck.matchesSelf(staged) {
            DebugLog.write("обновление: подпись не сошлась перед самой установкой")
            return reason
        }

        let parent = target.deletingLastPathComponent()
        let pid = ProcessInfo.processInfo.processIdentifier
        // Точка в начале имени прячет заготовку от Finder на ту секунду,
        // что она живёт.
        let prepared = parent.appendingPathComponent(".Trunook-update-\(pid).app")
        let backup = parent.appendingPathComponent(".Trunook-previous-\(pid).app")

        // Копия делается, пока приложение живо, и это и есть настоящая проверка
        // права на запись: предсказание правом не является. Не удалась — ничего
        // не начиналось, приложение работает, сказать можно точно.
        try? FileManager.default.removeItem(at: prepared)
        do {
            try FileManager.default.copyItem(at: staged, to: prepared)
        } catch {
            DebugLog.write("обновление: заготовка не легла рядом с целью — \(error.localizedDescription)")
            return .notWritable
        }

        // Зато теперь оба переименования у подменщика идут по одному тому,
        // то есть это мгновенный `rename(2)`. Перенос через границу тома был бы
        // копированием, во время которого приложения уже нет, и провал там
        // восстановить нечем.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c", script, "trunook-update",
            prepared.path, target.path, backup.path, String(pid)
        ]

        do {
            try process.run()
        } catch {
            DebugLog.write("обновление: подменщик не запустился — \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: prepared)
            return .installFailed
        }

        DebugLog.write("обновление: подменщик пошёл, выходим")
        return nil
    }

    /// Убирает заготовки, оставшиеся после сорвавшейся установки.
    ///
    /// Час — чтобы не тронуть ту, что прямо сейчас в работе.
    static func cleanLeftovers(near target: URL) {
        let parent = target.deletingLastPathComponent()
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: parent, includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []

        for item in contents {
            let name = item.lastPathComponent
            guard name.hasPrefix(".Trunook-update-") || name.hasPrefix(".Trunook-previous-") else { continue }
            let changed = (try? item.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            guard Date().timeIntervalSince(changed) > 3600 else { continue }
            DebugLog.write("обновление: убираем хвост прошлой попытки — \(name)")
            try? FileManager.default.removeItem(at: item)
        }
    }

    /// Тело подменщика.
    ///
    /// Файла на диске нет вовсе: текст уезжает аргументом `/bin/sh -c`. Файл
    /// в `/tmp` можно подменить между записью и запуском, а аргументы уже
    /// запущенного процесса — нельзя.
    ///
    /// Подстановок в тексте тоже нет ни одной: все пути едут позиционными
    /// аргументами и читаются только как `"$1"`, `"$2"` в кавычках. Склеить
    /// путь с текстом значило бы отдать выполнение произвольного кода любому,
    /// кто сумеет назвать папку с `$(…)` внутри.
    ///
    /// Скобки с `&` в конце — чтобы подоболочка осиротела и пережила наш выход.
    /// Журнал обязателен: приложения в этот миг уже нет, и без него любой отказ
    /// выглядел бы как «просто не запустилось».
    private static let script = """
    (
      exec >> "$HOME/Library/Logs/Trunook.log" 2>&1
      echo "[обновление] подменщик начал, цель $2"

      waited=0
      while kill -0 "$4" 2>/dev/null; do
        waited=$((waited + 1))
        if [ "$waited" -gt 100 ]; then
          echo "[обновление] приложение не вышло за десять секунд, ничего не трогаем"
          exit 1
        fi
        sleep 0.1
      done

      pkill -x TrunookHelper 2>/dev/null
      sleep 1

      if ! mv "$2" "$3"; then
        echo "[обновление] старое не сдвинулось, всё осталось на месте"
        exit 1
      fi
      if ! mv "$1" "$2"; then
        echo "[обновление] новое не встало, возвращаем старое"
        mv "$3" "$2"
        exit 1
      fi

      rm -rf "$3"
      xattr -cr "$2" 2>/dev/null
      echo "[обновление] подменено, запускаем"
      /usr/bin/open "$2"

      sleep 3
      pgrep -x Trunook >/dev/null || echo "[обновление] после подмены не запустилось"
    ) &
    """
}
