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

5. **[decision-tree-aep-options.puml](decision-tree-aep-options.puml)** ⭐ NEW
   - **Comprehensive decision tree for banking/regulated environments**
   - **Starts with critical security constraint**: Can you expose BigQuery to AEP?
   - Includes all 4 options (FAC, Computed Attributes, Hybrid, External Audiences)
   - Color-coded decision paths
   - **Interactive D3.js version**: [d3-diagrams/decision-tree-aep-options.html](d3-diagrams/decision-tree-aep-options.html)

## How to View Diagrams

### ⭐ Recommended: D3.js Interactive Diagrams (EASIEST)

**Open the interactive diagrams in your browser:**
```bash
open d3-diagrams/index.html
```

Or navigate to `diagrams/d3-diagrams/` and double-click `index.html`.

**Features:**
- ✅ No installation needed
- ✅ Interactive SVG graphics
- ✅ Works in any modern browser
- ✅ Professional quality

### Alternative: PlantUML (Backup)

#### Option 1: Online PlantUML Server
Visit: http://www.plantuml.com/plantuml/uml/

Paste the contents of any `.puml` file to render it online.

#### Option 2: VS Code Extension
1. Install "PlantUML" extension in VS Code
2. Open any `.puml` file
3. Press `Alt+D` (or `Cmd+D` on Mac) to preview

#### Option 3: Command Line
```bash
# Install PlantUML (requires Java)
brew install plantuml  # macOS
# or download from: https://plantuml.com/download

# Render diagrams to PNG
plantuml *.puml

# Render to SVG (scalable)
plantuml -tsvg *.puml
```

#### Option 4: IntelliJ IDEA / WebStorm
1. Install "PlantUML integration" plugin
2. Open any `.puml` file
3. Diagrams render automatically in the editor

## Directory Structure

```
diagrams/
├── d3-diagrams/              # ⭐ Interactive D3.js diagrams (RECOMMENDED)
│   ├── index.html           # Navigation page (START HERE)
│   ├── option1-federated.html
│   ├── option2-computed.html
│   ├── option3-hybrid.html
│   └── README.md
├── *.puml                    # PlantUML source files (backup)
├── test-diagrams.sh          # Validation script
└── README.md                 # This file
```

## Generated Images (PlantUML)

After rendering PlantUML files, the following will be created:
- `option1-federated-audience-composition.png` (or .svg)
- `option2-computed-attributes.png` (or .svg)
- `option3-hybrid-selective.png` (or .svg)
- `decision-flow.png` (or .svg)
- `decision-tree-aep-options.png` (or .svg) ⭐ NEW

**Note:** `.png` and `.svg` files are gitignored to avoid binary bloat. Render them locally as needed.

**To generate the decision tree visuals:**
```bash
plantuml -tsvg decision-tree-aep-options.puml
plantuml -tpng decision-tree-aep-options.puml
```

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
