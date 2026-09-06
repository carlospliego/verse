"""Parse a USFX XML bible into (book_id, chapter, verse, text) tuples.

Used for the World English Bible source, which ships as USFX rather than JSON.

USFX uses milestone markers: <c id="1"/> opens a chapter, <v id="1"/> opens a
verse, <ve/> closes it. Scripture text lives in text nodes between milestones,
usually inside <p> paragraphs. Non-scripture subtrees (footnotes, cross
references, headings, titles) must be skipped entirely.
"""

import re
from lxml import etree

from books import BY_USFX

# Subtrees whose text is never scripture.
SKIP_TAGS = {
    "f",      # footnote
    "x",      # cross reference
    "fig",    # illustration
    "rem",    # remark
    "toc",    # table of contents entry
    "h",      # running header
    "id",     # book id line
    "ide",    # encoding declaration
    "cl",     # chapter label
    "cp",     # published chapter char
    "ms",     # major section heading
    "mt",     # major title
    "s",      # section heading
    "r",      # parallel passage reference
    "sp",     # speaker
    "d",      # descriptive title / psalm superscription
    "b",      # blank line
    "table",  # tables are structural
    "generated",
    "languageCode",
}

# sfm attribute values on <p> that mark non-scripture paragraphs.
SKIP_SFM = {"mt", "mt1", "mt2", "mt3", "ms", "ms1", "s", "s1", "s2",
            "r", "is", "is1", "ip", "iot", "io1", "io2", "imt", "d",
            "cl", "sp", "lit"}

WS = re.compile(r"\s+")


def _clean(text: str) -> str:
    text = WS.sub(" ", text)
    # USFX leaves spaces before punctuation when inline markup is stripped.
    text = re.sub(r"\s+([,.;:!?’”\)])", r"\1", text)
    text = re.sub(r"([“‘\(])\s+", r"\1", text)
    return text.strip()


def parse(path: str):
    """Yield (book_id, chapter, verse, text) in canonical order."""
    tree = etree.parse(path)
    root = tree.getroot()

    verses = {}  # (book_id, chapter, verse) -> [fragments]

    for book_el in root.iter("book"):
        code = book_el.get("id")
        if code not in BY_USFX:
            continue  # front matter, glossary, deuterocanon
        book_id = BY_USFX[code][0]

        chapter = 0
        verse = 0
        active = False

        # Walk the book subtree in document order.
        for event, el in etree.iterwalk(book_el, events=("start", "end")):
            tag = el.tag

            if event == "start":
                if tag == "c":
                    cid = el.get("id")
                    if cid and cid.isdigit():
                        chapter = int(cid)
                    verse = 0
                    active = False
                elif tag == "v":
                    vid = el.get("id") or ""
                    # Ranges like "1-2" and letters like "3a" appear in some texts.
                    m = re.match(r"(\d+)", vid)
                    if m:
                        verse = int(m.group(1))
                        active = True
                elif tag == "ve":
                    active = False
                elif tag in SKIP_TAGS or (
                    tag == "p" and el.get("sfm") in SKIP_SFM
                ):
                    # Consume the whole subtree, but keep its tail text.
                    tail = el.tail
                    el.clear()
                    el.tail = tail
                    continue
                else:
                    if active and el.text:
                        verses.setdefault((book_id, chapter, verse), []).append(el.text)

            else:  # end
                if active and el.tail:
                    verses.setdefault((book_id, chapter, verse), []).append(el.tail)

        # <v> milestones carry their following text as .tail, handled above.

    for (book_id, chapter, verse), frags in sorted(verses.items()):
        if chapter == 0 or verse == 0:
            continue
        text = _clean("".join(frags))
        if text:
            yield book_id, chapter, verse, text


if __name__ == "__main__":
    import sys
    rows = list(parse(sys.argv[1]))
    print(f"{len(rows)} verses")
    for r in rows[:3]:
        print(r)
