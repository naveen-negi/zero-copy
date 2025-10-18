# AEP Zero-Copy Architecture Diagrams

This directory contains PlantUML diagrams for the three architecture options and decision flow.

## Diagrams

### Architecture Options

1. **[option1-federated-audience-composition.puml](option1-federated-audience-composition.puml)**
   - Federated Audience Composition (RECOMMENDED)
   - TRUE zero-copy architecture
   - Data stays in BigQuery, AEP queries in-place
   - 99.96% data reduction, $247K-$701K/year

2. **[option2-computed-attributes.puml](option2-computed-attributes.puml)**
   - Computed Attributes Pattern
   - Stream minimal profiles (5-10 fields) to AEP
   - Real-time capability (2-10 min latency)
   - 85-95% data reduction, $248K-$858K/year

3. **[option3-hybrid-selective.puml](option3-hybrid-selective.puml)**
   - Hybrid Selective Pattern
   - 99% Federated (batch) + 1% Streaming (real-time)
   - Best economics with real-time capability
   - 95-99% data reduction, $286K-$693K/year

### Decision Flow

4. **[decision-flow.puml](decision-flow.puml)**
   - Interactive decision tree
   - Guides you to the right option based on:
     - Batch vs real-time needs
     - % of use cases requiring <5 min latency
     - Customer AI/Attribution AI requirements
     - Cost vs simplicity preferences

## How to View/Render Diagrams

### Option 1: Online PlantUML Server
Visit: http://www.plantuml.com/plantuml/uml/

Paste the contents of any `.puml` file to render it online.

### Option 2: VS Code Extension
1. Install "PlantUML" extension in VS Code
2. Open any `.puml` file
3. Press `Alt+D` (or `Cmd+D` on Mac) to preview

### Option 3: Command Line
```bash
# Install PlantUML (requires Java)
brew install plantuml  # macOS
# or download from: https://plantuml.com/download

# Render diagrams to PNG
plantuml diagrams/*.puml

# Render to SVG (scalable)
plantuml -tsvg diagrams/*.puml
```

### Option 4: IntelliJ IDEA / WebStorm
1. Install "PlantUML integration" plugin
2. Open any `.puml` file
3. Diagrams render automatically in the editor

## Generated Images

After rendering, the following files will be created:
- `option1-federated-audience-composition.png` (or .svg)
- `option2-computed-attributes.png` (or .svg)
- `option3-hybrid-selective.png` (or .svg)
- `decision-flow.png` (or .svg)

**Note:** `.png` and `.svg` files are gitignored to avoid binary bloat. Render them locally as needed.

## Integration with Documents

These diagrams are referenced in:
- **[../aep-zero-copy-executive-summary.md](../aep-zero-copy-executive-summary.md)** - Executive decision guide with embedded ASCII versions
- **[../aep-zero-copy-architecture-options.md](../aep-zero-copy-architecture-options.md)** - Detailed technical implementation guide
- **[../gcp-zero-copy-architecture-options.md](../gcp-zero-copy-architecture-options.md)** - GCP-specific implementation guide

## Color Scheme

- **GCP Components**: Blue (#4285F4)
- **Adobe AEP Components**: Red (#FF0000)
- **Destinations**: Green (#34A853)
- **BigQuery**: Yellow (#FBBC04)
- **Batch Processing**: Blue (#4285F4)
- **Real-Time Processing**: Red (#EA4335)

## Customization

To customize diagrams:
1. Edit the `.puml` files
2. Re-render using any of the methods above
3. Colors and layout can be adjusted using PlantUML skinparam directives

## Questions?

Refer to the PlantUML documentation: https://plantuml.com/
