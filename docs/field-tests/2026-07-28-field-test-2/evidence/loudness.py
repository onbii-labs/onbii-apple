#!/usr/bin/env python3
"""What does a recording sound like, before anything tries to recognise it?

`coverage.py` (field test 1) answers "how much audible speech produced no
words", which needs a transcript to compare against. When recognition returns
*nothing at all* there is no transcript, and the question changes: is this a
recording with speech in it that was missed, or a recording that is mostly
ambience?

This reports the loudness structure alone — the ambient bed, how much of the
file rises above it, and how that loud material is distributed. Run it against
one or more `.onbii` objects:

    ./loudness.py "~/…/Onbii Archive/20260728-0908 Recording.onbii"

Caveat, the same one `coverage.py` carries: outdoors, "above the floor" catches
wind, traffic and footsteps as readily as speech. The figure is a description of
the signal, never a claim about how much speech is in it.

Requires ffmpeg on PATH. No third-party Python packages.
"""

import array
import math
import subprocess
import sys
from pathlib import Path

SAMPLE_RATE = 8000
WINDOW_SECONDS = 0.5
SPEECH_MARGIN_DB = 8.0
# A run of loud windows this long or longer is the shape continuous speech
# makes. Wind and footsteps tend to be either constant or impulsive.
RUN_SECONDS = 2.0


def loudness_windows(audio_path: Path) -> list[float]:
    """dBFS per WINDOW_SECONDS of the decoded mono signal."""
    raw = subprocess.run(
        ["ffmpeg", "-v", "quiet", "-i", str(audio_path),
         "-ac", "1", "-ar", str(SAMPLE_RATE), "-f", "s16le", "-"],
        capture_output=True, check=True,
    ).stdout
    samples = array.array("h")
    samples.frombytes(raw[: len(raw) // 2 * 2])

    size = int(SAMPLE_RATE * WINDOW_SECONDS)
    levels = []
    for start in range(0, len(samples) - size + 1, size):
        total = sum(v * v for v in samples[start:start + size])
        levels.append(20 * math.log10(math.sqrt(total / size) / 32768 + 1e-12))
    return levels


def runs_of(flags: list[bool]) -> list[int]:
    """Lengths, in windows, of every consecutive True run."""
    lengths, current = [], 0
    for flag in flags:
        if flag:
            current += 1
        elif current:
            lengths.append(current)
            current = 0
    if current:
        lengths.append(current)
    return lengths


def report(bundle: Path) -> None:
    levels = loudness_windows(bundle / "source" / "recording.m4a")
    ordered = sorted(levels)
    floor = ordered[len(ordered) // 10]
    loud = [level > floor + SPEECH_MARGIN_DB for level in levels]
    lengths = runs_of(loud)
    sustained = [n for n in lengths if n * WINDOW_SECONDS >= RUN_SECONDS]

    print(f"{bundle.name}")
    print(f"  length               {len(levels) * WINDOW_SECONDS:6.0f} s")
    print(f"  ambient floor        {floor:6.1f} dBFS")
    print(f"  median level         {ordered[len(ordered) // 2]:6.1f} dBFS")
    print(f"  90th percentile      {ordered[len(ordered) * 9 // 10]:6.1f} dBFS")
    print(f"  above floor +8 dB    {sum(loud) / len(levels) * 100:5.0f}% of the file")
    print(f"  sustained runs       {len(sustained):6d} of >= {RUN_SECONDS:.0f} s"
          f"  ({sum(sustained) * WINDOW_SECONDS:.0f} s total)")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(f"usage: {sys.argv[0]} <object.onbii> [...]")
    for argument in sys.argv[1:]:
        report(Path(argument).expanduser())
