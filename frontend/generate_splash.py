from PIL import Image, ImageDraw, ImageFont
import os

def create_gradient(draw, width, height, color1, color2):
    """Create a vertical gradient"""
    for y in range(height):
        ratio = y / height
        r = int(color1[0] + (color2[0] - color1[0]) * ratio)
        g = int(color1[1] + (color2[1] - color1[1]) * ratio)
        b = int(color1[2] + (color2[2] - color1[2]) * ratio)
        draw.line([(0, y), (width, y)], fill=(r, g, b))

# Create splash screen (common size: 1242x2688 for iOS, but we'll make 1242x2208)
width = 1242
height = 2208
img = Image.new('RGB', (width, height))
draw = ImageDraw.Draw(img)

# Create gradient background
create_gradient(draw, width, height, (37, 99, 235), (29, 78, 216))

# Calculate center
cx, cy = width // 2, height // 2

# Scale factor for logo (make it smaller for splash)
scale = 0.35
logo_size = int(1024 * scale)
logo_x = cx - logo_size // 2
logo_y = cy - logo_size // 2 - 100

# Draw shield logo (scaled)
s = scale * 1024 / 1024  # base scale
shield_path = [
    (int(512*s + logo_x), int(150*s + logo_y)),
    (int(600*s + logo_x), int(155*s + logo_y)),
    (int(680*s + logo_x), int(170*s + logo_y)),
    (int(740*s + logo_x), int(190*s + logo_y)),
    (int(780*s + logo_x), int(210*s + logo_y)),
    (int(810*s + logo_x), int(235*s + logo_y)),
    (int(820*s + logo_x), int(280*s + logo_y)),
    (int(820*s + logo_x), int(500*s + logo_y)),
    (int(815*s + logo_x), int(580*s + logo_y)),
    (int(800*s + logo_x), int(650*s + logo_y)),
    (int(775*s + logo_x), int(710*s + logo_y)),
    (int(740*s + logo_x), int(765*s + logo_y)),
    (int(690*s + logo_x), int(815*s + logo_y)),
    (int(630*s + logo_x), int(855*s + logo_y)),
    (int(570*s + logo_x), int(885*s + logo_y)),
    (int(512*s + logo_x), int(910*s + logo_y)),
    (int(454*s + logo_x), int(885*s + logo_y)),
    (int(394*s + logo_x), int(855*s + logo_y)),
    (int(334*s + logo_x), int(815*s + logo_y)),
    (int(284*s + logo_x), int(765*s + logo_y)),
    (int(249*s + logo_x), int(710*s + logo_y)),
    (int(224*s + logo_x), int(650*s + logo_y)),
    (int(209*s + logo_x), int(580*s + logo_y)),
    (int(204*s + logo_x), int(500*s + logo_y)),
    (int(204*s + logo_x), int(280*s + logo_y)),
    (int(214*s + logo_x), int(235*s + logo_y)),
    (int(244*s + logo_x), int(210*s + logo_y)),
    (int(284*s + logo_x), int(190*s + logo_y)),
    (int(344*s + logo_x), int(170*s + logo_y)),
    (int(424*s + logo_x), int(155*s + logo_y))
]
draw.polygon(shield_path, fill='#FFFFFF', outline='#1E40AF', width=5)

# Draw inner shield
shield_inner = [
    (int(512*s + logo_x), int(190*s + logo_y)),
    (int(580*s + logo_x), int(195*s + logo_y)),
    (int(640*s + logo_x), int(210*s + logo_y)),
    (int(690*s + logo_x), int(230*s + logo_y)),
    (int(730*s + logo_x), int(255*s + logo_y)),
    (int(760*s + logo_x), int(290*s + logo_y)),
    (int(770*s + logo_x), int(480*s + logo_y)),
    (int(765*s + logo_x), int(560*s + logo_y)),
    (int(750*s + logo_x), int(630*s + logo_y)),
    (int(720*s + logo_x), int(690*s + logo_y)),
    (int(680*s + logo_x), int(740*s + logo_y)),
    (int(620*s + logo_x), int(790*s + logo_y)),
    (int(560*s + logo_x), int(820*s + logo_y)),
    (int(512*s + logo_x), int(840*s + logo_y)),
    (int(464*s + logo_x), int(820*s + logo_y)),
    (int(404*s + logo_x), int(790*s + logo_y)),
    (int(344*s + logo_x), int(740*s + logo_y)),
    (int(304*s + logo_x), int(690*s + logo_y)),
    (int(274*s + logo_x), int(630*s + logo_y)),
    (int(259*s + logo_x), int(560*s + logo_y)),
    (int(254*s + logo_x), int(480*s + logo_y)),
    (int(264*s + logo_x), int(290*s + logo_y)),
    (int(294*s + logo_x), int(255*s + logo_y)),
    (int(334*s + logo_x), int(230*s + logo_y)),
    (int(384*s + logo_x), int(210*s + logo_y)),
    (int(444*s + logo_x), int(195*s + logo_y))
]
draw.polygon(shield_inner, fill='#EFF6FF', outline='#93C5FD', width=2)

# Draw lightning bolt
bolt_outer = [
    (int(555*s + logo_x), int(320*s + logo_y)),
    (int(465*s + logo_x), int(515*s + logo_y)),
    (int(515*s + logo_x), int(515*s + logo_y)),
    (int(485*s + logo_x), int(715*s + logo_y)),
    (int(630*s + logo_x), int(485*s + logo_y)),
    (int(560*s + logo_x), int(485*s + logo_y)),
    (int(600*s + logo_x), int(320*s + logo_y))
]
draw.polygon(bolt_outer, fill='#FBBF24', outline='#D97706', width=4)

# Draw bolt highlight
bolt_highlight = [
    (int(568*s + logo_x), int(340*s + logo_y)),
    (int(490*s + logo_x), int(510*s + logo_y)),
    (int(525*s + logo_x), int(510*s + logo_y)),
    (int(502*s + logo_x), int(665*s + logo_y)),
    (int(610*s + logo_x), int(495*s + logo_y)),
    (int(572*s + logo_x), int(495*s + logo_y)),
    (int(600*s + logo_x), int(340*s + logo_y))
]
draw.polygon(bolt_highlight, fill='#FDE68A')

# Draw energy circles
circles = [(400, 390), (624, 390), (400, 630), (624, 630)]
for cx_orig, cy_orig in circles:
    cx_new = int(cx_orig * s + logo_x)
    cy_new = int(cy_orig * s + logo_y)
    r1, r2, r3 = int(28*s), int(18*s), int(8*s)
    # Outer glow
    draw.ellipse([cx_new-r1, cy_new-r1, cx_new+r1, cy_new+r1], fill='#FEF3C7', outline='#FCD34D', width=1)
    # Inner circle
    draw.ellipse([cx_new-r2, cy_new-r2, cx_new+r2, cy_new+r2], fill='#FBBF24')
    # Highlight
    draw.ellipse([cx_new-r3, cy_new-r3, cx_new+r3, cy_new+r3], fill='#FDE68A')

# Add app name below logo
try:
    # Try to use a nice font if available
    font = ImageFont.truetype("arial.ttf", 72)
    tagline_font = ImageFont.truetype("arial.ttf", 32)
except:
    # Fallback to default
    font = ImageFont.load_default()
    tagline_font = ImageFont.load_default()

# Draw app name
app_name = "VOLT GUARD"
tagline = "Smart Energy Management"

# Get text bbox for centering (using textbbox with default anchor)
bbox = draw.textbbox((0, 0), app_name, font=font)
text_width = bbox[2] - bbox[0]
text_x = cx - text_width // 2
text_y = cy + logo_size // 2 + 50

draw.text((text_x, text_y), app_name, fill='#FFFFFF', font=font)

# Draw tagline
bbox2 = draw.textbbox((0, 0), tagline, font=tagline_font)
tag_width = bbox2[2] - bbox2[0]
tag_x = cx - tag_width // 2
tag_y = text_y + 90

draw.text((tag_x, tag_y), tagline, fill='#E0E7FF', font=tagline_font)

# Save the splash screen
output_path = os.path.join('assets', 'images', 'splash.png')
img.save(output_path, 'PNG', quality=100)
print(f"✓ Splash screen created successfully at {output_path}")
print(f"  Size: {width}x{height}px")
print(f"  Ready for use in your Flutter app")
