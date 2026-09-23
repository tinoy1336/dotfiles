export ZSH="/usr/share/oh-my-zsh"
export SHELL="/usr/bin/zsh"

ZSH_THEME="robbyrussell"

plugins=(git)

source "$ZSH/oh-my-zsh.sh"

export PATH="$HOME/.local/bin:$PATH"
export PATH="$PATH:/usr/lib/emscripten"
export PATH="$PATH:/snap/bin"

# kitty single-instance + kittens
alias kitty="kitty --single-instance"
alias ssh="kitten ssh"
