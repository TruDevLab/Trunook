-- Раскладка окна образа: размер, вид, фон и места значков.
--
--   osascript scripts/dmg-window.applescript "Trunook 0.5.0"
--
-- Всё это хранится в .DS_Store тома, а пишет его только Finder — своего
-- формата у файла нет. Поэтому образ сначала собирается изменяемым (UDRW),
-- монтируется, обставляется здесь и лишь потом сжимается.
--
-- Координаты значков намеренно НЕ привязаны ни к чему на фоне. Finder
-- отсчитывает их от одного края окна, а фон подкладывает от другого: с полосой
-- вкладок значки уезжают вниз на её высоту, и у каждого она своя. Поэтому фон
-- под значками пуст, а ряд стоит с запасом сверху и снизу.

on run argv
	set volumeName to item 1 of argv

	tell application "Finder"
		tell disk volumeName
			open

			set current view of container window to icon view
			set toolbar visible of container window to false
			set statusbar visible of container window to false
			-- Боковая панель сдвинула бы содержимое, и фон уехал бы вбок:
			-- её ширина у каждого своя, а фон рисуется по краю окна.
			set sidebar width of container window to 0
			-- Ширина ровно по фону. Высота — с запасом: полосы вкладок
			-- и состояния съедают её у самого окна, и без запаса нижний край
			-- содержимого оказывался обрезан.
			set the bounds of container window to {220, 120, 880, 600}

			set viewOptions to the icon view options of container window
			set arrangement of viewOptions to not arranged
			set icon size of viewOptions to 96
			set text size of viewOptions to 12
			set background picture of viewOptions to file ".background:background.tiff"

			-- Один ряд, а не два: по высоте ряд занимает втрое больше своего
			-- значка, если считать подпись и разброс из-за полосы вкладок,
			-- и второй ряд в окно уже не помещался.
			set position of item "Trunook.app" to {145, 255}
			set position of item "Applications" to {330, 255}
			set position of item "Как установить.txt" to {515, 255}

			-- Служебные папки видны, когда включён показ скрытых файлов, —
			-- и ложились поверх заголовка. Уводим их ниже окна: у всех
			-- остальных они не видны и так.
			try
				set position of item ".background" to {80, 620}
			end try
			try
				set position of item ".fseventsd" to {240, 620}
			end try

			-- Finder любит вернуть полосу состояния после смены размеров,
			-- поэтому гасим ещё раз — уже по готовому окну.
			set statusbar visible of container window to false
			set toolbar visible of container window to false

			-- Finder сбрасывает .DS_Store не сразу: без обновления и паузы
			-- образ отмонтируется раньше, чем раскладка окажется на диске.
			update without registering applications
			delay 3
			close
		end tell
	end tell
end run
