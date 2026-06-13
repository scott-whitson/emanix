"""
Web content extractor.

Extract clean article text from URLs, stripping ads/nav/boilerplate.

Usage:
  uv run ~/tools/web_extract.py "https://example.com/article"
  uv run ~/tools/web_extract.py "https://example.com" -o article.md
  uv run ~/tools/web_extract.py "https://example.com" -f text
  uv run ~/tools/web_extract.py "https://example.com" --precision
"""

import argparse
import sys
from pathlib import Path

import trafilatura


def extract_content(
    url: str,
    output_format: str = "markdown",
    include_comments: bool = False,
    precision_mode: bool = False,
) -> dict:
    """
    Extract clean content from a web URL.

    Returns dict with keys: content, metadata, url, success, error
    """
    fmt_map = {"markdown": "markdown", "text": "txt", "xml": "xml"}
    if output_format not in fmt_map:
        raise ValueError(f"Invalid format '{output_format}'. Choose from: {set(fmt_map)}")

    downloaded = trafilatura.fetch_url(url)
    if not downloaded:
        return {"content": None, "metadata": None, "url": url, "success": False,
                "error": "Failed to download URL"}

    content = trafilatura.extract(
        downloaded,
        output_format=fmt_map[output_format],
        include_comments=include_comments,
        with_metadata=True,
        favor_precision=precision_mode,
    )

    if not content:
        return {"content": None, "metadata": None, "url": url, "success": False,
                "error": "No content could be extracted"}

    metadata = trafilatura.extract_metadata(downloaded)
    metadata_dict = None
    if metadata:
        metadata_dict = {
            "title": metadata.title,
            "author": metadata.author,
            "date": metadata.date,
            "description": metadata.description,
            "sitename": metadata.sitename,
        }

    return {"content": content, "metadata": metadata_dict, "url": url, "success": True}


def main() -> None:
    parser = argparse.ArgumentParser(description="Extract clean content from web pages")
    parser.add_argument("url", help="URL to extract content from")
    parser.add_argument("-f", "--format", choices=["markdown", "text", "xml"],
                        default="markdown", help="Output format (default: markdown)")
    parser.add_argument("-o", "--output", help="Save to file")
    parser.add_argument("--comments", action="store_true", help="Include comments")
    parser.add_argument("--precision", action="store_true", help="Precision mode (slower, more accurate)")
    args = parser.parse_args()

    result = extract_content(args.url, output_format=args.format,
                             include_comments=args.comments, precision_mode=args.precision)

    if not result["success"]:
        print(f"Error: {result['error']}", file=sys.stderr)
        sys.exit(1)

    if args.output:
        Path(args.output).write_text(result["content"], encoding="utf-8")
    else:
        print(result["content"])


if __name__ == "__main__":
    main()
