# slidev-addon-red-hat-components

Opinionated Red Hat branded Vue components for Slidev presentations.

## Installation

```bash
npm install slidev-addon-red-hat-components slidev-theme-red-hat-deck
```

In your `slides.md` frontmatter:

```yaml
---
theme: red-hat-deck
addons:
  - slidev-addon-red-hat-components
---
```

## Components

All components use Red Hat design tokens (`--rh-*` CSS variables) from the theme. They're auto-registered—just use them directly in your slides.

### RhTwoColumn

Two-column layout wrapper using named slots.

**Props:** None

**Slots:**
- `#left` — Left column content
- `#right` — Right column content

**Example:**

```vue
<RhTwoColumn>
  <template #left>

  Left content here (Markdown works).

  - Bullet 1
  - Bullet 2

  </template>
  <template #right>

  Right content here.

  Can include code blocks, images, etc.

  </template>
</RhTwoColumn>
```

**Note:** Leave a blank line after `<template #left>` and before `</template>` so Slidev parses the slot content as Markdown.

---

### RhTable

Props-driven HTML table with Red Hat styling.

**Props:**

- `headers` (Array, required) — Column header labels
  - Example: `["Feature", "Classic", "HCP"]`
- `rows` (Array, required) — Array of rows; each row is an array of cell values
  - Example: `[["Cost", "$X", "$Y"], ["Speed", "40 min", "10 min"]]`

**Example:**

```vue
<RhTable
  :headers="['Feature', 'Classic', 'HCP']"
  :rows="[
    ['Cost', 'High', 'Low'],
    ['Speed', '40 min', '10 min'],
    ['Complexity', 'High', 'Low'],
  ]"
/>
```

**Styling:**
- Header text is uppercase, Red Hat Display font, red accent
- Rows alternate background on hover
- Borders use `--rh-border` token

---

### RhTimeline

Horizontal milestone timeline with optional legend.

**Props:**

- `milestones` (Array, required) — Array of `{ date: string, label: string, color?: string }`
  - `color` defaults to `var(--rh-red)` if omitted
  - Use `\n` in label for line breaks
- `legend` (Array, optional) — Array of `{ color: string, label: string }` for the colour key below the timeline

**Example:**

```vue
<RhTimeline
  :milestones="[
    { date: 'Q1 2026', label: 'Design', color: '#73BCF7' },
    { date: 'Q2 2026', label: 'Development', color: '#EE0000' },
    { date: 'Q3 2026', label: 'Launch', color: '#5BA352' },
  ]"
  :legend="[
    { color: '#73BCF7', label: 'Planning' },
    { color: '#EE0000', label: 'Execution' },
    { color: '#5BA352', label: 'Release' },
  ]"
/>
```

**Styling:**
- Timeline nodes are 6px circles
- Labels and dates are small, muted colour
- Legend sits below with colour swatches

---

### RhSpectrum

Horizontal spectrum/maturity scale. Highlights the active stage in red.

**Props:**

- `stages` (Array, required) — Array of `{ label: string, icon?: string, active?: boolean }`
  - `icon` is an emoji or text symbol (optional)
  - `active: true` highlights the stage in red and white
  - Use `\n` in label for line breaks
- `leftLabel` (String, default: `"← basic"`) — Left end of scale
- `rightLabel` (String, default: `"advanced →"`) — Right end of scale

**Example:**

```vue
<RhSpectrum
  :stages="[
    { label: 'Autocomplete', icon: '⌨️' },
    { label: 'Chat', icon: '💬' },
    { label: 'Agent', icon: '🔧', active: true },
    { label: 'Partner', icon: '🤝' },
  ]"
  left-label="← basic"
  right-label="advanced →"
/>
```

**Styling:**
- Stages are flexbox cells with equal width
- Active stage: red background, white text, bold
- Inactive stages: surface background, muted text
- Rounded border around entire spectrum

---

## Customisation

Components use CSS variables from the theme. Override them globally in your deck:

```vue
<style global>
:root {
  --rh-red: #C41C1C;      /* Your custom red */
  --rh-surface: #333333;  /* Your custom surface */
}
</style>
```

Or scope within a component:

```vue
<style scoped>
:deep(.slidev-layout) {
  --rh-red: #C41C1C;
}
</style>
```

---

## Related

- **[slidev-theme-red-hat-deck](https://github.com/paulczar/slidev-theme-red-hat-deck)** — Theme providing styles and global configuration
- **[DECK_CREATION_SKILL](../DECK_CREATION_SKILL.md)** — Interview-driven deck creation workflow
