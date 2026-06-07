if status is-interactive
    # --- Safe File Management ---
    abbr -a rm 'rm -iv'
    abbr -a cp 'cp -riv'
    abbr -a mv 'mv -iv'
    abbr -a mkdir 'mkdir -p'

    # --- Tool Replacements ---
    abbr -a cat 'bat'
    abbr -a grep 'rg'
    abbr -a find 'fd'
    abbr -a lg 'lazygit'
    abbr -a vim 'micro' # Change to nvim if preferred

    # --- Eza (Modern ls) ---
    abbr -a ls 'eza --icons --group-directories-first'
    abbr -a ll 'eza --long --all --header --icons'
    abbr -a la 'eza --long --all --total-size --icons'
    abbr -a lt 'eza --tree --icons'

    # --- Folder Jumps ---
    abbr -a desk 'cd ~/Desktop'
    abbr -a docs 'cd ~/Documents'
    abbr -a dl 'cd ~/Downloads'
    abbr -a dev 'cd ~/dev'
    abbr -a conf 'cd ~/dotfiles'

    # --- System ---
    abbr -a reload 'exec fish'
    abbr -a q 'exit'
    abbr -a c 'clear'

    # --- Git Workflow ---
    abbr -a g 'git'
    abbr -a gs 'git status -s'
    abbr -a ga 'git add'
    abbr -a gaa 'git add --all'
    abbr -a gc 'git commit -m'
    abbr -a gca 'git commit --amend -m'
    abbr -a gco 'git checkout'
    abbr -a gb 'git branch'
    abbr -a gl 'git pull'
    abbr -a gp 'git push'
    abbr -a gd 'git diff'
    abbr -a glg 'git log --stat'
    abbr -a lh 'lefthook'
end
