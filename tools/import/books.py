"""Canonical 66-book metadata, in canonical order.

id: 1..66
usfx: USFX/Paratext book code (used by the WEB source)
name: display name
abbrev: short display abbreviation
testament: OT | NT
"""

BOOKS = [
    (1,  "GEN", "Genesis",         "Gen",   "OT", 50),
    (2,  "EXO", "Exodus",          "Exod",  "OT", 40),
    (3,  "LEV", "Leviticus",       "Lev",   "OT", 27),
    (4,  "NUM", "Numbers",         "Num",   "OT", 36),
    (5,  "DEU", "Deuteronomy",     "Deut",  "OT", 34),
    (6,  "JOS", "Joshua",          "Josh",  "OT", 24),
    (7,  "JDG", "Judges",          "Judg",  "OT", 21),
    (8,  "RUT", "Ruth",            "Ruth",  "OT", 4),
    (9,  "1SA", "1 Samuel",        "1 Sam", "OT", 31),
    (10, "2SA", "2 Samuel",        "2 Sam", "OT", 24),
    (11, "1KI", "1 Kings",         "1 Kgs", "OT", 22),
    (12, "2KI", "2 Kings",         "2 Kgs", "OT", 25),
    (13, "1CH", "1 Chronicles",    "1 Chr", "OT", 29),
    (14, "2CH", "2 Chronicles",    "2 Chr", "OT", 36),
    (15, "EZR", "Ezra",            "Ezra",  "OT", 10),
    (16, "NEH", "Nehemiah",        "Neh",   "OT", 13),
    (17, "EST", "Esther",          "Esth",  "OT", 10),
    (18, "JOB", "Job",             "Job",   "OT", 42),
    (19, "PSA", "Psalms",          "Ps",    "OT", 150),
    (20, "PRO", "Proverbs",        "Prov",  "OT", 31),
    (21, "ECC", "Ecclesiastes",    "Eccl",  "OT", 12),
    (22, "SNG", "Song of Solomon", "Song",  "OT", 8),
    (23, "ISA", "Isaiah",          "Isa",   "OT", 66),
    (24, "JER", "Jeremiah",        "Jer",   "OT", 52),
    (25, "LAM", "Lamentations",    "Lam",   "OT", 5),
    (26, "EZK", "Ezekiel",         "Ezek",  "OT", 48),
    (27, "DAN", "Daniel",          "Dan",   "OT", 12),
    (28, "HOS", "Hosea",           "Hos",   "OT", 14),
    (29, "JOL", "Joel",            "Joel",  "OT", 3),
    (30, "AMO", "Amos",            "Amos",  "OT", 9),
    (31, "OBA", "Obadiah",         "Obad",  "OT", 1),
    (32, "JON", "Jonah",           "Jonah", "OT", 4),
    (33, "MIC", "Micah",           "Mic",   "OT", 7),
    (34, "NAM", "Nahum",           "Nah",   "OT", 3),
    (35, "HAB", "Habakkuk",        "Hab",   "OT", 3),
    (36, "ZEP", "Zephaniah",       "Zeph",  "OT", 3),
    (37, "HAG", "Haggai",          "Hag",   "OT", 2),
    (38, "ZEC", "Zechariah",       "Zech",  "OT", 14),
    (39, "MAL", "Malachi",         "Mal",   "OT", 4),
    (40, "MAT", "Matthew",         "Matt",  "NT", 28),
    (41, "MRK", "Mark",            "Mark",  "NT", 16),
    (42, "LUK", "Luke",            "Luke",  "NT", 24),
    (43, "JHN", "John",            "John",  "NT", 21),
    (44, "ACT", "Acts",            "Acts",  "NT", 28),
    (45, "ROM", "Romans",          "Rom",   "NT", 16),
    (46, "1CO", "1 Corinthians",   "1 Cor", "NT", 16),
    (47, "2CO", "2 Corinthians",   "2 Cor", "NT", 13),
    (48, "GAL", "Galatians",       "Gal",   "NT", 6),
    (49, "EPH", "Ephesians",       "Eph",   "NT", 6),
    (50, "PHP", "Philippians",     "Phil",  "NT", 4),
    (51, "COL", "Colossians",      "Col",   "NT", 4),
    (52, "1TH", "1 Thessalonians", "1 Thess", "NT", 5),
    (53, "2TH", "2 Thessalonians", "2 Thess", "NT", 3),
    (54, "1TI", "1 Timothy",       "1 Tim", "NT", 6),
    (55, "2TI", "2 Timothy",       "2 Tim", "NT", 4),
    (56, "TIT", "Titus",           "Titus", "NT", 3),
    (57, "PHM", "Philemon",        "Phlm",  "NT", 1),
    (58, "HEB", "Hebrews",         "Heb",   "NT", 13),
    (59, "JAS", "James",           "Jas",   "NT", 5),
    (60, "1PE", "1 Peter",         "1 Pet", "NT", 5),
    (61, "2PE", "2 Peter",         "2 Pet", "NT", 3),
    (62, "1JN", "1 John",          "1 John", "NT", 5),
    (63, "2JN", "2 John",          "2 John", "NT", 1),
    (64, "3JN", "3 John",          "3 John", "NT", 1),
    (65, "JUD", "Jude",            "Jude",  "NT", 1),
    (66, "REV", "Revelation",      "Rev",   "NT", 22),
]

BY_USFX = {b[1]: b for b in BOOKS}
BY_ID = {b[0]: b for b in BOOKS}

# Source JSON files use full display names; a few differ from ours.
_NAME_ALIASES = {
    "Song of Songs": "Song of Solomon",
    "Canticles": "Song of Solomon",
    "Psalm": "Psalms",
    "Revelation of John": "Revelation",
    "The Revelation": "Revelation",
    "Acts of the Apostles": "Acts",
}

BY_NAME = {}
for _b in BOOKS:
    BY_NAME[_b[2].lower()] = _b
for _alias, _canon in _NAME_ALIASES.items():
    BY_NAME[_alias.lower()] = BY_NAME[_canon.lower()]


_ROMAN = {"i": "1", "ii": "2", "iii": "3",
          "first": "1", "second": "2", "third": "3"}


def book_by_name(name: str):
    key = " ".join(name.strip().split()).lower()
    if key in BY_NAME:
        return BY_NAME[key]

    # Sources vary between "1 Samuel", "I Samuel" and "First Samuel".
    parts = key.split(" ", 1)
    if len(parts) == 2 and parts[0] in _ROMAN:
        alt = f"{_ROMAN[parts[0]]} {parts[1]}"
        if alt in BY_NAME:
            return BY_NAME[alt]

    raise KeyError(f"Unmapped book name: {name!r}")
