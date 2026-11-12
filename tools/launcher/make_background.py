"""Encodes the launcher's background loop (ui/assets/background.webm).

1. Record the frames from the game (needs your Ragnarok data mounted):
       godot --path 06_Godot_Project -s res://tests/capture_launcher_bg.gd
   They land in %APPDATA%/Godot/app_userdata/Project Twilight/captures/launcher_bg/.
2. Run this script. It needs ffmpeg with libvpx-vp9: pass its path as the
   first argument, or have `ffmpeg` on PATH.

The blur and darkening are baked into the file on purpose: the launcher ships
an atmosphere, not a usable recording of anyone's game art.
"""
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
FRAMES = os.path.join(os.environ.get("APPDATA", ""), "Godot", "app_userdata", "Project Twilight", "captures", "launcher_bg")
OUT = os.path.join(HERE, "ui", "assets", "background.webm")


def main() -> int:
    ffmpeg = sys.argv[1] if len(sys.argv) > 1 else shutil.which("ffmpeg")
    if not ffmpeg or not os.path.isfile(ffmpeg):
        print("ffmpeg was not found. Pass its full path as the first argument.")
        return 1
    if not os.path.isfile(os.path.join(FRAMES, "f_0000.jpg")):
        print("No frames in", FRAMES, "- run tests/capture_launcher_bg.gd first.")
        return 1
    cmd = [
        ffmpeg, "-y", "-loglevel", "error", "-framerate", "24",
        "-i", os.path.join(FRAMES, "f_%04d.jpg"),
        "-vf", "gblur=sigma=5,eq=brightness=-0.06:saturation=0.85:contrast=0.95,format=yuv420p",
        "-c:v", "libvpx-vp9", "-b:v", "0", "-crf", "40", "-row-mt", "1", "-an", OUT,
    ]
    subprocess.run(cmd, check=True)
    print("wrote", OUT, os.path.getsize(OUT), "bytes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
