
# fnm
status is-interactive; or exit

set FNM_PATH "/home/esko/.local/share/fnm"
if [ -d "$FNM_PATH" ]
  set PATH "$FNM_PATH" $PATH
  fnm env --shell fish | source
end
