---
name: drawing
description: This skill should be used when users want to create, edit, or generate visual diagrams, charts, and drawings. It supports ASCII art generation, diagram creation in various formats (Mermaid, PlantUML, SVG), and provides utilities for common drawing tasks.
license: Complete terms in LICENSE.txt
---

# Drawing Skill

This skill provides capabilities for creating and manipulating visual diagrams, drawings, and charts through various formats and tools.

## Purpose

To enable efficient generation and editing of visual content including:

- **Diagrams**: Flowcharts, sequence diagrams, architecture diagrams
- **Charts**: Bar charts, pie charts, line graphs
- **Drawings**: ASCII art, SVG graphics, technical drawings
- **Visualizations**: Network diagrams, entity-relationship diagrams, state machines

## When to Use This Skill

Use this skill when:

1. User requests diagram or chart generation (e.g., "Create a flowchart for...")
2. User asks for ASCII art or text-based drawings
3. User needs visual representation of data or processes
4. User wants to export drawings in various formats (SVG, PNG, etc.)
5. User needs to edit or modify existing visual content

## How to Use This Skill

### 1. Mermaid Diagrams

To create Mermaid diagrams, reference [references/mermaid-guide.md](references/mermaid-guide.md) for syntax and examples. Mermaid supports:

- Flowcharts
- Sequence diagrams
- Class diagrams
- State diagrams
- Entity-relationship diagrams
- Gantt charts

### 2. SVG Graphics

Create scalable vector graphics using SVG format. Reference [references/svg-guide.md](references/svg-guide.md) for SVG creation patterns and common shapes.

### 3. ASCII Art

To generate ASCII art, use the script at `scripts/ascii_art_generator.py` for programmatic ASCII art creation, or generate ASCII art directly in markdown format.

### 4. Chart Generation

For data visualization, reference [references/chart-guide.md](references/chart-guide.md) for creating charts using various formats and tools.

## Implementation Guidelines

When executing drawing-related tasks:

1. **Choose the right format** based on complexity and use case:
   - Simple diagrams → Mermaid
   - Custom graphics → SVG
   - Technical specifications → PlantUML
   - Text-based → ASCII Art

2. **Create inline content** by embedding diagrams directly in markdown or code blocks

3. **Provide multiple formats** when appropriate (e.g., both Mermaid code and potential visual output)

4. **Document the diagram** with clear titles and descriptions

5. **Test and validate** that diagrams render correctly in the target environment

## Bundled Resources

### Scripts

- `scripts/ascii_art_generator.py` - Generate ASCII art programmatically

### References

- `references/mermaid-guide.md` - Mermaid syntax and examples
- `references/svg-guide.md` - SVG creation patterns
- `references/chart-guide.md` - Chart generation techniques

### Assets

- `assets/templates/` - Drawing templates and boilerplate code
