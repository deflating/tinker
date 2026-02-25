#!/usr/bin/env python3
"""Generate Familiar app icon at all required sizes with pixel cat drawn programmatically."""

from PIL import Image, ImageDraw
import os

def draw_pixel_cat(size):
    """Draw pixel cat on a canvas of given size.

    The cat is defined on a 20x13 pixel grid to capture ears, head, whiskers, and jaw.
    """
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    bg_color = (248, 245, 240, 255)  # warm off-white
    draw.rectangle([0, 0, size, size], fill=bg_color)

    # 20 columns x 13 rows grid
    grid_w, grid_h = 20, 13

    # Cat occupies ~70% of icon width
    block = int(size * 0.70 / grid_w)

    # Center the cat
    cat_w = block * grid_w
    cat_h = block * grid_h
    ox = (size - cat_w) // 2
    oy = (size - cat_h) // 2 + int(size * 0.02)

    black = (30, 30, 30, 255)
    yellow = (255, 220, 0, 255)

    # (row, col, width, height) in grid units
    # Tracing from original: ears at top, wide head, 3 whiskers each side, tapered jaw
    cat_blocks = [
        # Left ear (pointy, 2 blocks wide)
        (0, 4, 2, 1),
        (1, 4, 2, 1),
        (2, 4, 3, 1),
        # Right ear
        (0, 14, 2, 1),
        (1, 14, 2, 1),
        (2, 13, 3, 1),
        # Head top connecting ears
        (3, 5, 10, 1),
        # Head body (wide)
        (4, 4, 12, 1),
        (5, 4, 12, 1),
        (6, 4, 12, 1),
        (7, 4, 12, 1),
        (8, 4, 12, 1),
        # Jaw taper
        (9, 5, 10, 1),
        (10, 6, 8, 1),

        # Left whiskers (3 lines extending left)
        (7, 0, 4, 1),   # top whisker
        (8, 1, 3, 1),   # middle whisker
        (9, 2, 3, 1),   # bottom whisker

        # Right whiskers (3 lines extending right)
        (7, 16, 4, 1),  # top whisker
        (8, 16, 3, 1),  # middle whisker
        (9, 15, 3, 1),  # bottom whisker
    ]

    for (r, c, w, h) in cat_blocks:
        x1 = ox + c * block
        y1 = oy + r * block
        x2 = x1 + w * block
        y2 = y1 + h * block
        draw.rectangle([x1, y1, x2, y2], fill=black)

    # Eyes (yellow squares) — positioned in the middle of the head
    eye_positions = [(7, 7), (7, 12)]
    for (r, c) in eye_positions:
        x1 = ox + c * block
        y1 = oy + r * block
        x2 = x1 + block
        y2 = y1 + block
        draw.rectangle([x1, y1, x2, y2], fill=yellow)

    return img


def main():
    icon_dir = os.path.join(
        os.path.dirname(__file__),
        "Familiar", "Assets.xcassets", "AppIcon.appiconset"
    )

    sizes = [16, 32, 64, 128, 256, 512, 1024]

    for s in sizes:
        # Always use NEAREST for pixel art crispness
        render_size = max(s, 1024)
        img = draw_pixel_cat(render_size)
        img = img.resize((s, s), Image.NEAREST)

        path = os.path.join(icon_dir, f"icon_{s}x{s}.png")
        img.save(path, "PNG")
        print(f"  Generated {s}x{s}")

    print("Done!")


if __name__ == "__main__":
    main()
