#!/usr/bin/env python3
"""
ASCII Art Generator - Create ASCII art programmatically
"""

def create_box(width, height, title=None):
    """Create a simple ASCII box."""
    lines = []
    
    # Top border
    top = "┌" + "─" * (width - 2) + "┐"
    lines.append(top)
    
    # Title if provided
    if title and len(title) < width - 2:
        padding = (width - len(title) - 2) // 2
        line = "│ " + " " * padding + title + " " * (width - len(title) - padding - 3) + "│"
        lines.append(line)
        # Add separator
        lines.append("├" + "─" * (width - 2) + "┤")
    
    # Middle rows
    for _ in range(max(1, height - 2 - (1 if title else 0))):
        lines.append("│" + " " * (width - 2) + "│")
    
    # Bottom border
    bottom = "└" + "─" * (width - 2) + "┘"
    lines.append(bottom)
    
    return "\n".join(lines)


def create_horizontal_bar(width, title, percentage):
    """Create a simple horizontal bar chart."""
    bar_width = width - len(title) - 5
    filled = int(bar_width * percentage / 100)
    
    bar = "█" * filled + "░" * (bar_width - filled)
    return f"{title} |{bar}| {percentage}%"


def create_arrow(length=10, direction="right"):
    """Create ASCII arrows."""
    arrows = {
        "right": "─" * length + "→",
        "left": "←" + "─" * length,
        "down": "↓" + "\n" * length,
        "up": "↑" + "\n" * length,
    }
    return arrows.get(direction, "")


def create_tree(items, indent=0):
    """Create a tree structure."""
    lines = []
    for i, item in enumerate(items):
        is_last = i == len(items) - 1
        prefix = "└── " if is_last else "├── "
        lines.append(" " * indent + prefix + item)
    return "\n".join(lines)


if __name__ == "__main__":
    # Example usage
    print("ASCII Box:")
    print(create_box(30, 5, "Title"))
    print()
    
    print("Bar Chart:")
    print(create_horizontal_bar(40, "Item A", 75))
    print(create_horizontal_bar(40, "Item B", 50))
    print(create_horizontal_bar(40, "Item C", 90))
    print()
    
    print("Tree Structure:")
    print(create_tree(["Item 1", "Item 2", "Item 3"]))
