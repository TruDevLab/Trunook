APP      := Trunook
VERSION := 0.5.0
# Номер сборки растёт со временем: так две сборки одной версии различимы.
BUILDNO  := $(shell date +%y%m%d%H%M)
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

.PHONY: all build bundle install run probe stop clean cert identity dmg icon purr

all: bundle

## Сборка исполняемых файлов
build:
	swift build -c $(CONF) 2>&1 | grep -v "ld: warning: search path" || true

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

## Образ для установки: приложение и ярлык на Программы
dmg: bundle
	@rm -rf $(BUILDDIR)/dmg "$(DMG)"
	@mkdir -p $(BUILDDIR)/dmg
	@cp -R $(BUNDLE) $(BUILDDIR)/dmg/
	@ln -s /Applications $(BUILDDIR)/dmg/Applications
	@# Приложение подписано самодельным сертификатом, поэтому на чужой машине
	@# Gatekeeper его отклоняет. Инструкция по снятию карантина едет в образе.
	@cp Resources/dmg-readme.txt "$(BUILDDIR)/dmg/Как установить.txt"
	@hdiutil create -quiet -volname "$(APP) $(VERSION)" -srcfolder $(BUILDDIR)/dmg \
		-ov -format UDZO "$(DMG)"
	@rm -rf $(BUILDDIR)/dmg
	@echo "образ собран: $(DMG)"

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
