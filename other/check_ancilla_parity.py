#!/usr/bin/env python3
"""Compare handwritten ancilla ports with the original C, without shipping a C copy.

Requires Python 3, Git, Zig, SDL2, and the baseline commit in the local repository.
Additional arguments are passed through to `zig build test` (e.g. -Doptimize=ReleaseSafe).
"""
import re
import subprocess
import sys
import tempfile
from pathlib import Path

BASELINE = "fbbb3f967a51fafe642e6140d0753979e73b4090"
ROOT = Path(__file__).resolve().parent.parent

# Headers the oracle needs, i.e. the transitive closure of ancilla.c's includes.
# These are pulled from the baseline commit alongside the .c so the check stays
# self-contained: the working tree is pure Zig and no longer carries src/*.h.
HEADERS = [
    "ancilla.h", "assets.h", "dungeon.h", "features.h", "hud.h", "load_gfx.h",
    "misc.h", "overworld.h", "player.h", "sprite.h", "sprite_main.h",
    "tagalong.h", "tile_detect.h", "types.h", "variables.h", "zelda_rtl.h",
]


def main():
    source = subprocess.check_output(
        ["git", "show", f"{BASELINE}:src/ancilla.c"], cwd=ROOT, text=True
    )
    functions = re.findall(
        r"^(?:[\w]+\s+)+\**(\w+)\([^;\n]*\)\s*\{", source, re.MULTILINE
    )
    # Rename definitions and their internal calls, keeping the original control
    # flow and expressions intact. Other subsystems use the normal game symbols.
    names = ["kBomb_Tab0", *functions]
    oracle = "".join(f"#define {name} Ref_{name}\n" for name in names) + source
    with tempfile.TemporaryDirectory(prefix="zelda-ancilla-parity-") as directory:
        # Quoted includes resolve next to the including file, so a flat copy of
        # the closure beside the .c is enough; no include path is needed.
        for header in HEADERS:
            text = subprocess.check_output(
                ["git", "show", f"{BASELINE}:src/{header}"], cwd=ROOT, text=True
            )
            (Path(directory) / header).write_text(text)
        path = Path(directory) / "ancilla_reference.c"
        path.write_text(oracle)
        return subprocess.call(
            ["zig", "build", "test", f"-Dancilla-reference={path}", "--summary", "all", *sys.argv[1:]],
            cwd=ROOT,
        )


if __name__ == "__main__":
    raise SystemExit(main())
