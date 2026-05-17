
# Cargo
if [ -d "$HOME/.cargo/bin" ]
  set -gx PATH "$HOME/.cargo/bin" $PATH
end

# fnm
status is-interactive; or exit

set -gx FNM_PATH "$HOME/.local/share/fnm"
if [ -d "$FNM_PATH" ]
  set -gx PATH "$FNM_PATH" $PATH
end

if command -v fnm >/dev/null 2>&1
  fnm env --shell fish | source
end
