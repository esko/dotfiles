# Check if the 'fisher' function exists
if not functions -q fisher
    echo "Installing Fisher and fetching plugins..."
    
    # Download Fisher
    curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source
    
    # Read the stowed fish_plugins file and install everything
    fisher update
    
    echo "Plugins installed!"
end
