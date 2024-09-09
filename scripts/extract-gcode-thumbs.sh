#!/bin/bash
# Usage exaple:
#   ./extract-gcode-thumbs.sh /path/to/gcode/files

# Function to display usage information
    # Display usage information for the script.

    # Prints a usage message to the standard output, indicating the correct
    # usage format for the script, and exits with a status of 1.

    # Parameters:
    #   None

    # Returns:
    #   None
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

# Check if the directory is empty or contains no .gcode files
if [ -z "$(find "$REPO_PATH" -name '*.gcode' -print -quit)" ]; then
    echo "Error: No .gcode files found in '$REPO_PATH' or its subdirectories."
    exit 1
fi

# Function to extract and decode base64 data
decode_base64() {
    local data="$1"
    echo "$data" | sed 's/ //g' | base64 -d
}

# Function to extract thumbnail of a specific size from a gcode file
# Extracts a thumbnail of a specific size from a gcode file and decodes it.
# Parameters:
#   $1: The path to the gcode file.
#   $2: The output file path for the extracted thumbnail.
#   $3: The size of the thumbnail to extract.
# Returns:
#   0 if the thumbnail is successfully extracted, 1 otherwise.
extract_thumbnail() {
    local gcode_file="$1"
    local output_file="$2"
    local size="$3"

    # Extract and decode the thumbnail data
    local thumbnail_data
    thumbnail_data=$(sed -n "/thumbnail begin ${size}/,/thumbnail end/p" "$gcode_file" |
                     sed '1d;$d' | sed 's/^; //' | tr -d '\n')

    if [ -n "$thumbnail_data" ]; then
        decode_base64 "$thumbnail_data" > "$output_file"
        echo "Extracted ${size} thumbnail: $output_file"
        return 0
    else
        echo "No ${size} thumbnail found in $gcode_file"
        return 1
    fi
}

# Function to generate a 32x32 thumbnail from a larger one
# Generate a 32x32 thumbnail from a larger image file.
#
# Parameters:
#   $1 (input_file): The path to the input image file.
#   $2 (output_file): The path to the output thumbnail file.
#
# Return:
#   0 on success, 1 if the input file is not found.
generate_32x32_thumbnail() {
    local input_file="$1"
    local output_file="$2"

    if [ -f "$input_file" ]; then
        # Check if the 'magick' command is available
        if command -v magick &> /dev/null; then
            magick "$input_file" -resize 32x32 "$output_file"
        else
            # Fall back to 'convert' if 'magick' is not available
            convert "$input_file" -resize 32x32 "$output_file"
        fi
        echo "Generated 32x32 thumbnail: $output_file"
        return 0
    else
        echo "Source file for 32x32 generation not found: $input_file"
        return 1
    fi
}

# Function to process a single gcode file
# Process a single gcode file by extracting thumbnails of different sizes and generating a 32x32 thumbnail if needed.
#
# @param {string} file - The path to the gcode file.
# @return {void} This function does not return anything.
process_file() {
    local file="$1"
    local dir
    dir=$(dirname "$file")
    local filename
    filename=$(basename "$file" .gcode)

    echo "Processing: $file"

    # Ensure .thumbs directory exists
    mkdir -p "$dir/.thumbs"

    # Extract thumbnails of different sizes
    local sizes=("32x32" "64x64" "400x300" "640x480")
    local extracted_larger=false
    for size in "${sizes[@]}"; do
        if extract_thumbnail "$file" "$dir/.thumbs/${filename}-${size}.png" "${size}"; then
            if [ "$size" != "32x32" ]; then
                extracted_larger=true
                larger_thumb="$dir/.thumbs/${filename}-${size}.png"
            fi
        fi
    done

    # If 32x32 wasn't extracted but a larger thumbnail was, generate 32x32
    if [ ! -f "$dir/.thumbs/${filename}-32x32.png" ] && $extracted_larger; then
        generate_32x32_thumbnail "$larger_thumb" "$dir/.thumbs/${filename}-32x32.png"
    fi

    echo "Finished processing: $file"
    echo "------------------------"
}

echo "Starting multi-size thumbnail extraction from $REPO_PATH"
echo "This will include all subdirectories"

# Find and process all gcode files
file_count=0
while IFS= read -r -d '' file; do
    process_file "$file"
    ((file_count++))
done < <(find "$REPO_PATH" -type f -name "*.gcode" -print0)

if [ $file_count -eq 0 ]; then
    echo "No .gcode files were processed. Check if the files have the correct .gcode extension."
else
    echo "Processed $file_count .gcode file(s)."
fi

echo "Multi-size thumbnail extraction complete."