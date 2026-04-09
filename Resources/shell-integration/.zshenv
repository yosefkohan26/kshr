# vim:ft=zsh
#
# kshr ZDOTDIR bootstrap for zsh.
#
# GhosttyKit already uses a ZDOTDIR injection mechanism for zsh (setting ZDOTDIR
# to Ghostty's integration dir). kshr also needs to run its integration, but
# we must restore the user's real ZDOTDIR immediately so that:
# - /etc/zshrc sets HISTFILE relative to the real ZDOTDIR/HOME (shared history)
# - zsh loads the user's real .zprofile/.zshrc normally (no wrapper recursion)
#
# We restore ZDOTDIR from (in priority order):
# - GHOSTTY_ZSH_ZDOTDIR (set by GhosttyKit when it overwrote ZDOTDIR)
# - KSHR_ZSH_ZDOTDIR (set by kshr when it overwrote a user-provided ZDOTDIR)
# - unset (zsh treats unset ZDOTDIR as $HOME)

if [[ -n "${GHOSTTY_ZSH_ZDOTDIR+X}" ]]; then
    builtin export ZDOTDIR="$GHOSTTY_ZSH_ZDOTDIR"
    builtin unset GHOSTTY_ZSH_ZDOTDIR
elif [[ -n "${KSHR_ZSH_ZDOTDIR+X}" ]]; then
    builtin export ZDOTDIR="$KSHR_ZSH_ZDOTDIR"
    builtin unset KSHR_ZSH_ZDOTDIR
else
    builtin unset ZDOTDIR
fi

{
    # zsh treats unset ZDOTDIR as if it were HOME. We do the same.
    builtin typeset _kshr_file="${ZDOTDIR-$HOME}/.zshenv"
    [[ ! -r "$_kshr_file" ]] || builtin source -- "$_kshr_file"
} always {
    if [[ -o interactive ]]; then
        # We overwrote GhosttyKit's injected ZDOTDIR, so manually load Ghostty's
        # zsh integration if available.
        #
        # We can't rely on GHOSTTY_ZSH_ZDOTDIR here because Ghostty's own zsh
        # bootstrap unsets it before chaining into this kshr wrapper.
        if [[ "${KSHR_LOAD_GHOSTTY_ZSH_INTEGRATION:-0}" == "1" ]]; then
            if [[ -n "${KSHR_SHELL_INTEGRATION_DIR:-}" ]]; then
                builtin typeset _kshr_ghostty="$KSHR_SHELL_INTEGRATION_DIR/ghostty-integration.zsh"
            fi
            if [[ ! -r "${_kshr_ghostty:-}" && -n "${GHOSTTY_RESOURCES_DIR:-}" ]]; then
                builtin typeset _kshr_ghostty="$GHOSTTY_RESOURCES_DIR/shell-integration/zsh/ghostty-integration"
            fi
            [[ -r "$_kshr_ghostty" ]] && builtin source -- "$_kshr_ghostty"
        fi

        # Load kshr integration (unless disabled)
        if [[ "${KSHR_SHELL_INTEGRATION:-1}" != "0" && -n "${KSHR_SHELL_INTEGRATION_DIR:-}" ]]; then
            builtin typeset _kshr_integ="$KSHR_SHELL_INTEGRATION_DIR/kshr-zsh-integration.zsh"
            [[ -r "$_kshr_integ" ]] && builtin source -- "$_kshr_integ"
        fi
    fi

    builtin unset _kshr_file _kshr_ghostty _kshr_integ
}
