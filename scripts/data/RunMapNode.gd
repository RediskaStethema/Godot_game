class_name RunMapNode
extends Resource

# Шаг забега: магазин перед волной, бой волны или событие (после некоторых волн). Связи — id следующего шага (RunMapData.nodes[id]).

const BATTLE: String = "battle"   # обычный бой волны
const MINIBOSS: String = "miniboss"  # каждая RunMapData.MINIBOSS_EVERY-я волна: мини-босс + элита
const BOSS: String = "boss"       # последняя волна (главный босс): победа = победа в забеге
const SHOP: String = "shop"       # магазин (ShopScene)
const PICK: String = "pick"       # выбор карты после волны (CardPickScene): 4 рубашкой вверх → 2 вскрыты → 1 в руку
const START_PICK: String = "start_pick"   # старт забега (решение пользователя 17.11.2026, вместо магазина волны 1): 6 карт рубашкой вверх → вслепую берёт 3
const EVENT: String = "event"     # событие (EventScene, RunEvents) — после волн RunMapData.EVENT_AFTER_WAVES

const BATTLE_TYPES: Array[String] = [BATTLE, MINIBOSS, BOSS]

@export var id: int = -1
@export var type: String = BATTLE
@export var wave: int = 0           # номер волны (только у боевых узлов)
@export var next: Array[int] = []   # id узлов, куда можно пойти дальше

static func is_battle_type(t: String) -> bool:
	return t in BATTLE_TYPES

# Шаг выбора карты любого вида (после волны — PICK, старт забега — START_PICK): окно CardPickScene над полем следующего боя
func is_pick() -> bool:
	return type == PICK or type == START_PICK

func is_battle() -> bool:
	return is_battle_type(type)
