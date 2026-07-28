#!/usr/bin/env python3
"""What changed between an object's transcript generations?

Reprocessing supersedes rather than overwriting (spec decision 0032), so an
object can hold several generations of the same transcript. This compares each
of them against the same source audio and reports how much audible speech each
one actually captured.

The point is to answer "is the new one better, and by how much?" from the object
itself, rather than from an impression of reading it. Run it against an `.onbii`
object that has been transcribed more than once:

    ./compare-generations.py "~/…/Onbii Archive/20260727-0802 Recording.onbii"

Generations are found by reading the manifest: the current transcript, plus
anything retained under a `superseded-…` resource identifier. They are reported
oldest first.

Caveat, inherited from `coverage.py`: "speech-level" means 8 dB above the
recording's own ambient floor, which outdoors also catches wind and traffic. The
absolute figures overstate lost speech on a walking recording. The *difference*
between two generations of the same file is the trustworthy part, because both
are measured against identical audio.

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
    return [
        20 * math.log10(
            math.sqrt(sum(v * v for v in samples[start:start + size]) / size)
            / 32768 + 1e-12
        )
        for start in range(0, len(samples) - size + 1, size)
    ]


def generations(manifest: dict) -> list[tuple[str, str]]:
    """(label, bundle-relative path) per transcript generation, oldest first.

    Retained generations carry the timestamp they were superseded at in their
    identifier, so sorting by identifier sorts by age.
    """
    retained = sorted(
        (r["id"], r["path"]) for r in manifest["resources"]
        if r["id"].startswith("superseded-") and r["id"].endswith("-derived-transcript")
    )
    current = [
        ("current", r["path"]) for r in manifest["resources"]
        if r["id"] == "derived-transcript"
    ]
    return [(i.split("-")[1], p) for i, p in retained] + current


def report(bundle: Path) -> None:
    manifest = json.loads((bundle / "manifest.json").read_text())
    source = next(
        r for r in manifest["resources"] if r.get("role") == "source"
    )
    levels = loudness_windows(bundle / source["path"])
    floor = sorted(levels)[len(levels) // 10]
    loud = [i for i, level in enumerate(levels) if level > floor + SPEECH_MARGIN_DB]

    print(f"{bundle.name}")
    print(f"  {len(levels) * WINDOW_SECONDS:.0f} s of audio, ambient floor "
          f"{floor:.1f} dBFS, {len(loud) / len(levels) * 100:.0f}% speech-level")

    # The configuration each generation was produced under lives in provenance
    # (spec decision 0033), not in the transcript document.
    configurations = [
        event.get("configuration") or {}
        for event in manifest["provenance"]
        if event["action"] == "transcribed"
    ]

    for index, (label, path) in enumerate(generations(manifest)):
        document = json.loads((bundle / path).read_text())
        timeline = document["timeline"]
        covered = [False] * len(levels)
        for word in timeline:
            first = int(word["startSeconds"] / WINDOW_SECONDS)
            last = int(
                (word["startSeconds"] + word["durationSeconds"]) / WINDOW_SECONDS
            )
            for i in range(first, last + 1):
                if 0 <= i < len(covered):
                    covered[i] = True
        missed = [i for i in loud if not covered[i]]

        speakers: dict[str, int] = {}
        for segment in timeline:
            speakers[str(segment.get("speakerID"))] = (
                speakers.get(str(segment.get("speakerID")), 0) + 1
            )
        unplaced = speakers.pop("None", 0)

        configuration = configurations[index] if index < len(configurations) else {}
        languages = ", ".join(configuration.get("languages") or []) or "not recorded"
        selection = configuration.get("languageSelection", "not recorded")

        print(f"\n  [{label}]")
        print(f"    language        {languages} ({selection})")
        print(f"    words           {len(timeline)}")
        print(f"    speech missed   {len(missed) / max(1, len(loud)) * 100:.0f}%"
              f"  ({len(missed) * WINDOW_SECONDS:.0f} s)")
        print(f"    speakers        {speakers}")
        print(f"    unplaced words  {unplaced}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(f"usage: {sys.argv[0]} <object.onbii> [...]")
    for argument in sys.argv[1:]:
        report(Path(argument).expanduser())
