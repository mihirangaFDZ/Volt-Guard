from PIL import Image, ImageDraw
import os

def create_gradient(draw, width, height, color1, color2):
    """Create a vertical gradient"""
    for y in range(height):
        ratio = y / height
        r = int(color1[0] + (color2[0] - color1[0]) * ratio)
        g = int(color1[1] + (color2[1] - color1[1]) * ratio)
        b = int(color1[2] + (color2[2] - color1[2]) * ratio)
        draw.line([(0, y), (width, y)], fill=(r, g, b))

# Create a 1024x1024 image
size = 1024
img = Image.new('RGBA', (size, size), color=(0, 0, 0, 0))
draw = ImageDraw.Draw(img)

# Create background circle with gradient
background = Image.new('RGB', (size, size))
bg_draw = ImageDraw.Draw(background)
create_gradient(bg_draw, size, size, (74, 144, 226), (37, 99, 235))

# Create circular mask
mask = Image.new('L', (size, size), 0)
mask_draw = ImageDraw.Draw(mask)
mask_draw.ellipse([0, 0, size, size], fill=255)

# Apply circular mask to background
img = Image.composite(background, Image.new('RGB', (size, size), (255, 255, 255)), mask)
draw = ImageDraw.Draw(img)

# Draw shield shape - custom shield outline
shield_path = [
    (512, 150), (600, 155), (680, 170), (740, 190), (780, 210), (810, 235),
    (820, 280), (820, 400), (820, 500), (815, 580), (800, 650), (775, 710),
    (740, 765), (690, 815), (630, 855), (570, 885), (512, 910),
    (454, 885), (394, 855), (334, 815), (284, 765), (249, 710), (224, 650),
    (209, 580), (204, 500), (204, 400), (204, 280), (214, 235), (244, 210),
    (284, 190), (344, 170), (424, 155)
]
draw.polygon(shield_path, fill='#FFFFFF', outline='#1E40AF', width=10)

# Draw inner shield highlight
shield_inner = [
    (512, 190), (580, 195), (640, 210), (690, 230), (730, 255), (760, 290),
    (770, 350), (770, 480), (765, 560), (750, 630), (720, 690), (680, 740),
    (620, 790), (560, 820), (512, 840),
    (464, 820), (404, 790), (344, 740), (304, 690), (274, 630), (259, 560),
    (254, 480), (254, 350), (264, 290), (294, 255), (334, 230), (384, 210), (444, 195)
]
draw.polygon(shield_inner, fill='#F0F4FF', outline='#93C5FD', width=3)

# Draw lightning bolt (more detailed)
bolt_outer = [
    (555, 320),
    (465, 515),
    (515, 515),
    (485, 715),
    (630, 485),
    (560, 485),
    (600, 320)
]
# Draw bolt with gradient effect (using multiple layers)
draw.polygon(bolt_outer, fill='#FBBF24', outline='#D97706', width=8)

# Draw bolt highlight
bolt_highlight = [
    (568, 340),
    (490, 510),
    (525, 510),
    (502, 665),
    (610, 495),
    (572, 495),
    (600, 340)
]
draw.polygon(bolt_highlight, fill='#FDE68A')

# Draw energy circles with glow effect
circles = [(400, 390), (624, 390), (400, 630), (624, 630)]
for cx, cy in circles:
    # Outer glow
    draw.ellipse([cx-28, cy-28, cx+28, cy+28], fill='#FEF3C7', outline='#FCD34D', width=2)
    # Inner circle
    draw.ellipse([cx-18, cy-18, cx+18, cy+18], fill='#FBBF24')
    # Highlight
    draw.ellipse([cx-8, cy-8, cx+8, cy+8], fill='#FDE68A')

# Save the image
output_path = os.path.join('assets', 'images', 'icon.png')
os.makedirs(os.path.dirname(output_path), exist_ok=True)
img.save(output_path, 'PNG', quality=100)
print(f"✓ Icon created successfully at {output_path}")
print(f"  Size: {size}x{size}px")
print(f"  Ready for use with flutter_launcher_icons")

