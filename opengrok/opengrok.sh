#!/bin/bash

function opengrok_help() {
    cat << EOF
OpenGrok Docker Management Tool

USAGE:
    opengrok <path/to/source>                # Run default OpenGrok version
    opengrok -v <version> <path/to/source>   # Run specific version
    opengrok build <version>                 # Build specific version
    opengrok build ls                        # List all versions available for building
    opengrok -u <version>                    # Remove specific version container and image
    opengrok -u all                          # Remove all OpenGrok containers and images
    opengrok ls                              # List all built versions and default version
    opengrok set-default <version>           # Set default version
    opengrok -h, --help                      # Show this help message
EOF
}

# Function to get default version from config file
function get_default_version() {
    local config_file="$HOME/.config/opengrok/default_version"
    if [ -f "$config_file" ]; then
        cat "$config_file"
    else
        echo ""
    fi
}

# Function to set default version
function set_default_version() {
    local version=$1
    local config_file="$HOME/.config/opengrok/default_version"
    
    # Check if the version exists in docker images
    if ! docker images "opengrok:$version" | grep -q "opengrok"; then
        echo "Error: Version $version not found in available images. Build it first using: opengrok build $version"
        return 1
    fi
    
    echo "$version" > "$config_file"
    echo "Default version set to $version"
}

# Function to list available versions for building
function list_buildable_versions() {
    local opengrok_dir="$HOME/Tools/opengrok"
    if [ ! -d "$opengrok_dir" ]; then
        echo "Error: OpenGrok directory not found at $opengrok_dir"
        return 1
    fi

    echo "Available versions for building:"
    echo "------------------------------"
    
    # Find all opengrok-* directories and extract versions
    local found_versions=false
    for dir in "$opengrok_dir"/opengrok-*; do
        if [ -d "$dir" ]; then
            found_versions=true
            local version=$(basename "$dir" | sed 's/opengrok-//')
            # Check if this version is already built
            if docker images "opengrok:$version" | grep -q "opengrok"; then
                echo "  $version (already built)"
            else
                echo "  $version (not built)"
            fi
        fi
    done

    if [ "$found_versions" = false ]; then
        echo "  No versions found in $opengrok_dir"
        echo "  Directory structure should be: $opengrok_dir/opengrok-<version>"
    fi
}

function opengrok() {
    if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
        opengrok_help
        return 0
    fi

    case "$1" in
        "ls")
            echo "Built OpenGrok versions:"
            echo "------------------------"
            docker images | grep "opengrok" | awk '{printf "  %s\n", $2}'
            echo ""
            local default_version=$(get_default_version)
            if [ -n "$default_version" ]; then
                echo "Default version: $default_version"
            else
                echo "No default version set. Use 'opengrok set-default <version>' to set one."
            fi
            ;;

        "build")
            case "$2" in
                "ls")
                    list_buildable_versions
                    ;;
                "")
                    echo "Error: Please specify version to build or 'ls' to list available versions"
                    opengrok_help
                    return 1
                    ;;
                *)
                    local build_path="$HOME/Tools/opengrok/opengrok-$2"
                    if [ ! -d "$build_path" ]; then
                        echo "Error: Build directory does not exist: $build_path"
                        echo "Available versions:"
                        list_buildable_versions
                        return 1
                    fi
                    echo "Building OpenGrok version $2..."
                    docker build "$build_path" -t "opengrok:$2"
                    ;;
            esac
            ;;

        "set-default")
            if [ -z "$2" ]; then
                echo "Error: Please specify version to set as default"
                return 1
            fi
            set_default_version "$2"
            ;;

        "-v")
            if [ -z "$2" ] || [ -z "$3" ]; then
                echo "Error: Missing version or source path"
                opengrok_help
                return 1
            fi
            local src_path=$(realpath "$3")
            if [ ! -d "$src_path" ]; then
                echo "Error: Source directory does not exist: $src_path"
                return 1
            fi
            if ! docker images "opengrok:$2" | grep -q "opengrok"; then
                echo "Error: OpenGrok version $2 not found. Build it first using: opengrok build $2"
                return 1
            fi
            docker run -d -v "$src_path:/opengrok/src" -p 8080:8080 "opengrok:$2"
            ;;

        "-u")
            if [ -z "$2" ]; then
                echo "Error: Please specify version to remove or 'all'"
                opengrok_help
                return 1
            fi
            if [ "$2" = "all" ]; then
                echo "This will remove all OpenGrok containers and images. Are you sure? (y/n)"
                read -r confirm
                if [ "$confirm" = "y" ]; then
                    echo "Removing containers..."
                    docker ps -a | grep "opengrok" | awk '{print $1}' | xargs -r docker rm -f
                    echo "Removing images..."
                    docker images | grep "opengrok" | awk '{print $1":"$2}' | xargs -r docker rmi -f
                    rm -f "$HOME/.config/opengrok/default_version"
                    echo "All OpenGrok containers and images removed"
                else
                    echo "Operation cancelled"
                fi
            else
                echo "Removing containers for version $2..."
                docker ps -a | grep "opengrok:$2" | awk '{print $1}' | xargs -r docker rm -f
                echo "Removing image opengrok:$2..."
                docker rmi -f "opengrok:$2"
                local default_version=$(get_default_version)
                if [ "$default_version" = "$2" ]; then
                    rm -f "$HOME/.config/opengrok/default_version"
                    echo "Removed default version setting"
                fi
                echo "Removed OpenGrok containers and image for version $2"
            fi
            ;;

	    "stop")
            if [ -z "$2" ]; then
                echo "Stopping all running OpenGrok containers..."
                local containers=$(docker ps | grep "opengrok" | awk '{print $1}')
                if [ -z "$containers" ]; then
                    echo "No running OpenGrok containers found"
                    return 0
                fi
                docker ps | grep "opengrok" | awk '{print $1}' | xargs docker stop
                echo "All OpenGrok containers stopped"
            else
                echo "Stopping OpenGrok containers for version $2..."
                local containers=$(docker ps | grep "opengrok:$2" | awk '{print $1}')
                if [ -z "$containers" ]; then
                    echo "No running OpenGrok containers found for version $2"
                    return 0
                fi
                docker ps | grep "opengrok:$2" | awk '{print $1}' | xargs docker stop
                echo "OpenGrok containers for version $2 stopped"
            fi
            ;;

        *)
            if [[ "$1" == -* ]]; then
                echo "Error: Unknown option $1"
                opengrok_help
                return 1
            fi
            local src_path=$(realpath "$1")
            if [ ! -d "$src_path" ]; then
                echo "Error: Directory does not exist: $src_path"
                return 1
            fi
            
            local default_version=$(get_default_version)
            if [ -z "$default_version" ]; then
                echo "Error: No default version set. Please set one using 'opengrok set-default <version>' or specify version using -v option"
                return 1
            fi
            
            if ! docker images "opengrok:$default_version" | grep -q "opengrok"; then
                echo "Error: Default version $default_version not found. Build it first using: opengrok build $default_version"
                return 1
            fi
            
            echo "Using default version: $default_version"
            docker run -d -v "$src_path:/opengrok/src" -p 8080:8080 "opengrok:$default_version"
            ;;
    esac
}
