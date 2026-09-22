#!/bin/bash
# Спросить человека через вырез Trunook — и дождаться ответа.
#
# Кладёт файл-вопрос во входящую папку приложения и, если у вопроса есть
# кнопки, ждёт, пока в файл ответа не ляжет слово нажатой кнопки.
#
# Файл пишется во временный и переносится на место: папка сообщает
# приложению о записи в тот миг, когда её начали, и недописанный файл
# оно прочитать не успеет.
#
# Примеры:
#   scripts/notify.sh "Сборка" "Выкатывать 0.23.0?" build 120
#     → печатает yes или no, код возврата 0 или 1
#   scripts/notify.sh "Сборка" "Готово" check
#     → просто показывает плашку и сразу выходит
#
# Аргументы: кто спрашивает, о чём, значок (bell question build code ai
# check cross warning download message phone), сколько секунд ждать ответа.
# Без четвёртого аргумента кнопок нет — это просто сообщение.

set -euo pipefail

source=${1:?кто спрашивает}
title=${2:?о чём вопрос}
icon=${3:-bell}
wait_seconds=${4:-0}

inbox="$HOME/Library/Application Support/Trunook/inbox"
mkdir -p "$inbox"

id="notify-$$-$(date +%s)"
reply="${TMPDIR:-/tmp}/trunook-$id.reply"
rm -f "$reply"

if [ "$wait_seconds" -gt 0 ]; then
    actions='"actions":[{"id":"yes","title":"Да"},{"id":"no","title":"Нет"}],'
else
    actions=''
fi

tmp="$inbox/.$id.json"
cat > "$tmp" <<EOF
{
  "source": "$source",
  "title": "$title",
  "icon": "$icon",
  $actions
  "reply": "$reply"
}
EOF
mv "$tmp" "$inbox/$id.json"

[ "$wait_seconds" -gt 0 ] || exit 0

# Ждём ответа, проверяя раз в полсекунды. Молчание — это «нет»: не ответив,
# человек ничего не разрешил, и считать иначе опаснее.
waited=0
while [ "$waited" -lt "$((wait_seconds * 2))" ]; do
    if [ -f "$reply" ]; then
        answer=$(tr -d '\n' < "$reply")
        rm -f "$reply"
        echo "$answer"
        [ "$answer" = "yes" ] && exit 0 || exit 1
    fi
    sleep 0.5
    waited=$((waited + 1))
done

echo "timeout"
exit 1
