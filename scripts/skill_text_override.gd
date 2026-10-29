class_name SkillTextOverride
extends Resource
## A world's own name / description / tip for one skill
## (WorldConfig.skill_text_overrides), e.g. the pressure skills talk about
## oxygen in the Ocean and about cold in the Snow. Empty fields keep the
## skill's own text.

@export var skill_id: String = ""
@export var name_en: String = ""
@export var name_ar: String = ""
@export_multiline var description_en: String = ""
@export_multiline var description_ar: String = ""
@export_multiline var tip_en: String = ""
@export_multiline var tip_ar: String = ""


## field = "name", "description" or "tip". Empty = not overridden.
func get_text(field: String, language: String) -> String:
	var text: String = str(get(field + "_" + language)) if language in UiText.LANGUAGES else ""
	return text if text != "" else str(get(field + "_en"))
