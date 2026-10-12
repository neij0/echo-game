class_name LightTextures
extends RefCounted
## Generates grey-box radial textures for PointLight2D (no art files needed).


## Returns a white radial gradient that stays bright until [param hard_edge] (0-1)
## and then fades to transparent at the edge.
static func radial(size: int, hard_edge: float) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, hard_edge, 1.0])
	gradient.colors = PackedColorArray([Color.WHITE, Color.WHITE, Color(0.0, 0.0, 0.0, 0.0)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = size
	texture.height = size
	return texture


## Like radial(), but the fade after hard_edge is a smooth (cubic) curve
## instead of a straight line, so no ring shows where the fade starts.
static func radial_smooth(size: int, hard_edge: float) -> GradientTexture2D:
	var texture: GradientTexture2D = radial(size, hard_edge)
	texture.gradient.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CUBIC
	return texture


## Converts a desired light radius in pixels to a PointLight2D texture_scale.
static func scale_for_radius(texture: Texture2D, radius: float) -> float:
	return radius / (texture.get_width() * 0.5)
