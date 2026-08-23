APP      := Trunook
VERSION := 0.8.0
# Номер сборки растёт со временем: так две сборки одной версии различимы.
BUILDNO  := $(shell date +%y%m%d%H%M)
# Провал сборки в конвейере с grep иначе теряется: make видит код последней
# команды, а `bundle` следом спокойно раскладывает и подписывает прежний
# бинарник — в бандл уезжает сборка, которой уже не соответствует исходник.
#
# `.SHELLFLAGS := -o pipefail -c` сюда просится, но не работает: в macOS
# лежит GNU Make 3.81, а эта переменная появилась в 3.82 — она молча
# игнорируется, и проверка проходит впустую. Поэтому `pipefail` включается
# прямо в рецепте, а оболочка задаётся явно: `SHELL` версия 3.81 понимает.
SHELL := /bin/bash
# Отладочная — для работы: пересборка занимает секунды вместо полуминуты.
# В образ едет release, и `dmg` добивается этого сам, не полагаясь на то,
# что кто-то вспомнит про переменную.
CONF     ?= debug
IDENTITY ?= Trunook Dev Signing
DEST     ?= /Applications
# Бандл собираем вне папки проекта: на Desktop файлы обрастают
# расширенными атрибутами, а codesign считает их посторонним мусором.
BUILDDIR := $(HOME)/Library/Caches/TrunookBuild
BUNDLE   := $(BUILDDIR)/$(APP).app
DMG      := $(CURDIR)/$(APP)-$(VERSION).dmg
HELPER   := $(BUNDLE)/Contents/XPCServices/TrunookHelper.xpc
BIN       = $(shell swift build -c $(CONF) --show-bin-path 2>/dev/null)

.PHONY: all build bundle install run probe stop clean cert identity dmg icon purr chime demo

all: bundle

## Сборка исполняемых файлов
##
## Фильтр в скобках, а не через `|| true` на весь конвейер: `grep -v`
## возвращает единицу, когда отфильтровал всё, и хвост глушил бы вместе
## с этим и настоящий провал сборки. Скобки гасят только код grep,
## а `pipefail` доносит до make код самого swift.
build:
	set -o pipefail; swift build -c $(CONF) 2>&1 | { grep -v "ld: warning: search path" || true; }

## Раскладка и подпись .app
bundle: build
	@rm -rf $(BUNDLE)
	@mkdir -p $(BUILDDIR)
	@mkdir -p $(BUNDLE)/Contents/MacOS $(BUNDLE)/Contents/Resources
	@mkdir -p $(HELPER)/Contents/MacOS
	@cp "$(BIN)/$(APP)" $(BUNDLE)/Contents/MacOS/$(APP)
	@cp Resources/Info.plist $(BUNDLE)/Contents/Info.plist
	@cp Resources/Trunook.icns $(BUNDLE)/Contents/Resources/Trunook.icns
	@cp Resources/purr.wav $(BUNDLE)/Contents/Resources/purr.wav
	@cp Resources/chime.wav $(BUNDLE)/Contents/Resources/chime.wav
	@cp -R Resources/en.lproj Resources/zh-Hans.lproj $(BUNDLE)/Contents/Resources/
	@/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(VERSION)" \
		$(BUNDLE)/Contents/Info.plist
	@/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(BUILDNO)" \
		$(BUNDLE)/Contents/Info.plist
	@printf 'APPL????' > $(BUNDLE)/Contents/PkgInfo
	@cp "$(BIN)/TrunookHelper" $(HELPER)/Contents/MacOS/TrunookHelper
	@cp Helper/Info.plist $(HELPER)/Contents/Info.plist
	@# macOS вешает на скопированные бинарники xattr (provenance, quarantine),
	@# а codesign считает их посторонним мусором в бандле.
	@xattr -cr $(BUNDLE)
	@# Вложенный код подписывается первым, иначе внешняя подпись не сойдётся.
	@codesign --force --sign "$(IDENTITY)" --timestamp=none $(HELPER)
	@codesign --force --sign "$(IDENTITY)" --timestamp=none \
		--entitlements Resources/Trunook.entitlements $(BUNDLE)
	@codesign --verify --deep --strict $(BUNDLE) && echo "подписано: $(BUNDLE)"

## Установка в /Applications. Разрешения TCC привязаны к подписи,
## поэтому при неизменном сертификате они переживают пересборку.
install: bundle
	@$(MAKE) --no-print-directory stop
	@# Launch Services не успевает заметить подмену бандла, если открыть
	@# приложение сразу после снятия предыдущего экземпляра.
	@sleep 1
	@rm -rf "$(DEST)/$(APP).app"
	@cp -R $(BUNDLE) "$(DEST)/$(APP).app"
	@echo "установлено: $(DEST)/$(APP).app"

run: install
	@open "$(DEST)/$(APP).app"

stop:
	@pkill -x $(APP) 2>/dev/null; pkill -x TrunookHelper 2>/dev/null; true

## Спайк MediaRemote: запускает хелпер напрямую из бандла .xpc,
## чтобы он получил подменённый bundle id.
probe: bundle
	@$(HELPER)/Contents/MacOS/TrunookHelper --probe

## Образ для установки: приложение, ярлык на Программы и обставленное окно
##
## Собирается в два захода: сначала изменяемый образ, который монтируется
## и обставляется через Finder, потом сжатый. Иначе никак — раскладка окна
## живёт в .DS_Store, а пишет его только Finder.
VOLUME := $(APP) $(VERSION)
RWDMG  := $(BUILDDIR)/$(APP)-rw.dmg

## Конфигурация задаётся здесь, а не наследуется от умолчания: образ уезжает
## к людям, и сборка без оптимизации в нём — не мелочь. Подпись и разрешения
## смену конфигурации переживают: сертификат самоподписанный, требование
## к подписи не содержит хеша кода, и TCC держится за него, а не за бинарник.
dmg:
	@$(MAKE) --no-print-directory bundle CONF=release
	@# Оставшийся с прошлого неудачного захода том иначе примонтируется
	@# вторым, под именем с единицей на конце, и обставится не он.
	@hdiutil detach -quiet "/Volumes/$(VOLUME)" 2>/dev/null || true
	@rm -rf $(BUILDDIR)/dmg "$(DMG)" "$(RWDMG)"
	@mkdir -p $(BUILDDIR)/dmg/.background
	@cp -R $(BUNDLE) $(BUILDDIR)/dmg/
	@ln -s /Applications $(BUILDDIR)/dmg/Applications
	@# Приложение подписано самодельным сертификатом, поэтому на чужой машине
	@# Gatekeeper его отклоняет. Инструкция по снятию карантина едет в образе.
	@cp Resources/dmg-readme.txt "$(BUILDDIR)/dmg/Как установить.txt"
	@# Пустой .fseventsd с меткой no_log: иначе система заводит его сама
	@# при монтировании, и он остаётся в образе лишней видимой папкой.
	@mkdir -p $(BUILDDIR)/dmg/.fseventsd
	@touch $(BUILDDIR)/dmg/.fseventsd/no_log
	@# Фон рисуется кодом и сшивается в один tiff: Finder сам берёт из него
	@# нужное разрешение, и на ретине картинка не мылится.
	@swift scripts/make-dmg-background.swift $(VERSION)
	@tiffutil -cathidpicheck build/dmg-background.png build/dmg-background@2x.png \
		-out $(BUILDDIR)/dmg/.background/background.tiff >/dev/null
	@hdiutil create -quiet -volname "$(VOLUME)" -srcfolder $(BUILDDIR)/dmg \
		-fs HFS+ -format UDRW -ov "$(RWDMG)"
	@hdiutil attach -quiet -noverify -noautoopen "$(RWDMG)"
	@osascript scripts/dmg-window.applescript "$(VOLUME)"
	@sync
	@hdiutil detach -quiet "/Volumes/$(VOLUME)"
	@hdiutil convert -quiet "$(RWDMG)" -format UDZO -imagekey zlib-level=9 -o "$(DMG)"
	@rm -rf $(BUILDDIR)/dmg "$(RWDMG)"
	@echo "образ собран: $(DMG)"
	@shasum -a 256 "$(DMG)"

## Перерисовать иконку приложения
icon:
	@mkdir -p build
	@swift scripts/make-icon.swift
	@iconutil -c icns build/Trunook.iconset -o Resources/Trunook.icns
	@rm -rf build/Trunook.iconset
	@echo "иконка обновлена"

## Пересобрать звук мурчания
purr:
	@swift scripts/make-purr.swift

## Пересобрать сигнал окончания таймера
chime:
	@swift scripts/make-chime.swift

## Собрать docs/demo.gif из снятых кадров.
## Кадры снимает само приложение — см. заголовок скрипта.
demo:
	@swift scripts/make-demo-gif.swift

## Разовое создание самоподписанного сертификата
cert:
	@./scripts/make-cert.sh

identity:
	@security find-identity -v -p codesigning

clean:
	@rm -rf $(BUILDDIR) .build

# Тесты собираются вне папки проекта по той же причине, что и бандл:
# на файлах внутри ~/Desktop заводятся расширенные атрибуты, и codesign
# считает их посторонним мусором.
TEST_BUILD := $(HOME)/Library/Caches/TrunookTests

.PHONY: test
test:
	swift test --scratch-path $(TEST_BUILD)
