# ~/.profile: executed by the command interpreter for login shells.
# This file is not read by bash(1), if ~/.bash_profile or ~/.bash_login
# exists.
# see /usr/share/doc/bash/examples/startup-files for examples.
# the files are located in the bash-doc package.

# the default umask is set in /etc/profile; for setting the umask
# for ssh logins, install and configure the libpam-umask package.
#umask 022

# if running bash
if [ -n "$BASH_VERSION" ]; then
    # include .bashrc if it exists
    if [ -f "$HOME/.bashrc" ]; then
	. "$HOME/.bashrc"
    fi
fi

# set PATH so it includes user's private bin if it exists
if [ -d "$HOME/bin" ] ; then
    PATH="$HOME/bin:$PATH"
fi

# set PATH so it includes user's private bin if it exists
if [ -d "$HOME/.local/bin" ] ; then
    PATH="$HOME/.local/bin:$PATH"
fi

# Second entry is for the go installation, https://go.dev/doc/install,
# but the first entry is for go tools and utilities.
export PATH="$HOME/go/bin:/usr/local/go/bin:$PATH"

eval "$(fzf --bash)"

# See https://wiki.archlinux.org/title/Qt#Configuration_of_Qt_5/6_applications_under_environments_other_than_KDE_Plasma
export XDG_CURRENT_DESKTOP="KDE"
export QT_QPA_PLATFORMTHEME="qt6ct"
