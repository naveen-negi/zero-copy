#!/bin/bash

# Test PlantUML Diagrams - Validation Script
# This script validates PlantUML syntax by checking for common errors

echo "Testing PlantUML Diagrams..."
echo "======================================"
echo ""

for file in *.puml; do
    if [ -f "$file" ]; then
        echo "Testing: $file"

        # Check for @startuml
        if ! grep -q "@startuml" "$file"; then
            echo "  ❌ ERROR: Missing @startuml tag"
        fi

        # Check for @enduml
        if ! grep -q "@enduml" "$file"; then
            echo "  ❌ ERROR: Missing @enduml tag"
        fi

        # Check for balanced braces
        open_braces=$(grep -o "{" "$file" | wc -l)
        close_braces=$(grep -o "}" "$file" | wc -l)
        if [ "$open_braces" -ne "$close_braces" ]; then
            echo "  ⚠️  WARNING: Unbalanced braces (${open_braces} open, ${close_braces} close)"
        fi

        # Basic validation passed
        if grep -q "@startuml" "$file" && grep -q "@enduml" "$file"; then
            echo "  ✅ Basic syntax validation passed"
        fi

        echo ""
    fi
done

echo "======================================"
echo "Validation complete!"
echo ""
echo "To render diagrams online:"
echo "1. Visit: http://www.plantuml.com/plantuml/uml/"
echo "2. Copy/paste contents of any .puml file"
echo "3. Click 'Submit' to render"
echo ""
echo "Or install PlantUML locally:"
echo "  brew install plantuml"
echo "  plantuml -tpng *.puml"
