function mkcd -d "Create a directory and automatically cd into it"
    mkdir -p $argv[1]
    and cd $argv[1]
end
