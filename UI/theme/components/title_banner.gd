@tool
extends CenterContainer
class_name TitleBanner

@export var title_text: String = "丛林塔防":
	set(value):
		title_text = value
		_apply_visuals()

@export var title_font_size: int = 46:
	set(value):
		title_font_size = value
		_apply_visuals()

@export var plaque_min_size: Vector2 = Vector2(360, 88):
	set(value):
		plaque_min_size = value
		_apply_visuals()

@onready var _banner_panel: PanelContainer = %BannerPanel
@onready var _title_label: Label = %TitleText


func _ready() -> void:
	_apply_visuals()


func set_title(text: String) -> void:
	title_text = text


func _apply_visuals() -> void:
	if not is_node_ready():
		return
	if _banner_panel:
		_banner_panel.custom_minimum_size = plaque_min_size
	if _title_label:
		_title_label.text = title_text
		if _title_label.label_settings:
			var ls := _title_label.label_settings.duplicate() as LabelSettings
			ls.font_size = title_font_size
			_title_label.label_settings = ls
