---
source: core
ported-from: https://github.com/Jeffallan/claude-skills/blob/main/skills/code-documenter/references/documentation-systems.md
ported-at: 2026-04-17
adapted: true
---

# Doc systems

Pick one. Resist the urge to introduce a second system "for the API docs" —
integrate them into the one you chose.

| System | Best for | Language | Notes |
|---|---|---|---|
| **MkDocs (Material)** | Python projects, small/medium docs | Python | `mkdocstrings` renders docstrings; Material theme is the de facto default. |
| **Docusaurus** | JS/TS projects, versioned product docs | Node | React-based, MDX, built-in versioning, blog. |
| **VitePress** | Lightweight JS/TS docs | Node | Vue-powered, fast, minimal. Less ecosystem than Docusaurus. |
| **Sphinx** | Large Python / scientific docs | Python | Powerful, verbose. Use if you need deep cross-referencing. |

## MkDocs (Material) — skeleton

```yaml
# mkdocs.yml
site_name: Orders Service
site_description: Orders, fulfillment, and payments.
theme:
  name: material
  features:
    - navigation.sections
    - navigation.tabs
    - content.code.copy
    - search.suggest
    - search.highlight
plugins:
  - search
  - mkdocstrings:
      handlers:
        python:
          options:
            docstring_style: google
            show_source: true
markdown_extensions:
  - admonition
  - pymdownx.details
  - pymdownx.superfences
  - pymdownx.snippets
nav:
  - Home: index.md
  - Getting started: getting-started.md
  - Guides:
      - Create an order: guides/create-order.md
  - Reference:
      - API: reference/api.md
      - Python: reference/python.md
  - Changelog: changelog.md
```

Render Python references automatically:

```markdown
# API reference

::: orders_service.domain.orders
    options:
      show_root_heading: true
      members_order: source
```

## Docusaurus — skeleton

```js
// docusaurus.config.js
module.exports = {
  title: "Orders Service",
  url: "https://docs.example.com",
  baseUrl: "/",
  presets: [
    [
      "classic",
      {
        docs: {
          sidebarPath: require.resolve("./sidebars.js"),
          editUrl: "https://github.com/example/docs/edit/main/",
        },
      },
    ],
  ],
  themeConfig: {
    navbar: {
      title: "Orders",
      items: [{ type: "docSidebar", sidebarId: "main", label: "Docs" }],
    },
  },
};
```

Versioning:

```bash
npx docusaurus docs:version 1.4
```

## VitePress — skeleton

```ts
// .vitepress/config.ts
export default defineConfig({
  title: "Orders Service",
  description: "Orders, fulfillment, and payments.",
  themeConfig: {
    nav: [
      { text: "Guide", link: "/guide/" },
      { text: "Reference", link: "/reference/" },
    ],
    sidebar: {
      "/guide/": [
        { text: "Getting started", link: "/guide/" },
        { text: "Create an order", link: "/guide/create-order" },
      ],
    },
  },
});
```

## Sphinx — skeleton

```python
# conf.py
project = "Orders Service"
extensions = [
    "sphinx.ext.autodoc",
    "sphinx.ext.napoleon",
    "sphinx.ext.viewcode",
    "myst_parser",
]
html_theme = "furo"
```

## Information architecture (any system)

Use the **Diátaxis** split — it keeps pages single-purpose:

- **Tutorials** — learning-oriented, "follow along and succeed" (Getting
  started, first API call).
- **How-to guides** — task-oriented, "I need to do X" (Create an order,
  Rotate keys).
- **Reference** — information-oriented, exhaustive (API reference,
  config options).
- **Explanation** — understanding-oriented, "why" (Architecture overview,
  pricing model).

Per page:

- One H1, clear H2/H3 hierarchy.
- A lead paragraph that states what the page covers in one sentence.
- Runnable examples (validate them).
- Links to adjacent pages.

## Search + feedback

- Enable full-text search (built-in for Material, Docusaurus, VitePress).
- Add an "Edit this page" link.
- Add a "Was this helpful?" widget for user-facing docs.

## Testing the docs

- Broken-link check in CI (`lychee`, `markdown-link-check`).
- Build the site in CI and fail on warnings (`mkdocs build --strict`,
  `docusaurus build`, `vitepress build`).
- For reference pages that pull in source docstrings/JSDoc, fail the build
  if symbol references are missing.

## Anti-patterns

- Two doc systems in one repo.
- Drift: hand-written reference pages that repeat generated reference.
- Pages longer than ~1 000 words — split into "overview" + "deep dive".
- Screenshots with no alt text.
- Copy-pasted code that doesn't actually compile in context.
