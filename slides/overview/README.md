# mobb-deck-template

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A reusable Red Hat-themed [Slidev](https://sli.dev/) presentation template. Write slides in Markdown, use Vue components for reusable visuals, and deploy to GitHub Pages or any static host.

Built and maintained by the MOBB (Managed OpenShift Black Belt) team at Red Hat.

---

## Recommended workflow

There are two ways to use this template. Choose based on whether you have an existing project repo or are starting fresh.

### Option A  -  Existing project repo (talk about a real project)

This is the most common case. Your project already has a repo with code, docs, and context. You want to build a talk that draws from that material.

```bash
# 1. In your project repo, add a references/ directory to .gitignore
echo "references/" >> .gitignore

# 2. Create the references directory and clone the template into it
mkdir -p references
git clone https://github.com/paulczar/mobb-deck-template.git references/mobb-deck-template

# 3. Install deps inside the template (needed for the agent's build check)
cd references/mobb-deck-template && npm install && cd ../..

# 4. Paste the kickoff prompt into your AI agent
#    See references/mobb-deck-template/PROMPT.md  -  it targets slides/ as output
```

Your presentation ends up at `slides/`  -  tracked in your repo, separate from the template reference.

### Option B  -  Standalone presentation repo (new repo just for the talk)

Use this when the talk is not tied to a specific codebase, or when you want the deck to live in its own repo.

```bash
# 1. Create a new repo for the talk
mkdir my-talk && cd my-talk && git init

# 2. Add references/ to .gitignore and clone the template
echo "references/" >> .gitignore
mkdir -p references
git clone https://github.com/paulczar/mobb-deck-template.git references/mobb-deck-template

# 3. Install deps
cd references/mobb-deck-template && npm install && cd ../..

# 4. Paste the kickoff prompt into your AI agent
#    See references/mobb-deck-template/PROMPT.md  -  it targets the repo root as output
```

Your presentation ends up at the repo root (`slides.md`, `components/`, `styles/`, etc.).

### The kickoff prompt

`PROMPT.md` in this repo contains a ready-to-paste AI agent prompt that:

1. Points the agent at this template as read-only reference material
2. Asks it to study your project's README, ARCHITECTURE.md, KNOWLEDGE.md, and docs
3. Instructs it to map content to the right slide formats
4. Sets the output location (root or `slides/`)
5. Tells it to run a build and fix errors before declaring the draft ready

Edit the `← CHANGE THIS` lines in the prompt before pasting  -  audience, tone, talk length, and the one-sentence thesis are the most important inputs.

---

## Quick start (editing an existing deck)

```bash
git clone https://github.com/paulczar/mobb-deck-template.git my-talk
cd my-talk
make dev
```

Or without `make`:

```bash
npm install
npm run dev
```

The dev server opens at **http://localhost:3030**. Navigate to slide `N` at `/N` (e.g. `/3` for slide 3).

---

## Makefile targets

| Target | What it does |
|--------|-------------|
| `make dev` | Install deps and start the live-reload dev server |
| `make build` | Build a production static site to `dist/` |
| `make export` | Export slides to PDF |
| `make install` | Run `npm install` only |

### Deploying to GitHub Pages

Edit `package.json` to add `--base` to the build script, matching your repo path:

```json
"build": "slidev build slides.md --base /my-repo-name/"
```

Then configure GitHub Pages to serve from the `dist/` directory or use a GitHub Actions workflow.

---

## File map

```
mobb-deck-template/
├── slides.md              ← All slide content lives here
├── styles/
│   └── index.css          ← Red Hat palette, typography, layout helpers
├── components/
│   ├── RhTwoColumn.vue    ← Two-column layout component
│   ├── RhTable.vue        ← Data-driven table
│   ├── RhTimeline.vue     ← Horizontal milestone timeline
│   └── RhSpectrum.vue     ← Maturity / spectrum scale
└── public/
    └── (images and static assets served at /filename)
```

Edit `slides.md` for all content. Edit `styles/index.css` for theming. Add images to `public/` and reference them as `/your-image.png`.

---

## Slide format gallery

Each format is demonstrated in `slides.md`. Here is a one-line summary of each:

| # | Format | When to use |
|---|--------|-------------|
| 1 | **Title** | Opening card  -  deck title, subtitle, author byline |
| 2 | **Speaker intro** | Bio grid with avatar; works for 1–2 speakers or human + tool |
| 3 | **Agenda / overview** | Two-column: hook on the left, numbered outline on the right |
| 4 | **Section header** | Landmark between major sections; large red heading |
| 5 | **Two-column compare** | Contrast two options, before/after, or competing approaches |
| 6 | **Bullet list** | Standard content slide; 3–5 bullets + optional blockquote |
| 7 | **Code block** | Syntax-highlighted code with optional before/after pair |
| 8 | **Table** | Structured comparison across 3–4 columns |
| 9 | **Mermaid flowchart** | System diagrams, data flows, decision trees |
| 10 | **Mermaid state diagram** | Lifecycles, reconciliation loops, CI pipelines |
| 11 | **Image slide** | Full-height PNG/SVG from `public/` with caption |
| 12 | **Quote / stat callout** | Centred big number or memorable quote |
| 13 | **Spectrum scale** | Maturity curve; highlights where your subject sits |
| 14 | **Timeline** | Horizontal milestone view of a project or process |
| 15 | **Closing / CTA** | Centred final message + links |

---

## Component API

### `RhTwoColumn`

A two-column grid wrapper using named slots.

```md
<RhTwoColumn>
  <template #left>

  Left column content (Markdown works here)

  </template>
  <template #right>

  Right column content

  </template>
</RhTwoColumn>
```

> **Note:** Do not put Mermaid fenced code blocks inside `<RhTwoColumn>` slots  -  they will not render. Use Slidev's built-in `two-cols` layout with `::right::` instead, or keep diagrams outside the component.

---

### `RhTable`

A props-driven table with Red Hat styling.

```md
<RhTable
  :headers="['Column A', 'Column B', 'Column C']"
  :rows="[
    ['Row 1 A', 'Row 1 B', 'Row 1 C'],
    ['Row 2 A', 'Row 2 B', 'Row 2 C'],
  ]"
/>
```

| Prop | Type | Required | Description |
|------|------|----------|-------------|
| `headers` | `string[]` | Yes | Column header labels |
| `rows` | `string[][]` | Yes | 2D array of cell values (plain text) |

---

### `RhTimeline`

A horizontal milestone timeline with optional colour legend.

```md
<RhTimeline
  :milestones="[
    { date: 'Jan 1',  label: 'Kickoff',  color: '#73BCF7' },
    { date: 'Mar 31', label: 'Launch',   color: '#5BA352' },
  ]"
  :legend="[
    { color: '#73BCF7', label: 'Phase 1' },
    { color: '#5BA352', label: 'Phase 2' },
  ]"
/>
```

| Prop | Type | Required | Description |
|------|------|----------|-------------|
| `milestones` | `{ date: string, label: string, color?: string }[]` | Yes | Milestone list; `label` supports `\n` for line breaks; `color` defaults to `--rh-red` |
| `legend` | `{ color: string, label: string }[]` | No | Colour key rendered below the timeline |

---

### `RhSpectrum`

A horizontal maturity/spectrum scale with one highlighted active stage.

```md
<RhSpectrum
  :stages="[
    { label: 'Manual',    icon: '🖐️' },
    { label: 'Automated', icon: '⚙️', active: true },
  ]"
  left-label="← basic"
  right-label="advanced →"
/>
```

| Prop | Type | Required | Description |
|------|------|----------|-------------|
| `stages` | `{ label: string, icon?: string, active?: boolean }[]` | Yes | Stage list; `active: true` highlights the stage in red |
| `leftLabel` | `string` | No | Label for the left end of the scale (default: `← basic`) |
| `rightLabel` | `string` | No | Label for the right end (default: `advanced →`) |

---

## CSS variable reference

These variables are defined in `styles/index.css` and used throughout the theme.

| Variable | Value | Usage |
|----------|-------|-------|
| `--rh-red` | `#EE0000` | Primary accent, section headers, `.rh-tag` background |
| `--rh-bg` | `#1A1A1A` | Slide background |
| `--rh-surface` | `#242424` | Card / code block background |
| `--rh-border` | `#383838` | Dividers, table borders |
| `--rh-text` | `#F0F0F0` | Primary text |
| `--rh-muted` | `#A8A8A8` | Secondary text, captions |
| `--rh-blue` | `#73BCF7` | Links, secondary accent |
| `--rh-green` | `#5BA352` | Success states |
| `--rh-yellow` | `#F0AB00` | Warning states |

Use them in slides with inline `style=""` or Tailwind-style arbitrary values:

```md
<div style="color: var(--rh-red)">Red text</div>
<div class="text-[var(--rh-muted)]">Muted text</div>
```

---

## Customisation

### Rename the deck

Change `name` in `package.json` and `title` in the `slides.md` frontmatter.

### Use a different accent colour

Override `--rh-red` in `styles/index.css`:

```css
:root {
  --rh-red: #0066CC;  /* your brand colour */
}
```

The section headers, tag pills, h1 left-border, and active spectrum stage all pick up the change automatically.

### Change the fonts

Update the `fonts` block in `slides.md` frontmatter and the `@import` URL in `styles/index.css`:

```yaml
fonts:
  sans: Inter
  serif: Playfair Display
  mono: Fira Code
```

### Add a custom component

Create a `.vue` file in `components/`. Slidev auto-registers it by filename:

```
components/MyWidget.vue  →  <MyWidget /> in slides.md
```

See [AGENTS.md](AGENTS.md) for component authoring patterns.

### Add images

Drop any PNG, JPG, or SVG into `public/` and reference it as `/filename.ext`:

```md
<img src="/my-diagram.png" alt="Description" class="max-w-full object-contain" />
```

---

## Known Slidev gotchas

| Issue | Cause | Fix |
|-------|-------|-----|
| Mermaid renders as a raw code fence | Block is inside a Vue component slot | Move it to plain slide Markdown or use the built-in `two-cols` layout |
| Image overflows slide height | `max-h-[Xvh]` is relative to the browser viewport, not the Slidev canvas | Use the `.rh-image-slide` flex wrapper (see slide 11 example) |
| Goto (`g`) dialog list pokes into view | Slidev bug  -  dialog not hidden when closed | The `#slidev-goto-dialog` rule in `styles/index.css` patches this |
| `--base` breaks local dev | `build --base /repo-name/` only applies to the production build | Keep `--base` in the `build` script only, not `dev` |
| Edge labels with parens break Mermaid | `A -->|O(1) lookup| B`  -  parens parsed as node syntax | Wrap in quotes: `A -->|"O(1) lookup"| B` |
| `depends_on` on Terraform modules (if applicable) | Defers all data sources to apply-time | Pass outputs as inputs for implicit ordering instead |

---

## Turning your finished deck into its own git repo

If you built your slides in `slides/` of an existing project repo and want to publish the deck independently:

```bash
# Copy the slides directory to a new location
cp -r slides/ ~/my-talk && cd ~/my-talk

# Initialise a fresh repo (no parent history)
git init
git add .
git commit -m "Initial commit: my-talk"

# Push to your remote
git remote add origin https://github.com/your-org/my-talk.git
git push -u origin main
```

Update the `build --base` flag in `package.json` to match the new repo name for GitHub Pages hosting. Update any internal path references if you moved the directory.

---

## Contributing

Open a PR against this template with:
- New example slide formats that cover a genuinely different information type
- Component improvements with backward-compatible prop changes
- Bug fixes for layout or Slidev version compatibility

Run `make build` before submitting  -  a successful build confirms no broken imports or Mermaid parse errors.
