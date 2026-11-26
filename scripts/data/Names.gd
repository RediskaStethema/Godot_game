class_name Names
extends RefCounted

# Названия для игрока на двух языках (решение пользователя 17.11.2026: «сделай выбор языка»; названия — RENAMING_MAP.txt).
# В данных (CardData.title, UnitData.unit_name, Chapters name, названия синергий) лежат английские названия — это и
# ключи (applied_upgrades, сохранения, тесты), поэтому они не меняются. Игроку название показывают через Names.of(): язык —
# GameSettings.names_language ("ru" — русские из карты, "en" — английские). Названия, которых нет в таблице, не
# переводятся (возвращаются как есть). Новая карта / юнит / здание — строка в RU (тест test_names проверит покрытие).

const LANGUAGES = {"ru": "Русские", "en": "English"}

const RU = {
	# отряды Криспинцев (карта и боец)
	"Crispin Plate": "Латники Криспина", "Crispin Line": "Латники Криспина",
	"Arielite": "Ариэлиты", "Ariel Wing": "Ариэлиты",
	"Nightstrider": "Ночеходы", "Nightstrider Squad": "Ночеходы",
	"Dunsiner": "Дунсинанцы", "Dunsinane Battery": "Дунсинанцы",
	"Virgilian": "Вергилианец", "Virgilian Veteran": "Вергилианец-ветеран",
	"Friar-Leech": "Брат-лекарь", "Armitager": "Армитажец", "Bursak": "Бурсак",
	"Wind Skiff": "Ветровой чёлн", "Shadeking": "Тенекороль", "Monstruwacan": "Монструвакан",
	# особые отряды братств
	"Expounders": "Толкователи", "Hunger Tower Guard": "Стража Голодной башни", "Walking Bastions": "Ходячие бастионы",
	"Erl-Riders": "Ольховая конница", "Devil-Saddlers": "Чёртосёдлы",
	# отряды Кровоподписантов
	"Pallid Masquer": "Бледномасочники", "Pallid Masquers": "Бледномасочники",
	"Bloodsigned": "Кровоподписанты", "Bloodsigned Squad": "Кровоподписанты",
	"Hookwing": "Крюкокрылы", "Hookwings": "Крюкокрылы",
	"Walpurger": "Вальпургиевцы", "Walpurgers": "Вальпургиевцы",
	"Thousand-Young": "Тысячемладые", "Thane": "Таны", "Thanes": "Таны",
	"Heath-King": "Пустошный король", "Signatory Lord": "Владыка-Подписант",
	# особые отряды Внешних
	"Seethers": "Кипенцы", "Goatspawn": "Козлища", "Dustplate": "Прахолаты", "Second Act Chorus": "Хористы Второго акта",
	# здания
	"Petard Tower": "Петардная башня", "Sacrilege Cannon": "Святотатская пушка", "Dunsinane Thunder": "Гром Дунсинана",
	"Phlegethon Mortar": "Флегетонская мортира", "Kuren": "Курень", "Masque Hall": "Маскарадная",
	"Redoubt Wall": "Стена Редута", "Wall of Dis": "Ограда Дита", "Current Well": "Токовый колодец",
	"Altar of the Pact": "Алтарь Договора", "Friar's Cell": "Келья лекаря", "Hali Rift": "Халийская прорубь",
	"Lexicon Bastion": "Бастион Лексикона", "Hunger Tower": "Башня Голода", "Redoubt Pyramid": "Пирамида Редута",
	"Erlthrone": "Ольховый трон", "Vakula's Forge": "Кузня Вакулы", "Seething Font": "Кипящая купель",
	"Thousandfold Cauldron": "Котёл Тысячи", "Herald's Spire": "Шпиль Вестника", "Second Act Theatre": "Театр Второго акта",
	# улучшения и дары
	"Hallowed Plate": "Освящённые латы", "Bloodsigned Plate": "Кровоподписные латы", "Tiger's Action": "Тигриный порыв",
	"The Seethe": "Кипень", "Beatrice's Halo": "Нимб Беатриче", "Yellow Seal": "Жёлтая печать",
	"Friar's Draught": "Зелье лекаря", "Cauldron Brew": "Ведьмино варево", "Crispin's Banner": "Знамя Криспина",
	"Icon of the Act": "Икона Акта",
	"Gift of the Seething": "Дар Кипящего", "Gift of the Grandfather": "Дар Дедушки", "Gift of the Herald": "Дар Вестника",
	"Gift of the King": "Дар Короля", "Recasting": "Пересмена ролей",
	# карты событий
	"Redoubt Relief": "Подмога из Редута", "Masquerade Rising": "Восстание масок",
	"Current Lance from Above": "Копьё Тока с неба", "Hali Surge": "Халийский всплеск",
	# братства и Внешние
	"Lexiconers": "Лексиконцы", "Ugolines": "Уголинцы", "Redoubtmen": "Редутчики", "Alderkin": "Ольховники",
	"Vakulans": "Вакулинцы", "The Seething": "Кипящий", "Grandfather of the Thousand": "Дедушка Тысячи",
	"The Thousand-Faced Herald": "Вестник Тысячи Ликов", "The King of the Second Act": "Король Второго Акта",
	# синергии
	"We Few": "Мы, немногие", "More Light!": "Больше света!", "Thane's Path": "Путь тана", "The Second Act": "Второй акт",
	"Greymoustaches": "Седоусые",
	# финальные боссы
	"Coriol": "Кориол", "Morviy": "Морвий", "Faustin the Crimson": "Фаустин Багряный", "Geryonis": "Герионий",
	"Wilhelm the Lexicarch": "Вильгельм Лексикарх", "Ugolinus the Winged": "Уголиний Крылатый",
	"Götz Ironhand": "Гётц Железнорукий", "The Alder King": "Ольхокороль", "Vakulan the Smith": "Вакулан Кузнец",
}

# Язык названий — GameSettings (автозагрузка): Names вызывают и из скриптов данных, которые компилируются до автолоадов
static func language() -> String:
	var tree := Engine.get_main_loop() as SceneTree
	var settings = tree.root.get_node_or_null("GameSettings") if tree else null
	return str(settings.get("names_language")) if settings and settings.get("names_language") != null else "ru"

# Название для игрока: английское как есть или русское из таблицы (нет в таблице — как есть)
static func of(name: String) -> String:
	if language() == "ru":
		return RU.get(name, name)
	return name
