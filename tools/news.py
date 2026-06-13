"""
Daily tech news briefing from RSS feeds. No API keys required.

Usage:
  uv run ~/tools/news.py              # All feeds
  uv run ~/tools/news.py hn           # Hacker News only
  uv run ~/tools/news.py reddit       # Reddit only
  uv run ~/tools/news.py lobsters     # Lobsters only
  uv run ~/tools/news.py -n 5         # 5 items per feed
"""

import argparse
import sys
import xml.etree.ElementTree as ET
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime

import requests

# --- Config: edit these to taste ---
REDDIT_SUBS = ["python", "linux", "selfhosted", "programming"]
HN_COUNT = 10
REDDIT_COUNT = 5
LOBSTERS_COUNT = 10
# -----------------------------------

HEADERS = {"User-Agent": "news-cli/1.0"}


def fetch_hn(count: int) -> list[dict]:
    """Fetch top Hacker News stories via the public API."""
    try:
        ids = requests.get("https://hacker-news.firebaseio.com/v0/topstories.json",
                           headers=HEADERS, timeout=10).json()[:count]

        def get_story(sid):
            r = requests.get(f"https://hacker-news.firebaseio.com/v0/item/{sid}.json",
                             headers=HEADERS, timeout=10)
            return r.json()

        stories = []
        with ThreadPoolExecutor(max_workers=10) as pool:
            futures = {pool.submit(get_story, sid): sid for sid in ids}
            for f in as_completed(futures):
                s = f.result()
                if s and s.get("title"):
                    stories.append({
                        "title": s["title"],
                        "url": s.get("url", f"https://news.ycombinator.com/item?id={s['id']}"),
                        "score": s.get("score", 0),
                        "comments": s.get("descendants", 0),
                        "hn_link": f"https://news.ycombinator.com/item?id={s['id']}",
                    })

        stories.sort(key=lambda x: x["score"], reverse=True)
        return stories
    except Exception as e:
        print(f"  Error fetching HN: {e}", file=sys.stderr)
        return []


def fetch_reddit(subreddits: list[str], count: int) -> dict[str, list[dict]]:
    """Fetch top posts from subreddits via public RSS feeds."""
    results = {}
    for sub in subreddits:
        try:
            r = requests.get(f"https://www.reddit.com/r/{sub}/hot/.rss?limit={count}",
                             headers=HEADERS, timeout=10)
            root = ET.fromstring(r.text)
            ns = {"atom": "http://www.w3.org/2005/Atom"}
            entries = root.findall("atom:entry", ns)

            posts = []
            for entry in entries[:count]:
                title = entry.find("atom:title", ns)
                link = entry.find("atom:link", ns)
                posts.append({
                    "title": title.text if title is not None else "?",
                    "url": link.get("href") if link is not None else "",
                })
            results[sub] = posts
        except Exception as e:
            print(f"  Error fetching r/{sub}: {e}", file=sys.stderr)
            results[sub] = []
    return results


def fetch_lobsters(count: int) -> list[dict]:
    """Fetch hot stories from Lobsters via RSS."""
    try:
        r = requests.get("https://lobste.rs/hottest.rss", headers=HEADERS, timeout=10)
        root = ET.fromstring(r.text)
        items = root.findall(".//item")

        stories = []
        for item in items[:count]:
            title = item.find("title")
            link = item.find("link")
            stories.append({
                "title": title.text if title is not None else "?",
                "url": link.text if link is not None else "",
            })
        return stories
    except Exception as e:
        print(f"  Error fetching Lobsters: {e}", file=sys.stderr)
        return []


def print_section(title: str, char: str = "="):
    width = max(len(title) + 4, 40)
    print(f"\n{char * width}")
    print(f"  {title}")
    print(f"{char * width}")


def main():
    parser = argparse.ArgumentParser(description="Daily tech news briefing (no API keys)")
    parser.add_argument("sources", nargs="*", default=["all"],
                        help="Sources to fetch: hn, reddit, lobsters, all (default: all)")
    parser.add_argument("-n", "--count", type=int, help="Items per feed (overrides defaults)")
    args = parser.parse_args()

    sources = [s.lower() for s in args.sources]
    fetch_all = "all" in sources

    print(f"News briefing - {datetime.now().strftime('%A, %B %d %Y')}")

    if fetch_all or "hn" in sources:
        count = args.count or HN_COUNT
        print_section(f"Hacker News (top {count})")
        stories = fetch_hn(count)
        for i, s in enumerate(stories, 1):
            print(f"  {i:2}. [{s['score']:>4} pts, {s['comments']:>3} comments] {s['title']}")
            print(f"      {s['url']}")

    if fetch_all or "reddit" in sources:
        count = args.count or REDDIT_COUNT
        print_section(f"Reddit")
        reddit = fetch_reddit(REDDIT_SUBS, count)
        for sub, posts in reddit.items():
            print(f"\n  r/{sub}:")
            for i, p in enumerate(posts, 1):
                print(f"    {i}. {p['title']}")
                print(f"       {p['url']}")

    if fetch_all or "lobsters" in sources:
        count = args.count or LOBSTERS_COUNT
        print_section(f"Lobsters (top {count})")
        stories = fetch_lobsters(count)
        for i, s in enumerate(stories, 1):
            print(f"  {i:2}. {s['title']}")
            print(f"      {s['url']}")

    print()


if __name__ == "__main__":
    main()
