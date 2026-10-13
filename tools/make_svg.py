import contourpy
from PIL import Image
import numpy as np
import os

def rdp(points, epsilon):
    if len(points) < 3:
        return points
    first, last = points[0], points[-1]
    if np.all(first == last):
        if len(points) > 3:
            last = points[-2]
        else:
            return points
    diff = last - first
    diff_norm = np.linalg.norm(diff)
    if diff_norm == 0:
        return np.vstack([points[0], points[-1]])
    dists = np.abs(np.cross(np.pad(diff, (0, 1)), np.pad(first - points, ((0, 0), (0, 1)))))[:, 2] / diff_norm
    idx = np.argmax(dists)
    if dists[idx] > epsilon:
        left = rdp(points[:idx+1], epsilon)
        right = rdp(points[idx:], epsilon)
        return np.vstack([left[:-1], right])
    else:
        return np.vstack([points[0], points[-1]])

im = Image.open('examples/acorn_3364582.png')
# Note: contourpy puts y=0 at row 0 (or bottom depending on array).
# For PIL image array, row 0 is y=0 at top.
alpha = np.array(im.split()[3], dtype=np.float64)

c = contourpy.contour_generator(z=alpha, fill_type=contourpy.FillType.OuterCode)
points, codes = c.filled(128.0, 256.0)
pts = points[0]
cds = codes[0]

subpaths = []
cur = []
for p, code in zip(pts, cds):
    if code == 1 and cur:
        subpaths.append(np.array(cur))
        cur = []
    cur.append(p)
if cur:
    subpaths.append(np.array(cur))

d_parts = []
for sp in subpaths:
    s = rdp(sp, 0.45)
    cmds = []
    for i, pt in enumerate(s):
        x, y = round(pt[0], 2), round(pt[1], 2)
        if i == 0:
            cmds.append(f"M {x} {y}")
        else:
            cmds.append(f"L {x} {y}")
    cmds.append("Z")
    d_parts.append(" ".join(cmds))

all_d = " ".join(d_parts)

svg_content = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="512" height="512">
  <path fill="currentColor" fill-rule="evenodd" d="{all_d}" />
</svg>
'''

os.makedirs('assets', exist_ok=True)
with open('assets/acorn.svg', 'w', encoding='utf-8') as f:
    f.write(svg_content)
with open('examples/acorn.svg', 'w', encoding='utf-8') as f:
    f.write(svg_content)

# Also copy the PNG to assets/acorn.png
im.save('assets/acorn.png')
print("Successfully generated assets/acorn.svg, examples/acorn.svg, and assets/acorn.png")
