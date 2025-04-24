sudo pacman -S zsh fzf bat lsd locate

usermod --shell /usr/bin/zsh (user)

yay -S --noconfirm zsh-theme-powerlevel10k-git scrub zsh-autosuggestions zsh-syntax-highlighting

sudo mkdir /usr/share/zsh-sudo

sudo cp sudo.plugin.zsh /usr/share/zsh-sudo

usermod --shell /usr/bin/zsh root

sudo ln -s -f /home/(user)/.zshrc /root/.zshrc

