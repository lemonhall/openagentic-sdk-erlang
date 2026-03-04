# SVG Graphics Guide

SVG (Scalable Vector Graphics) is an XML-based format for creating vector graphics that scale without quality loss.

## Basic SVG Structure

```xml
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 300" width="400" height="300">
  <!-- SVG content here -->
</svg>
```

## Basic Shapes

### Rectangle

```xml
<rect x="10" y="10" width="200" height="100" fill="blue" stroke="black" stroke-width="2"/>
```

### Circle

```xml
<circle cx="200" cy="150" r="50" fill="red" stroke="black" stroke-width="2"/>
```

### Ellipse

```xml
<ellipse cx="200" cy="150" rx="100" ry="50" fill="green" stroke="black" stroke-width="2"/>
```

### Line

```xml
<line x1="10" y1="10" x2="300" y2="200" stroke="black" stroke-width="2"/>
```

### Polyline

```xml
<polyline points="10,10 20,20 30,10 40,20" fill="none" stroke="black" stroke-width="2"/>
```

### Polygon

```xml
<polygon points="100,10 40,198 190,78" fill="yellow" stroke="black" stroke-width="2"/>
```

### Text

```xml
<text x="50" y="50" font-size="24" fill="black">Hello SVG</text>
```

## Color and Styling

### Fill and Stroke

```xml
<rect x="10" y="10" width="100" height="100" fill="blue" stroke="black" stroke-width="3"/>
```

### Opacity

```xml
<rect x="10" y="10" width="100" height="100" fill="blue" opacity="0.5"/>
```

### Stroke Properties

```xml
<line x1="10" y1="50" x2="300" y2="50" stroke="black" stroke-width="2" stroke-dasharray="5,5"/>
```

## Transformations

### Translate

```xml
<g transform="translate(50, 50)">
  <rect x="0" y="0" width="100" height="100" fill="blue"/>
</g>
```

### Rotate

```xml
<g transform="rotate(45 200 150)">
  <rect x="150" y="100" width="100" height="100" fill="green"/>
</g>
```

### Scale

```xml
<g transform="scale(2, 1.5)">
  <circle cx="100" cy="100" r="50" fill="red"/>
</g>
```

### Skew

```xml
<g transform="skewX(20)">
  <rect x="50" y="50" width="100" height="100" fill="purple"/>
</g>
```

## Grouping

```xml
<g id="myGroup" fill="none" stroke="black" stroke-width="2">
  <line x1="10" y1="10" x2="50" y2="50"/>
  <line x1="50" y1="50" x2="100" y2="10"/>
</g>
```

## Paths

### Common Path Commands

- `M` - Move to
- `L` - Line to
- `C` - Cubic Bezier curve
- `Q` - Quadratic Bezier curve
- `A` - Elliptical arc
- `Z` - Close path

```xml
<path d="M 10 10 L 100 10 L 100 100 L 10 100 Z" fill="blue" stroke="black" stroke-width="2"/>
```

### Bezier Curve

```xml
<path d="M 10 50 Q 100 10 200 50" fill="none" stroke="black" stroke-width="2"/>
```

## Example: Simple Diagram

```xml
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 300" width="400" height="300">
  <!-- Background -->
  <rect x="0" y="0" width="400" height="300" fill="lightgray"/>
  
  <!-- Boxes -->
  <rect x="50" y="50" width="80" height="60" fill="lightblue" stroke="black" stroke-width="2"/>
  <text x="90" y="85" text-anchor="middle" font-size="12">Start</text>
  
  <!-- Arrow -->
  <line x1="130" y1="80" x2="180" y2="80" stroke="black" stroke-width="2" marker-end="url(#arrowhead)"/>
  
  <!-- Box -->
  <rect x="180" y="50" width="80" height="60" fill="lightgreen" stroke="black" stroke-width="2"/>
  <text x="220" y="85" text-anchor="middle" font-size="12">Process</text>
  
  <!-- Arrow marker -->
  <defs>
    <marker id="arrowhead" markerWidth="10" markerHeight="10" refX="9" refY="3" orient="auto">
      <polygon points="0 0, 10 3, 0 6" fill="black"/>
    </marker>
  </defs>
</svg>
```
