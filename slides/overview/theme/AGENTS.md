# AGENTS.md - slidev-theme-red-hat-deck

Rules for AI agents using this theme. Read this before writing any slide content or frontmatter.

---

## What this theme provides

- 14 layouts (see table below)
- CSS tokens: `--rh-red`, `--rh-muted`, `--rh-surface`, `--rh-border`, `--rh-green`, `--rh-yellow`, `--rh-blue`
- Utility classes: `.cols-2`, `.cols-2.divided`, `.rh-tag`, `.rh-image-slide`
- Fonts: Red Hat Display (headings), Red Hat Text (body), JetBrains Mono (code)

---

## Layout selection guide

| Situation | Layout | Notes |
|-----------|--------|-------|
| Standard content slide | `default` (no frontmatter) | Most slides use this |
| Section landmark / divider | `layout: section` + `class: section-header` | Always pair both |
| CTA, closing, quote slide | `layout: center` | Add `class: text-center` if needed |
| Two content columns, Markdown-heavy | Use `<RhTwoColumn>` addon component in `default` layout | Preferred over built-in `two-cols` |
| Two columns with Mermaid diagram | `layout: two-cols` with `::right::` | Mermaid only works in plain slide Markdown, not slots |
| Before/after with shared title | `layout: two-cols-header` | |
| Speaker bio | `layout: intro` + `image: /speaker.png` | Photo is cropped to circle |
| Single external quote | `layout: quote` | `h1` = quote text (with quotation marks), `h2` = attribution |
| Big stat or number | `layout: fact` | `h1` = number, `h2` = label. Cite the source. |
| Single bold thesis | `layout: statement` | One line, no body content |
| Full-bleed image | `layout: image` + `image: /path` | Keep text minimal |
| Image + content | `layout: image-left` or `image-right` + `image: /path` | Image path in frontmatter, not inline |
| Closing / thank you | `layout: end` | Links and CTA only |

---

## Section header pattern

Section dividers require both `layout` AND `class`:

```yaml
---
layout: section
class: section-header
---

# Section 2
## Platform Hardening
```

Do not use `layout: section` without `class: section-header` - the red bar accent will be missing.

---

## CSS tokens - when and how to use them

Tokens are safe to use in:
- Inline styles in `slides.md`: `style="color: var(--rh-red)"`
- Tailwind bracket notation: `class="text-[var(--rh-muted)]"`
- `.vue` component files that are NOT animated diagram components

Do NOT use `var(--rh-*)` tokens in animated diagram components. Those components often render on dark canvas backgrounds where the light-mode token values produce low contrast. Use explicit RGBA values instead (see the animated components section in `template/AGENTS.md`).

**Token reference:**

| Token | Value (light) | Use |
|-------|--------------|-----|
| `--rh-red` | `#EE0000` | Brand, CTAs, highlights |
| `--rh-blue` | `#0066CC` | Links, info |
| `--rh-green` | `#5BA352` | Success, healthy state |
| `--rh-yellow` | `#F0AB00` | Warning, AWS layer |
| `--rh-muted` | `#4D4D4D` | Secondary text, captions |
| `--rh-surface` | `#E0E0E0` | Card/box backgrounds |
| `--rh-border` | `#C7C7C7` | Subtle borders |

---

## Typography rules

| Element | Brand rule |
|---------|-----------|
| Slide title (`#`) | One line max. If the title wraps, shorten it. |
| Section header titles | `# Section N` + `## Section Name` — two lines only |
| Bullets per column | 4-5 max. More than 5 means the slide should be split. |
| Blockquotes (`>`) | Rendered as red left-bar callout. Use for punchy single lines, not paragraphs. |
| `h2` inside a slide | Renders as a red subheading. Reserve for column headers and section labels. |

---

## RhTwoColumn usage

`RhTwoColumn` (from `slidev-addon-red-hat-components`) is the preferred two-column approach when both columns contain rich Markdown:

```md
<RhTwoColumn>
  <template #left>

  ### Left heading

  Content here. Markdown works: **bold**, lists, inline code.

  </template>
  <template #right>

  ### Right heading

  Right content.

  </template>
</RhTwoColumn>
```

**Critical:** leave a blank line after `<template #left>` (and `#right`) and before each closing `</template>`. Without it, Slidev treats the slot content as raw HTML, not Markdown.

Use the built-in `layout: two-cols` (with `::right::`) only when a Mermaid diagram appears in one of the columns.

---

## Image frontmatter

For `image-left`, `image-right`, `image`, and `intro` layouts, the image path goes in slide frontmatter, not inline:

```yaml
---
layout: image-left
image: /my-photo.jpg
---
```

Images in `public/` are served at `/filename`. Do not use absolute filesystem paths.

---

## Inline image pattern (default layout)

To embed an image below a title without overflow, use the `.rh-image-slide` wrapper:

```md
<div class="rh-image-slide">

Optional caption text.

<div class="rh-image-slide__figure">
<img src="/diagram.png" alt="Descriptive alt" />
</div>

</div>
```

Do not use `max-h-[Xvh]` on images - `vh` units are relative to the browser viewport, not the slide canvas, and cause overflow at small window sizes.

---

## Speaker notes

Every slide must have a speaker note in an HTML comment block:

```md
# My Slide

Slide content.

<!--
Speaker note: What to say here. What to emphasise.
-->
```

Notes appear in presenter view. Write them as speaking prompts (1-3 sentences), not full scripts.

---

## No em-dashes

Never write `—` (em-dash, U+2014) anywhere. Use a spaced hyphen ` - ` instead. This applies in Markdown content, speaker notes, Vue templates, YAML frontmatter, and everywhere else.

---

## Utility class reference

| Class | Effect |
|-------|--------|
| `.cols-2` | Two-column CSS grid, 1fr 1fr, 2rem gap |
| `.cols-2.divided` | Same grid with a visible vertical centre divider |
| `.rh-tag` | Red uppercase badge pill — inline use inside slide body |
| `.rh-image-slide` | Flex column wrapper for images in default layout |
| `.rh-image-slide__figure` | Inner figure container — centres the image |

Tailwind/UnoCSS utilities (`text-sm`, `mt-4`, `flex`, `items-center`, etc.) work freely on elements inside slides. For token-based values, use bracket notation: `text-[var(--rh-muted)]`.
