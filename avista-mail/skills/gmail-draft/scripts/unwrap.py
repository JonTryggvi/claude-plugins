#!/usr/bin/env python3
"""Unwrap Google redirect links (google.com/url?q=...) back to their real target.

Usage:
  unwrap.py 'https://www.google.com/url?q=https://example.com&sa=D&...'
  echo "text with links" | unwrap.py
Reads arguments, or stdin when no arguments are given, and prints the text
with every Google redirect URL replaced by its destination.
"""
import re
import sys
from urllib.parse import urlparse, parse_qs, unquote

# google.com, google.is, google.co.uk ... plus the Gmail/Docs redirect hosts
WRAPPER = re.compile(
  r'https?://(?:www\.)?google\.[a-z.]{2,6}/url\?[^\s"\'<>)\]]+',
  re.IGNORECASE,
)


def unwrap_one(url: str) -> str:
  for _ in range(5):  # links are sometimes wrapped more than once
    url = url.replace('&amp;', '&')
    parsed = urlparse(url)
    if not re.match(r'(?:www\.)?google\.[a-z.]{2,6}$', parsed.netloc, re.I) or parsed.path != '/url':
      return url
    params = parse_qs(parsed.query)
    target = (params.get('q') or params.get('url') or [None])[0]
    if not target:
      return url
    url = unquote(target) if '%' in target and '://' not in target else target
  return url


def unwrap_text(text: str) -> str:
  def repl(m: re.Match) -> str:
    raw = m.group(0)
    tail = re.search(r'[.,;:!?]+$', raw)
    trail = tail.group(0) if tail else ''
    return unwrap_one(raw[:len(raw) - len(trail)]) + trail
  return WRAPPER.sub(repl, text)


if __name__ == '__main__':
  data = ' '.join(sys.argv[1:]) if len(sys.argv) > 1 else sys.stdin.read()
  sys.stdout.write(unwrap_text(data) + ('\n' if len(sys.argv) > 1 else ''))
