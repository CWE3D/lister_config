#!/bin/bash

# Make this script executable
chmod +x "$0"

# Function to display usage information
usage() {
    echo "Usage: $0 <directory>"
    echo "Extract thumbnails from gcode files in the specified directory and its subdirectories."
    exit 1
}

# Check if a directory argument is provided
if [ $# -ne 1 ]; then
    usage
fi

REPO_PATH="$1"

# Check if the provided path is a directory
if [ ! -d "$REPO_PATH" ]; then
    echo "Error: '$REPO_PATH' is not a valid directory."
    usage
fi

# Function to extract and decode base64 data
decode_base64() {
    local data="$1"
    echo "$data" | sed 's/ //g' | base64 -d
}

# Function to extract thumbnail of a specific size from a gcode file
extract_thumbnail() {
    local gcode_file="$1"
    local output_file="$2"
    local size="$3"

    # Extract and decode the thumbnail data
    local thumbnail_data=$(sed -n "/thumbnail begin ${size}/,/thumbnail end/p" "$gcode_file" |
                           sed '1d;$d' | sed 's/^; //' | tr -d '\n')

    if [ -n "$thumbnail_data" ]; then
        decode_base64 "$thumbnail_data" > "$output_file"
        echo "Extracted ${size} thumbnail: $output_file"
    else
        echo "No ${size} thumbnail found in $gcode_file"
    fi
}

# Function to process a single gcode file
process_file() {
    local file="$1"
    local dir=$(dirname "$file")
    local filename=$(basename "$file" .gcode)

    echo "Processing: $file"

    # Ensure .thumbs directory exists
    mkdir -p "$dir/.thumbs"

    # Extract thumbnails of different sizes
    local sizes=("32x32" "64x64" "640x480")
    for size in "${sizes[@]}"; do
        extract_thumbnail "$file" "$dir/.thumbs/${filename}-${size}.png" "${size}"
    done

    echo "Finished processing: $file"
    echo "------------------------"
}

echo "Starting multi-size thumbnail extraction from $REPO_PATH"
echo "This will include all subdirectories"

# Find and process all gcode files
find "$REPO_PATH" -type f -name "*.gcode" | while read -r file; do
    process_file "$file"
done

echo "Multi-size thumbnail extraction complete."