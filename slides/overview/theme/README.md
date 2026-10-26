# slidev-theme-red-hat-deck

A Slidev theme implementing Red Hat brand standards for technical presentations, conference talks, and consulting decks.

## Installation

In a deck's `package.json`:

```json
{
  "dependencies": {
    "slidev-theme-red-hat-deck": "file:../../theme"
  }
}
```

In `slides.md` frontmatter:

```yaml
---
theme: red-hat-deck
fonts:
  sans: Red Hat Text
  serif: Red Hat Display
  mono: JetBrains Mono
---
```

## Layouts

The theme registers 14 layouts. Use them via `layout:` in slide frontmatter.

| Layout | Use case | Required frontmatter |
|--------|----------|----------------------|
| `default` | Standard content slide. Left-aligned `h1` with red left-border accent. | None |
| `center` | Vertically and horizontally centred. Good for CTAs and key-takeaway lists. | None |
| `cover` | Full-bleed title/hero slide variant. | None |
| `section` | Section divider. Grey background, red left bar. `h1` = section number, `h2` = section title. | `class: section-header` |
| `intro` | Speaker bio. Photo in a circle left, name/title/bullets right. | `image: /speaker.png` |
| `quote` | Single external quote. `h1` = quote text (with quotation marks), `h2` = attribution. | None |
| `fact` | Big stat slide. `h1` = number, `h2` = supporting label. | None |
| `statement` | Single bold centred line. No body content. | None |
| `end` | Closing slide with links and CTA. | None |
| `two-cols` | Built-in two-column. `::right::` divider separates content. | None |
| `two-cols-header` | Shared header above two columns. Good for before/after. | None |
| `image` | Full-bleed image with text overlay at bottom. | `image: /path-or-url` |
| `image-left` | Photo left third, content right. | `image: /path-or-url` |
| `image-right` | Content left, photo right third. | `image: /path-or-url` |

### Section header pattern

Section dividers use both `layout` and `class`:

```yaml
---
layout: section
class: section-header
---

# Section 2
## Platform Hardening
```

## CSS tokens

The theme exposes shorthand aliases for use in inline styles and Markdown:

```css
--rh-red      /* #EE0000  — brand red */
--rh-blue     /* #0066CC  — links */
--rh-green    /* #5BA352  — success / healthy */
--rh-yellow   /* #F0AB00  — warning / AWS */
--rh-muted    /* #4D4D4D  — secondary text (light mode) */
--rh-surface  /* #E0E0E0  — surface / card background */
--rh-border   /* #C7C7C7  — subtle borders */
```

Use in slide Markdown via Tailwind bracket notation:

```html
<div class="text-[var(--rh-muted)]">Secondary text</div>
<div style="color: var(--rh-red)">Brand red</div>
```

Dark mode variants are defined automatically — all tokens flip to their on-dark equivalents when `colorSchema: dark` is set.

## Utility classes

| Class | Effect |
|-------|--------|
| `.cols-2` | Two-column CSS grid (1fr 1fr, 2rem gap) |
| `.cols-2.divided` | Same grid with a subtle vertical centre divider |
| `.rh-tag` | Red uppercase badge pill (e.g., "LIVE", "BETA") |
| `.rh-image-slide` | Flex wrapper for images embedded in default layout — fills height below title without overflowing |

## Typography hierarchy

| Markdown | Renders as |
|----------|-----------|
| `# Title` | Left-aligned h1, bold, Red Hat Display |
| `## Subtitle` | Red subheading |
| `### Section label` | Bold section label, smaller |
| `> blockquote` | Red left-bar callout |
| `` `code` `` | JetBrains Mono, monospaced inline |

## Fonts

The theme loads fonts via the `fonts:` frontmatter key (Slidev fetches from Google Fonts):

```yaml
fonts:
  sans: Red Hat Text
  serif: Red Hat Display
  mono: JetBrains Mono
```

## Companion addon

`slidev-addon-red-hat-components` provides auto-registered Vue components:

- `RhTwoColumn` — Named-slot two-column wrapper (preferred over built-in `two-cols` layout for Markdown-heavy columns)
- `RhTable` — Props-driven styled table
- `RhTimeline` — Horizontal milestone timeline
- `RhSpectrum` — Maturity / spectrum scale

See [`../addon/README.md`](../addon/README.md) for full component API.
