extends SceneTree
## Planche d'images avec légendes (captures avant / après, contrôle d'animations).
## godot --path . --position 6000,3000 -s tools/planche.gd -- <sortie.jpg|png> <colonnes> <largeur_case> <image[=légende]> ...
## (fenêtre hors écran, jamais au premier plan ; la fenêtre prend la taille de la planche)

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var out := a[0]
	var cols := int(a[1])
	var cw := int(a[2])
	var cases: Array = []
	var ch := 0
	for i in range(3, a.size()):
		var parts := a[i].split("=", true, 1)
		var img := Image.load_from_file(parts[0])
		if img == null:
			push_error("image illisible " + parts[0])
			continue
		var h := int(round(float(img.get_height()) * cw / img.get_width()))
		img.resize(cw, h, Image.INTERPOLATE_LANCZOS)
		ch = max(ch, h)
		cases.append([ImageTexture.create_from_image(img), parts[1] if parts.size() > 1 else ""])
	var rows := int(ceil(cases.size() / float(cols)))
	var size := Vector2i(cols * cw + (cols - 1) * 4, rows * ch + (rows - 1) * 4)
	root.size = size
	DisplayServer.window_set_size(size)
	root.transparent_bg = false
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.08, 0.08)
	bg.size = size
	root.add_child(bg)
	for i in cases.size():
		var tr := TextureRect.new()
		tr.texture = cases[i][0]
		tr.position = Vector2((i % cols) * (cw + 4), (i / cols) * (ch + 4))
		root.add_child(tr)
		if cases[i][1] != "":
			var l := Label.new()
			l.text = cases[i][1]
			l.position = tr.position + Vector2(10, ch - max(14, cw / 32) - 18)
			l.add_theme_font_size_override("font_size", max(14, cw / 32))
			l.add_theme_color_override("font_color", Color(1, 0.95, 0.4))
			l.add_theme_color_override("font_outline_color", Color.BLACK)
			l.add_theme_constant_override("outline_size", 5)
			root.add_child(l)
	for k in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var im := root.get_texture().get_image()
	im = im.get_region(Rect2i(Vector2i.ZERO, Vector2i(min(size.x, im.get_width()), min(size.y, im.get_height()))))
	if out.ends_with(".jpg"):
		im.save_jpg(out, 0.88)
	else:
		im.save_png(out)
	print("PLANCHE ", out, " ", im.get_size())
	quit()
