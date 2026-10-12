class_name UiText
extends RefCounted
## Every menu / screen string in English and Arabic. Read through
## Game.text(key) so the current language setting is used. Keys missing from a
## language fall back to English, then to the key itself.

const LANGUAGES: PackedStringArray = ["en", "ar"]

const STRINGS: Dictionary = {
	# Main menu
	"game_title": {"en": "ECHO", "ar": "إيكو"},
	"continue": {"en": "Continue", "ar": "متابعة"},
	"new_game": {"en": "New Game", "ar": "لعبة جديدة"},
	"mode": {"en": "Mode: %s", "ar": "الوضع: %s"},
	"mode_calm": {"en": "Calm", "ar": "هادئ"},
	"mode_challenge": {"en": "Challenge", "ar": "تحدٍّ"},
	"mode_calm_desc": {
		"en": "Both downed: restart the current level. A bit more oxygen.",
		"ar": "إذا سقطتما معاً: تعيدان المستوى الحالي، مع أكسجين أكثر قليلاً.",
	},
	"mode_challenge_desc": {
		"en": "Both downed: restart the current stage from level 1.",
		"ar": "إذا سقطتما معاً: تعيدان المرحلة الحالية من المستوى الأول.",
	},
	"language": {"en": "Language: English", "ar": "اللغة: العربية"},
	"quit": {"en": "Quit", "ar": "خروج"},
	"options": {"en": "Options", "ar": "الإعدادات"},
	"brightness": {"en": "Brightness: %d%%", "ar": "السطوع: %d%%"},
	"brightness_desc": {
		"en": "Changes how much you see close around you. The far darkness, the Echo's light and the pulse are not affected.",
		"ar": "يغيّر ما تريانه حولكما عن قرب فقط. الظلام البعيد وضوء إيكو والنبضة لا تتأثر.",
	},
	"back": {"en": "Back", "ar": "رجوع"},
	"confirm_new_game": {
		"en": "Start a new game? Your saved progress will be lost.",
		"ar": "بدء لعبة جديدة؟ سيُحذف تقدّمك المحفوظ.",
	},
	"yes": {"en": "Yes", "ar": "نعم"},
	"no": {"en": "No", "ar": "لا"},
	"saved_at": {"en": "Saved: %s, stage %d", "ar": "المحفوظ: %s، المرحلة %d"},

	# In-game screens
	"defeat_title": {"en": "Both of you are down", "ar": "سقطتما كلاكما"},
	"cause_creature": {"en": "caught by a creature", "ar": "هجوم مخلوق"},
	"cause_pressure": {"en": "out of %s", "ar": "نفاد %s"},
	"reached": {"en": "Stage %d, level %d / %d", "ar": "المرحلة %d، المستوى %d من %d"},
	"restart_level": {"en": "Restarting level %d...", "ar": "إعادة المستوى %d..."},
	"restart_stage": {"en": "Restarting the stage from level 1...", "ar": "إعادة المرحلة من المستوى 1..."},
	"retry": {"en": "Retry", "ar": "إعادة"},
	"level_cleared": {"en": "Level %d cleared", "ar": "اجتزتما المستوى %d"},
	"going_deeper": {"en": "Going deeper... (level %d / %d)", "ar": "إلى الأعمق... (المستوى %d من %d)"},
	"stage_cleared": {"en": "Stage %d cleared", "ar": "اجتزتما المرحلة %d"},
	"boss_down": {"en": "The great creature has fallen", "ar": "سقط المخلوق العظيم"},
	"stat_time": {"en": "Time: %d:%02d", "ar": "الوقت: %d:%02d"},
	"stat_pulses": {"en": "Pulses used: %d", "ar": "النبضات المستخدمة: %d"},
	"stat_hits": {"en": "Hits taken: %d", "ar": "الضربات المتلقاة: %d"},
	"stat_kills": {"en": "Creatures killed: %d", "ar": "المخلوقات المقتولة: %d"},
	"stat_pressure": {"en": "%s left: %s", "ar": "%s المتبقي: %s"},
	"progress_saved": {"en": "Progress saved", "ar": "تم حفظ التقدّم"},
	"pressure_Oxygen": {"en": "oxygen", "ar": "الأكسجين"},

	# World map
	"world_map": {"en": "World Map", "ar": "خريطة العوالم"},
	"main_menu": {"en": "Main Menu", "ar": "القائمة الرئيسية"},
	"coming_soon": {"en": "%s: coming soon", "ar": "%s: قريباً"},
	"completed": {"en": "Completed", "ar": "مكتمل"},
	"next_world": {"en": "Next", "ar": "التالي"},
	"world_ocean": {"en": "Ocean", "ar": "المحيط"},
	"world_caves": {"en": "Caves", "ar": "الكهوف"},
	"world_forest": {"en": "Forest", "ar": "الغابة"},
	"world_desert": {"en": "Desert", "ar": "الصحراء"},
	"world_snow": {"en": "Snow", "ar": "الثلج"},
}


static func get_text(key: String, language: String) -> String:
	var entry: Dictionary = STRINGS.get(key, {})
	if entry.is_empty():
		return key
	return str(entry.get(language, entry.get("en", key)))
