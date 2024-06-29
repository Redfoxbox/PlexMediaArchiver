#!/bin/bash

# Plex server details
PLEX_HOST="http://localhost:32400"  # Set the appropriate host address
PLEX_TOKEN="YOUR_PLEX_TOKEN"  # Set the obtained Plex token

# Source and destination directories
SOURCE_DIR="/mnt/ssd"
DEST_DIR="/mnt/storage"

# List of excluded directories
EXCLUDE_DIRS=("tmp" "torrentfiles")

# Calculate the date one month ago
ONE_MONTH_AGO=$(date -d '1 month ago' +%s)

# Function to log start time
function log_start_time {
    echo "Script started at: $(date +"%Y-%m-%d %H:%M:%S")"
    echo "-------------------------------------"
}

# Function to check if a path is in the excluded directories
function is_excluded {
    local path=$1
    for exclude in "${EXCLUDE_DIRS[@]}"; do
        if [[ "$path" == ${SOURCE_DIR}/$exclude/* ]]; then
            return 0
        fi
    done
    return 1
}

# Function to move file to destination
function move_file {
    local path=$1
    if [[ "$path" == ${SOURCE_DIR}/* ]] && ! is_excluded "$path"; then
        dest_path="$DEST_DIR${path#${SOURCE_DIR}}"
        dest_dir=$(dirname "$dest_path")
        mkdir -p "$dest_dir"
        mv "$path" "$dest_path"
        echo "Moved $path to $dest_path"
        echo "-------------------------------------"
    fi
}

# Log start time
log_start_time

# Fetch all libraries
libraries=$(curl -s "${PLEX_HOST}/library/sections?X-Plex-Token=${PLEX_TOKEN}" | xmlstarlet sel -t -m "//Directory" -v "@key" -o ":" -v "@title" -o ":" -v "@type" -n)

# Print and move movies and TV show episodes added more than a month ago or watched
IFS=$'\n'
for library in $libraries; do
    library_id=$(echo "$library" | awk -F":" '{print $1}')
    library_name=$(echo "$library" | awk -F":" '{print $2}')
    library_type=$(echo "$library" | awk -F":" '{print $3}')
    echo "Checking library: $library_name"
    echo "-------------------------------------"

    if [ "$library_type" == "movie" ]; then
        # Fetch all movies in the library
        response=$(curl -s "${PLEX_HOST}/library/sections/${library_id}/all?X-Plex-Token=${PLEX_TOKEN}")

        # Process the XML response to get 'Video' elements
        movies=$(echo "$response" | xmlstarlet sel -t -m "//Video" -v "@title" -o " - " -v "Media/Part/@file" -o " - " -v "@addedAt" -o " - " -v "@viewCount" -n)

        # Print and move movies added more than a month ago or watched
        for entry in $movies; do
            title=$(echo "$entry" | awk -F" - " '{print $1}')
            path=$(echo "$entry" | awk -F" - " '{print $2}')
            addedAt=$(echo "$entry" | awk -F" - " '{print $3}')
            viewCount=$(echo "$entry" | awk -F" - " '{print $4}')

            # Check if addedAt is not empty and is a valid UNIX timestamp
            if [[ "$addedAt" =~ ^[0-9]+$ ]]; then
                addedAtEpoch=$(date -d @"$addedAt" +%s)

                # Check if viewCount is a valid integer
                if [[ -z "$viewCount" ]]; then
                    viewCount=0
                fi

                if [ "$addedAtEpoch" -lt "$ONE_MONTH_AGO" ] || [ "$viewCount" -gt 0 ]; then
                    move_file "$path"
                fi
            fi
        done
    elif [ "$library_type" == "show" ]; then
        # Fetch all shows in the library
        response=$(curl -s "${PLEX_HOST}/library/sections/${library_id}/all?X-Plex-Token=${PLEX_TOKEN}")

        # Process the XML response to get 'Directory' elements
        shows=$(echo "$response" | xmlstarlet sel -t -m "//Directory" -v "@key" -n)

        # Fetch seasons for each show
        for show_key in $shows; do
            seasons_response=$(curl -s "${PLEX_HOST}${show_key}?X-Plex-Token=${PLEX_TOKEN}")

            # Process the XML response to get 'Directory' elements for seasons
            seasons=$(echo "$seasons_response" | xmlstarlet sel -t -m "//Directory" -v "@key" -n)

            # Fetch episodes for each season
            for season_key in $seasons; do
                episodes_response=$(curl -s "${PLEX_HOST}${season_key}?X-Plex-Token=${PLEX_TOKEN}")

                # Process the XML response to get 'Episode' elements
                episodes=$(echo "$episodes_response" | xmlstarlet sel -t -m "//Video" -v "@title" -o " - " -v "Media/Part/@file" -o " - " -v "@addedAt" -o " - " -v "@viewCount" -n)

                # Print and move episodes added more than a month ago or watched
                for episode_entry in $episodes; do
                    episode_title=$(echo "$episode_entry" | awk -F" - " '{print $1}')
                    episode_path=$(echo "$episode_entry" | awk -F" - " '{print $2}')
                    episode_addedAt=$(echo "$episode_entry" | awk -F" - " '{print $3}')
                    episode_viewCount=$(echo "$episode_entry" | awk -F" - " '{print $4}')

                    # Check if addedAt is not empty and is a valid UNIX timestamp
                    if [[ "$episode_addedAt" =~ ^[0-9]+$ ]]; then
                        episode_addedAtEpoch=$(date -d @"$episode_addedAt" +%s)

                        # Check if episode_viewCount is a valid integer
                        if [[ -z "$episode_viewCount" ]]; then
                            episode_viewCount=0
                        fi

                        if [ "$episode_addedAtEpoch" -lt "$ONE_MONTH_AGO" ] || [ "$episode_viewCount" -gt 0 ]; then
                            move_file "$episode_path"
                        fi
                    fi
                done
            done
        done
    fi
done
