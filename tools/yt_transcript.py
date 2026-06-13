"""
YouTube transcript extractor.

Extract transcripts from YouTube videos. No API key required.

Usage:
  uv run ~/tools/yt_transcript.py "https://www.youtube.com/watch?v=VIDEO_ID"
  uv run ~/tools/yt_transcript.py "VIDEO_ID" --timestamps
  uv run ~/tools/yt_transcript.py "VIDEO_ID" -o transcript.md
  uv run ~/tools/yt_transcript.py "VIDEO_ID" -l es -l en
"""

import argparse
import re
import sys
from pathlib import Path
from urllib.parse import parse_qs, urlparse

from youtube_transcript_api import YouTubeTranscriptApi
from youtube_transcript_api._errors import (
    CouldNotRetrieveTranscript,
    NoTranscriptFound,
    TranscriptsDisabled,
)


def extract_video_id(url_or_id: str) -> str | None:
    """Extract YouTube video ID from URL or return the ID if already bare."""
    if re.match(r"^[a-zA-Z0-9_-]{11}$", url_or_id):
        return url_or_id

    parsed = urlparse(url_or_id)

    if parsed.hostname in ("www.youtube.com", "youtube.com", "m.youtube.com"):
        query = parse_qs(parsed.query)
        return query.get("v", [None])[0]

    if parsed.hostname in ("youtu.be", "www.youtu.be"):
        return parsed.path.lstrip("/").split("/")[0]

    return None


def get_transcript(
    url_or_id: str,
    languages: list[str] | None = None,
    preserve_formatting: bool = False,
) -> dict:
    """
    Get transcript from a YouTube video.

    Returns dict with keys: transcript, video_id, language, is_generated, success, error
    """
    if languages is None:
        languages = ["en"]

    video_id = extract_video_id(url_or_id)
    if not video_id:
        raise ValueError(f"Could not extract video ID from: {url_or_id}")

    try:
        api = YouTubeTranscriptApi()
        fetched = api.fetch(video_id, languages=tuple(languages), preserve_formatting=preserve_formatting)

        if preserve_formatting:
            lines = [f"[{s.start:.2f}s] {s.text}" for s in fetched.snippets]
            transcript_text = "\n".join(lines)
        else:
            transcript_text = " ".join(s.text for s in fetched.snippets)

        return {
            "transcript": transcript_text,
            "video_id": video_id,
            "language": fetched.language_code,
            "is_generated": fetched.is_generated,
            "success": True,
        }

    except TranscriptsDisabled:
        return {"transcript": None, "video_id": video_id, "success": False,
                "error": "Transcripts are disabled for this video"}
    except NoTranscriptFound:
        return {"transcript": None, "video_id": video_id, "success": False,
                "error": f"No transcript found in languages: {', '.join(languages)}"}
    except CouldNotRetrieveTranscript as e:
        return {"transcript": None, "video_id": video_id, "success": False,
                "error": f"Could not retrieve transcript: {e}"}
    except Exception as e:
        return {"transcript": None, "video_id": video_id, "success": False,
                "error": f"Unexpected error: {e}"}


def main() -> None:
    parser = argparse.ArgumentParser(description="Extract transcripts from YouTube videos")
    parser.add_argument("url", help="YouTube URL or video ID")
    parser.add_argument("-o", "--output", help="Save to file")
    parser.add_argument("-l", "--language", action="append", dest="languages",
                        help="Language codes (can repeat: -l en -l es)")
    parser.add_argument("--timestamps", action="store_true", help="Preserve timestamps")
    args = parser.parse_args()

    result = get_transcript(args.url, languages=args.languages, preserve_formatting=args.timestamps)

    if not result["success"]:
        print(f"Error: {result['error']}", file=sys.stderr)
        sys.exit(1)

    output = result["transcript"]

    if args.output:
        Path(args.output).write_text(output, encoding="utf-8")
    else:
        print(output)


if __name__ == "__main__":
    main()
