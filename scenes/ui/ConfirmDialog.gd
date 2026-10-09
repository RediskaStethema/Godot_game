class_name ConfirmDialog
extends ModalOverlay

# «Точно?» — вопрос и две кнопки. confirmed — по «да», окно закрывается в обоих случаях.

signal confirmed

func setup(question: String, yes_text: String, no_text: String = "Отмена") -> void:
	build_frame(440.0)
	add_title(question, "HeaderLabel")
	add_button(yes_text, _on_yes, "PrimaryButton")
	add_button(no_text, close)

func _on_yes() -> void:
	emit_signal("confirmed")
	close()
