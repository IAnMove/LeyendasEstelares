class_name StoryJournal
extends RefCounted

static func open(parent: Control) -> void:
	var modal := Overlay.new()
	modal.add_to_group("dismissible")
	parent.add_child(modal)
	modal.open()
	modal.title(T.t("ui.story.journal"))
	modal.body(T.t("ui.story.pending", {"n": GameState.story_queue.size()}))
	if GameState.journal.is_empty():
		modal.body(T.t("ui.story.empty"))
	for entry in GameState.journal:
		modal.separator()
		modal.title(T.ev(entry["event"], "title"))
		modal.body(T.ev(entry["event"], "c%d.%s" % [entry["choice"], entry["suffix"]]))
	modal.button(T.t("ui.ship.back"), modal.queue_free).grab_focus()
	UITheme.isolate_focus(modal)
