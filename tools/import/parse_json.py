"""Parse a scrollmapper-format JSON bible into (book_id, chapter, verse, text).

Shape:
{
  "translation": "ASV: American Standard Version (1901)",
  "books": [ {"name": "Genesis",
              "chapters": [ {"chapter": 1,
                             "verses": [ {"verse": 1, "text": "..."} ]} ]} ]
}
"""

import json
import re

from books import book_by_name

WS = re.compile(r"\s+")
# Some sources leave bracketed editorial insertions and stray markup.
MARKUP = re.compile(r"</?[a-zA-Z][^>]*>")


def _clean(text: str) -> str:
    text = MARKUP.sub("", text)
    text = text.replace("\u00a0", " ")
    text = WS.sub(" ", text)
    return text.strip()


def parse(path: str):
    with open(path, encoding="utf-8") as fh:
        data = json.load(fh)

    for book in data["books"]:
        meta = book_by_name(book["name"])
        book_id = meta[0]
        for chapter in book["chapters"]:
            cnum = int(chapter["chapter"])
            for verse in chapter["verses"]:
                vnum = int(verse["verse"])
                text = _clean(verse["text"])
                if text:
                    yield book_id, cnum, vnum, text


if __name__ == "__main__":
    import sys
    rows = list(parse(sys.argv[1]))
    print(f"{len(rows)} verses")
    for r in rows[:2]:
        print(r)
