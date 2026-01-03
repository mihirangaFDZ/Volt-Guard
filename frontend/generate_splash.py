from PIL import Image, ImageDraw
import os


def create_vertical_gradient(width, height, top, bottom):
    img = Image.new('RGB', (width, height), bottom)
    draw = ImageDraw.Draw(img)
    for y in range(height):
        t = y / max(1, height - 1)
        r = int(top[0] * (1 - t) + bottom[0] * t)
        g = int(top[1] * (1 - t) + bottom[1] * t)
        b = int(top[2] * (1 - t) + bottom[2] * t)
        draw.line([(0, y), (width, y)], fill=(r, g, b))
    return img


width = 1242
height = 2208

# Eco dark background like the app's startup
img = create_vertical_gradient(width, height, top=(20, 66, 47), bottom=(13, 26, 20))
draw = ImageDraw.Draw(img)

cx, cy = width // 2, height // 2

# Logo container circle
logo_radius = 220
draw.ellipse(
    [cx - logo_radius, cy - logo_radius - 120, cx + logo_radius, cy + logo_radius - 120],
    fill=(255, 255, 255),
)

# Inner circle background
inner_radius = 200
draw.ellipse(
    [cx - inner_radius, cy - inner_radius - 120, cx + inner_radius, cy + inner_radius - 120],
    fill=(13, 26, 20),
)

# Leaf (simplified)
leaf_color = (0, 200, 83)
leaf_hi = (150, 255, 198)
leaf_w = 260
leaf_h = 320
leaf_cx = cx + 10
leaf_cy = cy - 120

draw.ellipse(
    [
        leaf_cx - leaf_w // 2,
        leaf_cy - leaf_h // 2,
        leaf_cx + leaf_w // 2,
        leaf_cy + leaf_h // 2,
    ],
    fill=leaf_color,
)
draw.ellipse(
    [
        leaf_cx - int(leaf_w * 0.55),
        leaf_cy - int(leaf_h * 0.40),
        leaf_cx + int(leaf_w * 0.55),
        leaf_cy + int(leaf_h * 0.30),
    ],
    fill=(13, 26, 20),
)
draw.ellipse(
    [
        leaf_cx - int(leaf_w * 0.30),
        leaf_cy - int(leaf_h * 0.28),
        leaf_cx - int(leaf_w * 0.05),
        leaf_cy + int(leaf_h * 0.18),
    ],
    fill=leaf_hi,
)

# Stem
draw.rounded_rectangle(
    [leaf_cx - 8, leaf_cy + 95, leaf_cx + 8, leaf_cy + 165],
    radius=8,
    fill=(0, 140, 60),
)

# Bolt
bolt = [
    (cx + 10, cy - 300),
    (cx - 60, cy - 120),
    (cx - 5, cy - 120),
    (cx - 40, cy + 70),
    (cx + 110, cy - 110),
    (cx + 45, cy - 110),
    (cx + 85, cy - 300),
]
draw.polygon(bolt, fill=(251, 191, 36), outline=(217, 119, 6), width=6)

# App name text as simple vector-like bars (no fonts dependency)
title_y = cy + 190
bar_w = 480
bar_h = 10
draw.rounded_rectangle(
    [cx - bar_w // 2, title_y, cx + bar_w // 2, title_y + bar_h],
    radius=6,
    fill=(255, 255, 255),
)
draw.rounded_rectangle(
    [cx - 320, title_y + 28, cx + 320, title_y + 28 + 8],
    radius=6,
    fill=(224, 231, 255),
)

output_path = os.path.join('assets', 'images', 'splash.png')
img.save(output_path, 'PNG', quality=100)
print(f"✓ Splash screen created successfully at {output_path}")
print(f"  Size: {width}x{height}px")
print("  Theme: leaf + bolt (energy saving)")
