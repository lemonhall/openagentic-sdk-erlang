# Mermaid Diagram Guide

Mermaid is a JavaScript-based diagramming and charting tool that uses a simple, markdown-inspired syntax.

## Flowchart

### Basic Syntax

```mermaid
graph TD
    A[Start] --> B{Decision}
    B -->|Yes| C[Process 1]
    B -->|No| D[Process 2]
    C --> E[End]
    D --> E
```

### Node Types

- `[Text]` - Rectangle
- `(Text)` - Rounded rectangle
- `{Text}` - Diamond (decision)
- `([Text])` - Stadium shape
- `[[Text]]` - Subroutine
- `[(Text)]` - Cylinder
- `(( Text ))` - Circle

## Sequence Diagram

```mermaid
sequenceDiagram
    participant User
    participant Server
    participant Database
    
    User->>Server: Request
    Server->>Database: Query
    Database-->>Server: Response
    Server-->>User: Result
```

## Class Diagram

```mermaid
classDiagram
    class Animal {
        +name: string
        +age: int
        +eat()
        +sleep()
    }
    
    class Dog {
        +bark()
    }
    
    Animal <|-- Dog
```

## State Diagram

```mermaid
stateDiagram
    [*] --> Idle
    Idle --> Processing: trigger
    Processing --> Idle: complete
    Processing --> Error: failure
    Error --> Idle: retry
    Idle --> [*]
```

## Entity-Relationship Diagram

```mermaid
erDiagram
    CUSTOMER ||--o{ ORDER : places
    ORDER ||--|{ LINE-ITEM : contains
    PRODUCT ||--o{ LINE-ITEM : contains
```

## Gantt Chart

```mermaid
gantt
    title Project Timeline
    dateFormat YYYY-MM-DD
    
    section Planning
    Design :des1, 2024-01-01, 30d
    Requirements :req1, 2024-01-01, 20d
    
    section Development
    Frontend :dev1, after des1, 60d
    Backend :dev2, after req1, 80d
```

## Common Patterns

### Decision Flow

```mermaid
graph TD
    A[Input] --> B{Valid?}
    B -->|No| C[Show Error]
    C --> D[Return]
    B -->|Yes| E[Process]
    E --> D
```

### Nested Subgraph

```mermaid
graph TD
    subgraph System
        A[Component A]
        B[Component B]
        A --> B
    end
    subgraph External
        C[Service]
    end
    B --> C
```
