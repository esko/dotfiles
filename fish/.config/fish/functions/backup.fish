function backup -d "Create a timestamped backup of a file or folder"
    set timestamp (date +%Y%m%d_%H%M%S)
    set target $argv[1]
    
    if test -e $target
        cp -riv $target "{$target}_{$timestamp}.bak"
        echo "Created backup: {$target}_{$timestamp}.bak"
    else
        echo "File or directory '$target' does not exist."
    end
end
