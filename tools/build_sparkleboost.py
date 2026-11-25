"""Generate exact UI textures and package the standalone SparkleBoost addon."""
from pathlib import Path
import hashlib
import math
import zipfile

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ADDON = ROOT / "SparkleBoost"
VERSION = "0.1.1-test"


def texture(name, width, height, alpha):
    image = Image.new("RGBA", (width, height))
    pixels = image.load()
    for y in range(height):
        for x in range(width):
            value = max(0, min(1, alpha((x + 0.5) / width, (y + 0.5) / height)))
            pixels[x, y] = (255, 255, 255, round(value * 255))
    destination = ADDON / "Textures" / (name + ".tga")
    destination.parent.mkdir(parents=True, exist_ok=True)
    image.save(destination, compression=None)
    with Image.open(destination) as check:
        assert check.size == (width, height) and check.mode == "RGBA"


def flare(u, v):
    x, y = abs(u * 2 - 1), abs(v * 2 - 1)
    r = math.hypot(x, y)
    cross = math.exp(-x * 28) * (1 - y) ** 3 + math.exp(-y * 28) * (1 - x) ** 3
    core = math.exp(-(r * 6) ** 2)
    diagonal = 0.24 * math.exp(-abs(x - y) * 25) * max(0, 1 - r) ** 4
    return core + cross * 0.9 + diagonal


def halo(u, v):
    r = math.hypot(u * 2 - 1, v * 2 - 1)
    if r > 1:
        return 0
    return 0.86 * math.exp(-((r - 0.70) / 0.08) ** 2) + 0.15 * math.exp(-r * r * 7)


def beam(u, v):
    x = u * 2 - 1
    width = 0.13 + 0.50 * v
    body = math.exp(-((x / width) ** 2) * 3) * v ** 1.1
    core = 0.3 * math.exp(-(x / 0.075) ** 2) * v ** 0.8
    return body + core


def build():
    texture("flare", 64, 64, flare)
    texture("halo", 128, 128, halo)
    texture("beam", 64, 256, beam)
    toc = (ADDON / "SparkleBoost.toc").read_text(encoding="utf-8")
    assert "## Interface: 16001" in toc
    assert f"## Version: {VERSION}" in toc
    for line in toc.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        path = (ADDON / line.replace("\\", "/")).resolve()
        assert path.is_relative_to(ADDON.resolve()) and path.is_file(), line
    destination = ROOT / "dist" / f"SparkleBoost-{VERSION}.zip"
    destination.parent.mkdir(exist_ok=True)
    files = sorted(path for path in ADDON.rglob("*") if path.is_file())
    with zipfile.ZipFile(destination, "w", zipfile.ZIP_DEFLATED) as archive:
        for path in files:
            archive.write(path, path.relative_to(ROOT).as_posix())
    with zipfile.ZipFile(destination) as archive:
        assert archive.testzip() is None
        assert all(name.startswith("SparkleBoost/") for name in archive.namelist())
        assert len(archive.namelist()) == len(files)
        assert len([name for name in archive.namelist() if name.endswith(".tga")]) == 3
        assert archive.read("SparkleBoost/SparkleBoost.toc").decode("utf-8") == toc
    digest = hashlib.sha256(destination.read_bytes()).hexdigest()
    destination.with_suffix(".zip.sha256").write_text(digest + "  " + destination.name + "\n", encoding="ascii")
    print(f"PACKAGED {destination} ({destination.stat().st_size:,} bytes, {len(files)} files)")
    print("SHA256", digest)


if __name__ == "__main__":
    build()
