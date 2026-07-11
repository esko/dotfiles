# Completions for agy cli
complete -c agy -e

# Disable file completion by default
complete -c agy -f

# Global Options
complete -c agy -l add-dir -d 'Add a directory to the workspace (repeatable)' -r
complete -c agy -s c -l continue -d 'Continue the most recent conversation'
complete -c agy -l conversation -d 'Resume a previous conversation by ID' -x
complete -c agy -l dangerously-skip-permissions -d 'Auto-approve all tool permission requests without prompting'
complete -c agy -s i -l prompt-interactive -d 'Run an initial prompt interactively and continue the session'
complete -c agy -l log-file -d 'Override CLI log file path' -r
complete -c agy -l model -d 'Model for the current CLI session' -x -a '(agy models 2>/dev/null)'
complete -c agy -s p -l print -d 'Run a single prompt non-interactively and print the response'
complete -c agy -l print-timeout -d 'Timeout for print mode wait' -x
complete -c agy -l prompt -d 'Alias for --print'
complete -c agy -l sandbox -d 'Run in a sandbox with terminal restrictions enabled'

# Subcommands
set -l agy_subcommands changelog help install models plugin plugins update

complete -c agy -n "not __fish_seen_subcommand_from \$agy_subcommands" -a changelog -d 'Show changelog and release notes'
complete -c agy -n "not __fish_seen_subcommand_from \$agy_subcommands" -a help -d 'Show help for subcommands'
complete -c agy -n "not __fish_seen_subcommand_from \$agy_subcommands" -a install -d 'Configure environment paths and shell settings'
complete -c agy -n "not __fish_seen_subcommand_from \$agy_subcommands" -a models -d 'List available models'
complete -c agy -n "not __fish_seen_subcommand_from \$agy_subcommands" -a plugin -d 'Manage plugins'
complete -c agy -n "not __fish_seen_subcommand_from \$agy_subcommands" -a plugins -d 'Alias for plugin'
complete -c agy -n "not __fish_seen_subcommand_from \$agy_subcommands" -a update -d 'Update CLI'

# Plugin subcommands
set -l plugin_subcommands list import install uninstall enable disable validate link help

complete -c agy -n "__fish_seen_subcommand_from plugin plugins; and not __fish_seen_subcommand_from \$plugin_subcommands" -a list -d 'List imported plugins'
complete -c agy -n "__fish_seen_subcommand_from plugin plugins; and not __fish_seen_subcommand_from \$plugin_subcommands" -a import -d 'Import plugins from gemini or claude'
complete -c agy -n "__fish_seen_subcommand_from plugin plugins; and not __fish_seen_subcommand_from \$plugin_subcommands" -a install -d 'Install a plugin'
complete -c agy -n "__fish_seen_subcommand_from plugin plugins; and not __fish_seen_subcommand_from \$plugin_subcommands" -a uninstall -d 'Uninstall a plugin'
complete -c agy -n "__fish_seen_subcommand_from plugin plugins; and not __fish_seen_subcommand_from \$plugin_subcommands" -a enable -d 'Enable a plugin'
complete -c agy -n "__fish_seen_subcommand_from plugin plugins; and not __fish_seen_subcommand_from \$plugin_subcommands" -a disable -d 'Disable a plugin'
complete -c agy -n "__fish_seen_subcommand_from plugin plugins; and not __fish_seen_subcommand_from \$plugin_subcommands" -a validate -d 'Validate a plugin'
complete -c agy -n "__fish_seen_subcommand_from plugin plugins; and not __fish_seen_subcommand_from \$plugin_subcommands" -a link -d 'Generate link to a marketplace'
complete -c agy -n "__fish_seen_subcommand_from plugin plugins; and not __fish_seen_subcommand_from \$plugin_subcommands" -a help -d 'Show plugin help'

# Autocomplete plugin names for uninstall, enable, disable
complete -c agy -n "__fish_seen_subcommand_from plugin plugins; and __fish_seen_subcommand_from uninstall enable disable" -a "(agy plugin list 2>/dev/null | grep -o '\"name\": \"[^\"]*\"' | cut -d'\"' -f4)"
