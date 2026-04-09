# vim:ft=zsh
#
# Compatibility shim: with the current integration model, kshr restores
# ZDOTDIR in .zshenv so this file should never be reached. If it is, restore
# ZDOTDIR and behave like vanilla zsh by sourcing the user's .zprofile.

if [[ -n "${GHOSTTY_ZSH_ZDOTDIR+X}" ]]; then
    builtin export ZDOTDIR="$GHOSTTY_ZSH_ZDOTDIR"
    builtin unset GHOSTTY_ZSH_ZDOTDIR
elif [[ -n "${KSHR_ZSH_ZDOTDIR+X}" ]]; then
    builtin export ZDOTDIR="$KSHR_ZSH_ZDOTDIR"
    builtin unset KSHR_ZSH_ZDOTDIR
else
    builtin unset ZDOTDIR
fi

builtin typeset _kshr_file="${ZDOTDIR-$HOME}/.zprofile"
[[ ! -r "$_kshr_file" ]] || builtin source -- "$_kshr_file"
builtin unset _kshr_file
