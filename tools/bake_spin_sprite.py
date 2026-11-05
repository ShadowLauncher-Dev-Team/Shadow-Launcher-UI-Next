# SPDX-License-Identifier: AGPL-3.0-or-later
"""把 Google 风格的不确定环(F 方案)烘焙成帧序列图，供 QML AnimatedSprite 播放。

为什么烘焙：QML 里用 Canvas/PathAngleArc 每帧重画 dash 伸缩，会受数据刷新、
delegate 重建、重绘时序影响，表现为"转一下回跳 / 变长缩回"。烘焙后运行时
只换贴图，动画永远不会被重置。

参数与 design/step-spinner-google.html 的 F 方案一致：
  viewBox 20, cx=cy=10, r=8, stroke-width 2, round cap
  spin 1.6s/圈（linear），dash 1.4s（0%:1 42/off0 → 50%:26 42/off-10 → 100%:1 42/off-42）
两个周期的最小公倍数是 11.2s，因此帧数 = fps * 11.2，播放完正好无缝循环。

用法：
  python tools/bake_spin_sprite.py
  python tools/bake_spin_sprite.py --fps 30 --size 32 --cols 16
输出：icons/anim/spin-f.png
"""
import argparse
import math
import os

from PIL import Image, ImageDraw

CIRC = 2 * math.pi * 8.0
BASE = (35, 42, 52)      # #232a34
ARC = (59, 130, 246)     # #3b82f6


def ease_in_out(u: float) -> float:
    # CSS ease-in-out 的余弦近似，弧长伸缩的手感与网页一致
    return 0.5 - 0.5 * math.cos(math.pi * u)


def state(t: float):
    """返回 (旋转角, dash 长度, dash 偏移)，单位均为 SVG 用户单位。"""
    rot = (t / 1.6) * 360.0
    td = t % 1.4
    if td < 0.7:
        e = ease_in_out(td / 0.7)
        return rot, 1 + 25 * e, -10 * e
    e = ease_in_out((td - 0.7) / 0.7)
    return rot, 26 - 25 * e, -10 - 32 * e


def draw_frame(i: int, n: int, size: int, ss: int) -> Image.Image:
    t = i * 11.2 / n
    rot, dash, off = state(t)
    s = ss
    img = Image.new("RGBA", (20 * s, 20 * s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx = cy = 10 * s
    r = 8 * s
    w = 2 * s
    box = [cx - r, cy - r, cx + r, cy + r]
    d.arc(box, 0, 360, fill=BASE + (255,), width=w)

    # dash 沿圆周平铺：段长 dash、间隔 42，整体偏移 off（SVG 单位）
    period = dash + 42.0
    seg = off
    while seg < CIRC:
        a0 = max(seg, 0.0)
        a1 = min(seg + dash, CIRC)
        if a1 > a0 + 1e-6:
            s_deg = -90 + rot + a0 / CIRC * 360
            e_deg = -90 + rot + a1 / CIRC * 360
            d.arc(box, s_deg, e_deg, fill=ARC + (255,), width=w)
            for adeg in (s_deg, e_deg):
                rr = w / 2
                ax = cx + r * math.cos(math.radians(adeg))
                ay = cy + r * math.sin(math.radians(adeg))
                d.ellipse([ax - rr, ay - rr, ax + rr, ay + rr], fill=ARC + (255,))
        seg += period
    return img.resize((size, size), Image.LANCZOS)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--fps", type=int, default=30)
    ap.add_argument("--size", type=int, default=32)
    ap.add_argument("--cols", type=int, default=16)
    ap.add_argument("--ss", type=int, default=4, help="超采样倍数")
    ap.add_argument("--out", default=os.path.join("icons", "anim", "spin-f.png"))
    args = ap.parse_args()

    n = int(round(args.fps * 11.2))
    rows = (n + args.cols - 1) // args.cols
    sheet = Image.new("RGBA", (args.cols * args.size, rows * args.size), (0, 0, 0, 0))
    for i in range(n):
        sheet.paste(draw_frame(i, n, args.size, args.ss),
                    ((i % args.cols) * args.size, (i // args.cols) * args.size))
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    sheet.save(args.out, optimize=True)
    print(f"frames={n} fps={args.fps} size={args.size} cols={args.cols} -> {args.out} "
          f"({os.path.getsize(args.out)} bytes)")


if __name__ == "__main__":
    main()
