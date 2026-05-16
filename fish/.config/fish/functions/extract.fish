function extract -d "Extract any common archive format"
    if test -f $argv[1]
        switch $argv[1]
            case '*.tar.gz' '*.tgz'
                tar xzf $argv[1]
            case '*.tar.bz2' '*.tbz2'
                tar xjf $argv[1]
            case '*.tar.xz' '*.txz'
                tar xJf $argv[1]
            case '*.zip'
                unzip $argv[1]
            case '*.rar'
                unrar x $argv[1]
            case '*.7z'
                7z x $argv[1]
            case '*.tar'
                tar xf $argv[1]
            case '*.gz'
                gunzip $argv[1]
            case '*'
                echo "Error: '$argv[1]' cannot be extracted."
        end
    else
        echo "Error: '$argv[1]' is not a valid file."
    end
end
