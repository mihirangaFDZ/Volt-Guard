from PIL import Image, ImageDraw
import os


def create_radial_gradient(size, inner_color, outer_color):
    """Create a simple radial gradient by drawing concentric circles."""
    img = Image.new('RGB', (size, size), outer_color)
    draw = ImageDraw.Draw(img)
    steps = 140
    for i in range(steps, 0, -1):
        t = i / steps
        r = int(inner_color[0] * t + outer_color[0] * (1 - t))
        g = int(inner_color[1] * t + outer_color[1] * (1 - t))
        b = int(inner_color[2] * t + outer_color[2] * (1 - t))
        radius = int((size / 2) * t)
        x0 = size // 2 - radius
        y0 = size // 2 - radius
        x1 = size // 2 + radius
        y1 = size // 2 + radius
        draw.ellipse([x0, y0, x1, y1], fill=(r, g, b))
    return img


size = 1024

# Eco-themed background (dark green with subtle radial highlight)
bg = create_radial_gradient(size, inner_color=(20, 66, 47), outer_color=(13, 26, 20))

# Circular mask for a clean app icon silhouette
mask = Image.new('L', (size, size), 0)
mask_draw = ImageDraw.Draw(mask)
mask_draw.ellipse([0, 0, size, size], fill=255)
img = Image.composite(bg, Image.new('RGB', (size, size), (13, 26, 20)), mask)
draw = ImageDraw.Draw(img)

# Soft ring to add depth
ring_margin = 70
draw.ellipse(
    [ring_margin, ring_margin, size - ring_margin, size - ring_margin],
    outline=(255, 255, 255),
    width=8,
)

# Leaf shape (simple stylized leaf using two overlapping ellipses + stem)
leaf_center_x = 520
leaf_center_y = 520
leaf_w = 520
leaf_h = 620
leaf_color = (0, 200, 83)  # existing app green
leaf_highlight = (150, 255, 198)

# Main leaf body
draw.ellipse(
    [
        leaf_center_x - leaf_w // 2,
        leaf_center_y - leaf_h // 2,
        leaf_center_x + leaf_w // 2,
        leaf_center_y + leaf_h // 2,
    ],
    fill=leaf_color,
)

# Cutout to form a pointed leaf tip (overlay background-colored ellipse)
draw.ellipse(
    [
        leaf_center_x - int(leaf_w * 0.56),
        leaf_center_y - int(leaf_h * 0.44),
        leaf_center_x + int(leaf_w * 0.56),
        leaf_center_y + int(leaf_h * 0.32),
    ],
    fill=(13, 26, 20),
)

# Leaf highlight
draw.ellipse(
    [
        leaf_center_x - int(leaf_w * 0.28),
        leaf_center_y - int(leaf_h * 0.28),
        leaf_center_x + int(leaf_w * 0.10),
        leaf_center_y + int(leaf_h * 0.18),
    ],
    fill=leaf_highlight,
)

# Stem
stem_w = 26
stem_h = 200
draw.rounded_rectangle(
    [
        leaf_center_x - stem_w // 2,
        leaf_center_y + int(leaf_h * 0.12),
        leaf_center_x + stem_w // 2,
        leaf_center_y + int(leaf_h * 0.12) + stem_h,
    ],
    radius=14,
    fill=(0, 140, 60),
)

# Bolt overlay (energy) - centered and slightly tilted look via polygon
bolt = [
    (520, 260),
    (420, 520),
    (505, 520),
    (455, 790),
    (660, 500),
    (555, 500),
    (610, 260),
]
draw.polygon(bolt, fill=(251, 191, 36), outline=(217, 119, 6), width=10)

# Bolt highlight
bolt_hi = [
    (535, 285),
    (452, 518),
    (520, 518),
    (485, 725),
    (620, 505),
    (565, 505),
    (610, 285),
]
draw.polygon(bolt_hi, fill=(253, 230, 138))

# Save
output_path = os.path.join('assets', 'images', 'icon.png')
os.makedirs(os.path.dirname(output_path), exist_ok=True)
img.save(output_path, 'PNG', quality=100)
print(f"✓ Icon created successfully at {output_path}")
print(f"  Size: {size}x{size}px")
print("  Theme: leaf + bolt (energy saving)")


# Also create an Android adaptive foreground (transparent background, safe area)
fg = Image.new('RGBA', (size, size), (0, 0, 0, 0))
fg_draw = ImageDraw.Draw(fg)

# Android adaptive icons have a "safe zone"; keep artwork centered with padding
safe = 720
offset = (size - safe) // 2

def map_point(x, y):
    sx = offset + int(x * safe / size)
    sy = offset + int(y * safe / size)
    return sx, sy

# Re-draw the leaf + bolt centered, but without any background
leaf_center_x, leaf_center_y = map_point(520, 520)
leaf_w = int(520 * safe / size)
leaf_h = int(620 * safe / size)
leaf_color = (0, 200, 83, 255)
leaf_highlight = (150, 255, 198, 255)

fg_draw.ellipse(
    [
        leaf_center_x - leaf_w // 2,
        leaf_center_y - leaf_h // 2,
        leaf_center_x + leaf_w // 2,
        leaf_center_y + leaf_h // 2,
    ],
    fill=leaf_color,
)
fg_draw.ellipse(
    [
        leaf_center_x - int(leaf_w * 0.56),
        leaf_center_y - int(leaf_h * 0.44),
        leaf_center_x + int(leaf_w * 0.56),
        leaf_center_y + int(leaf_h * 0.32),
    ],
    fill=(0, 0, 0, 0),
)
fg_draw.ellipse(
    [
        leaf_center_x - int(leaf_w * 0.28),
        leaf_center_y - int(leaf_h * 0.28),
        leaf_center_x + int(leaf_w * 0.10),
        leaf_center_y + int(leaf_h * 0.18),
    ],
    fill=leaf_highlight,
)

stem_w = max(10, int(26 * safe / size))
stem_h = int(200 * safe / size)
fg_draw.rounded_rectangle(
    [
        leaf_center_x - stem_w // 2,
        leaf_center_y + int(leaf_h * 0.12),
        leaf_center_x + stem_w // 2,
        leaf_center_y + int(leaf_h * 0.12) + stem_h,
    ],
    radius=max(8, stem_w // 2),
    fill=(0, 140, 60, 255),
)

bolt = [
    map_point(520, 260),
    map_point(420, 520),
    map_point(505, 520),
    map_point(455, 790),
    map_point(660, 500),
    map_point(555, 500),
    map_point(610, 260),
]
fg_draw.polygon(bolt, fill=(251, 191, 36, 255), outline=(217, 119, 6, 255), width=max(6, int(10 * safe / size)))

bolt_hi = [
    map_point(535, 285),
    map_point(452, 518),
    map_point(520, 518),
    map_point(485, 725),
    map_point(620, 505),
    map_point(565, 505),
    map_point(610, 285),
]
fg_draw.polygon(bolt_hi, fill=(253, 230, 138, 255))

fg_path = os.path.join('assets', 'images', 'icon_foreground.png')
fg.save(fg_path, 'PNG', quality=100)
print(f"✓ Adaptive foreground created at {fg_path}")

