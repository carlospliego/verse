# App icon

`make_icon.swift` draws the icon with CoreGraphics and writes an `.iconset`.
Placeholder art — SPEC §11 lists icon design as an open question.

```bash
swiftc -O -o /tmp/makeicon make_icon.swift
/tmp/makeicon /tmp/AppIcon.iconset
iconutil -c icns /tmp/AppIcon.iconset -o ../../Resources/AppIcon.icns
```

The **status item** icon is separate and is not this file: it is the `book.closed`
SF Symbol, set in `StatusItemLabel`. A symbol is already a template image, so it follows
light/dark mode and menu bar tinting without any extra assets.
