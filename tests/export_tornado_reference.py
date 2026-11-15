"""Package isolated native captures; run tornado_reference_review.gd -- --capture first."""
from pathlib import Path
import argparse
import shutil
import subprocess
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
NAMES = ["wind", "dark_red", "chaos", "violet", "blue", "debris", "electric", "sand", "fire", "wild_blue", "anime", "green"]
parser = argparse.ArgumentParser()
parser.add_argument("--ffmpeg", default=shutil.which("ffmpeg") or "D:/soft/JianyingPro/10.1.0.13849/ffmpeg.exe")
args = parser.parse_args()
source = ROOT / ".godot/tornado_reference_review"
output = ROOT / "docs/vfx_tornado_reference"
output.mkdir(parents=True, exist_ok=True)
(output / ".gdignore").touch()
font_path = Path("C:/Windows/Fonts/arial.ttf")
font = ImageFont.truetype(str(font_path), 24) if font_path.exists() else ImageFont.load_default()
contact = Image.new("RGB", (1600, 900), (10, 14, 20))
clips = []
for index, name in enumerate(NAMES):
    for suffix in ("", "_rts", "_light", "_forming"):
        shutil.copyfile(source / (name + suffix + ".png"), output / (name + suffix + ".png"))
    thumbnail = Image.open(source / (name + ".png")).convert("RGB").resize((400, 250))
    x, y = index % 4 * 400, index // 4 * 300
    contact.paste(thumbnail, (x, y))
    ImageDraw.Draw(contact).text((x + 12, y + 260), name.replace("_", " ").upper(), font=font, fill="white")
    labeled = source / (name + "_labeled")
    labeled.mkdir(exist_ok=True)
    frames = sorted((source / (name + "_sequence")).glob("frame_*.png"))
    if len(frames) != 48:
        raise RuntimeError("Missing 48-frame native sequence: " + name)
    for frame in frames:
        image = Image.open(frame).convert("RGB")
        draw = ImageDraw.Draw(image)
        draw.rectangle((12, 12, 440, 62), fill=(10, 14, 20))
        draw.text((24, 24), f"{index + 1:02d} / 12   {name.replace('_', ' ').upper()}", font=font, fill="white")
        image.save(labeled / frame.name, compress_level=1)
    clip = output / (name + ".mp4")
    subprocess.run([args.ffmpeg, "-hide_banner", "-loglevel", "error", "-y", "-framerate", "24", "-i", str(labeled / "frame_%03d.png"), "-c:v", "h264_nvenc", "-b:v", "6M", "-pix_fmt", "yuv420p", str(clip)], check=True)
    clips.append(clip)
    print("EXPORTED: " + name, flush=True)
contact.save(output / "contact.png")
manifest = source / "concat.txt"
manifest.write_text("".join("file '" + clip.as_posix() + "'\n" for clip in clips), encoding="utf-8")
subprocess.run([args.ffmpeg, "-hide_banner", "-loglevel", "error", "-y", "-f", "concat", "-safe", "0", "-i", str(manifest), "-c", "copy", str(output / "showcase.mp4")], check=True)
shutil.copyfile(source / "report.json", output / "report.json")
print("TORNADO_EXPORT_OK", flush=True)
