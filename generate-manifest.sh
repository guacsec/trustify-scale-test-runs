#!/bin/bash

# Generate a manifest file listing all JSON reports
# This should be run after test reports are generated
# Respects exclusions listed in publish/excluded-reports.txt

cd "$(dirname "$0")" || exit 1

echo "Generating reports manifest..."

# Load exclusion list (filter out comments and empty lines)
EXCLUDED_FILE="publish/excluded-reports.txt"
EXCLUDED=()
if [ -f "$EXCLUDED_FILE" ]; then
    # Read excluded files into an array, stripping comments and whitespace
    # Compatible with older bash versions (macOS)
    while IFS= read -r line; do
        # Skip empty lines and comments
        if [ -n "$line" ] && [[ ! "$line" =~ ^[[:space:]]*# ]]; then
            # Strip inline comments and trim whitespace
            line=$(echo "$line" | sed 's/[[:space:]]*#.*//' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            if [ -n "$line" ]; then
                EXCLUDED+=("$line")
            fi
        fi
    done < "$EXCLUDED_FILE"
    echo "Loaded ${#EXCLUDED[@]} excluded report(s)"
else
    echo "No exclusion file found, including all reports"
fi

# Function to check if a filename is excluded
is_excluded() {
    local filename="$1"
    for excluded in "${EXCLUDED[@]}"; do
        if [ "$filename" = "$excluded" ]; then
            return 0  # true - is excluded
        fi
    done
    return 1  # false - not excluded
}

# Create manifest.json with list of all report files
echo "{" > publish/manifest.json
echo '  "reports": [' >> publish/manifest.json

# Find all JSON report files and format as JSON array
first=true
excluded_count=0
included_count=0

for file in publish/reports/report-*.json; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")

        # Check if this file is excluded
        if is_excluded "$filename"; then
            echo "  Skipping excluded: $filename"
            excluded_count=$((excluded_count + 1))
            continue
        fi

        if [ "$first" = true ]; then
            first=false
        else
            echo "," >> publish/manifest.json
        fi
        echo -n "    \"reports/$filename\"" >> publish/manifest.json
        included_count=$((included_count + 1))
    fi
done

echo "" >> publish/manifest.json
echo "  ]," >> publish/manifest.json
echo "  \"generated\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\"" >> publish/manifest.json
echo "}" >> publish/manifest.json

echo ""
echo "Manifest generated at publish/manifest.json"
echo "  Included: $included_count reports"
echo "  Excluded: $excluded_count reports"
