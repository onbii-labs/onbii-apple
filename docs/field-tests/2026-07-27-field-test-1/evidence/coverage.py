#!/usr/bin/env python3
"""How much audible speech did the transcript actually capture?

Compares per-window loudness in a preserved source recording against the word
timings in that object's `derived/transcript.json`, and reports how much
speech-level audio produced no words at all.

The point is to separate two very different failures that look identical in a
transcript: audio that was never captured, and audio that was captured but not
recognised. Run it against an `.onbii` object:

    ./coverage.py "~/…/Onbii Archive/20260727-0902 Recording.onbii"

Caveat: "speech-level" here means 8 dB above the recording's own ambient floor.
Outdoors that also catches wind and traffic, so the figure overstates lost
speech on the walking recordings. It is trustworthy on quiet, indoor audio.

Requires ffmpeg on PATH. No third-party Python packages.
"""

import array
import json
import math
import subprocess
import sys
from pathlib import Path

SAMPLE_RATE = 8000
WINDOW_SECONDS = 0.5
# How far above a recording's own ambient floor counts as speech-level.
SPEECH_MARGIN_DB = 8.0


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


def transcribed_windows(transcript_path: Path, count: int) -> list[bool]:
    """Which loudness windows any transcript word overlaps."""
    document = json.loads(transcript_path.read_text())
    covered = [False] * count
    for word in document["timeline"]:
        first = int(word["startSeconds"] / WINDOW_SECONDS)
        last = int((word["startSeconds"] + word["durationSeconds"]) / WINDOW_SECONDS)
        for index in range(first, last + 1):
            if 0 <= index < count:
                covered[index] = True
    return covered


def report(bundle: Path) -> None:
    levels = loudness_windows(bundle / "source" / "recording.m4a")
    covered = transcribed_windows(bundle / "derived" / "transcript.json", len(levels))

    ordered = sorted(levels)
    floor = ordered[len(ordered) // 10]  # 10th percentile: the ambient bed
    loud = [i for i, level in enumerate(levels) if level > floor + SPEECH_MARGIN_DB]
    missed = [i for i in loud if not covered[i]]

    print(f"{bundle.name}")
    print(f"  ambient floor        {floor:6.1f} dBFS")
    print(f"  median level         {ordered[len(ordered) // 2]:6.1f} dBFS")
    print(f"  speech-level audio   {len(loud) / len(levels) * 100:5.0f}% of the file")
    print(f"  of that, no words    {len(missed) / max(1, len(loud)) * 100:5.0f}%"
          f"  ({len(missed) * WINDOW_SECONDS:.0f} s)")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(f"usage: {sys.argv[0]} <object.onbii> [...]")
    for argument in sys.argv[1:]:
        report(Path(argument).expanduser())
