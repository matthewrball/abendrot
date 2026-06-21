#!/bin/bash

__abendrot_cursor_index_in_current_word() {
    local remaining="${COMP_LINE}"

    local word
    for word in "${COMP_WORDS[@]::COMP_CWORD}"; do
        remaining="${remaining##*([[:space:]])"${word}"*([[:space:]])}"
    done

    local -ir index="$((COMP_POINT - ${#COMP_LINE} + ${#remaining}))"
    if [[ "${index}" -le 0 ]]; then
        printf 0
    else
        printf %s "${index}"
    fi
}

# positional arguments:
#
# - 1: the current (sub)command's count of positional arguments
#
# required variables:
#
# - repeating_flags: the repeating flags that the current (sub)command can accept
# - non_repeating_flags: the non-repeating flags that the current (sub)command can accept
# - repeating_options: the repeating options that the current (sub)command can accept
# - non_repeating_options: the non-repeating options that the current (sub)command can accept
# - positional_number: value ignored
# - unparsed_words: unparsed words from the current command line
#
# modified variables:
#
# - non_repeating_flags: remove flags for this (sub)command that are already on the command line
# - non_repeating_options: remove options for this (sub)command that are already on the command line
# - positional_number: set to the current positional number
# - unparsed_words: remove all flags, options, and option values for this (sub)command
__abendrot_offer_flags_options() {
    local -ir positional_count="${1}"
    positional_number=0

    local was_flag_option_terminator_seen=false
    local is_parsing_option_value=false

    local -ar unparsed_word_indices=("${!unparsed_words[@]}")
    local -i word_index
    for word_index in "${unparsed_word_indices[@]}"; do
        if "${is_parsing_option_value}"; then
            # This word is an option value:
            # Reset marker for next word iff not currently the last word
            [[ "${word_index}" -ne "${unparsed_word_indices[${#unparsed_word_indices[@]} - 1]}" ]] && is_parsing_option_value=false
            unset "unparsed_words[${word_index}]"
            # Do not process this word as a flag or an option
            continue
        fi

        local word="${unparsed_words["${word_index}"]}"
        if ! "${was_flag_option_terminator_seen}"; then
            case "${word}" in
            --)
                unset "unparsed_words[${word_index}]"
                # by itself -- is a flag/option terminator, but if it is the last word, it is the start of a completion
                if [[ "${word_index}" -ne "${unparsed_word_indices[${#unparsed_word_indices[@]} - 1]}" ]]; then
                    was_flag_option_terminator_seen=true
                fi
                continue
                ;;
            -*)
                # ${word} is a flag or an option
                # If ${word} is an option, mark that the next word to be parsed is an option value
                local option
                for option in "${repeating_options[@]}" "${non_repeating_options[@]}"; do
                    [[ "${word}" = "${option}" ]] && is_parsing_option_value=true && break
                done

                # Remove ${word} from ${non_repeating_flags} or ${non_repeating_options} so it isn't offered again
                local not_found=true
                local -i index
                for index in "${!non_repeating_flags[@]}"; do
                    if [[ "${non_repeating_flags[${index}]}" = "${word}" ]]; then
                        unset "non_repeating_flags[${index}]"
                        non_repeating_flags=("${non_repeating_flags[@]}")
                        not_found=false
                        break
                    fi
                done
                if "${not_found}"; then
                    for index in "${!non_repeating_flags[@]}"; do
                        if [[ "${non_repeating_flags[${index}]}" = "${word}" ]]; then
                            unset "non_repeating_flags[${index}]"
                            non_repeating_flags=("${non_repeating_flags[@]}")
                            break
                        fi
                    done
                fi
                unset "unparsed_words[${word_index}]"
                continue
                ;;
            esac
        fi

        # ${word} is neither a flag, nor an option, nor an option value
        if [[ "${positional_number}" -lt "${positional_count}" || "${positional_count}" -lt 0 ]]; then
            # ${word} is a positional
            ((positional_number++))
            unset "unparsed_words[${word_index}]"
        else
            if [[ -z "${word}" ]]; then
                # Could be completing a flag, option, or subcommand
                positional_number=-1
            else
                # ${word} is a subcommand or invalid, so stop processing this (sub)command
                positional_number=-2
            fi
            break
        fi
    done

    unparsed_words=("${unparsed_words[@]}")

    if\
        ! "${was_flag_option_terminator_seen}"\
        && ! "${is_parsing_option_value}"\
        && [[ ("${cur}" = -* && "${positional_number}" -ge 0) || "${positional_number}" -eq -1 ]]
    then
        COMPREPLY+=($(compgen -W "${repeating_flags[*]} ${non_repeating_flags[*]} ${repeating_options[*]} ${non_repeating_options[*]}" -- "${cur}"))
    fi
}

__abendrot_add_completions() {
    local completion
    while IFS='' read -r completion; do
        COMPREPLY+=("${completion}")
    done < <(IFS=$'\n' compgen "${@}" -- "${cur}")
}

__abendrot_custom_complete() {
    if [[ -n "${cur}" || -z ${COMP_WORDS[${COMP_CWORD}]} || "${COMP_LINE:${COMP_POINT}:1}" != ' ' ]]; then
        local -ar words=("${COMP_WORDS[@]}")
    else
        local -ar words=("${COMP_WORDS[@]::${COMP_CWORD}}" '' "${COMP_WORDS[@]:${COMP_CWORD}}")
    fi

    "${COMP_WORDS[0]}" "${@}" "${words[@]}"
}

_abendrot() {
    local state
    state="$(shopt -p;shopt -po)"
    trap "${state//$'\n'/;}" RETURN
    shopt -s extglob
    set +o history +o posix

    local -xr SAP_SHELL=bash
    local -x SAP_SHELL_VERSION
    SAP_SHELL_VERSION="$(IFS='.';printf %s "${BASH_VERSINFO[*]}")"
    local -r SAP_SHELL_VERSION

    local -r cur="${2}"
    local -r prev="${3}"

    local -i positional_number
    local -a unparsed_words=("${COMP_WORDS[@]:1:${COMP_CWORD}}")

    local -a repeating_flags=()
    local -a non_repeating_flags=(--version -h --help)
    local -a repeating_options=()
    local -a non_repeating_options=()
    __abendrot_offer_flags_options 0

    # Offer subcommand / subcommand argument completions
    local -r subcommand="${unparsed_words[0]}"
    unset 'unparsed_words[0]'
    unparsed_words=("${unparsed_words[@]}")
    case "${subcommand}" in
    status|get|on|off|cozy|set|exclude|reveal|help)
        # Offer subcommand argument completions
        "_abendrot_${subcommand}"
        ;;
    *)
        # Offer subcommand completions
        COMPREPLY+=($(compgen -W 'status get on off cozy set exclude reveal help' -- "${cur}"))
        ;;
    esac
}

_abendrot_status() {
    repeating_flags=()
    non_repeating_flags=(--json --version -h --help)
    repeating_options=()
    non_repeating_options=()
    __abendrot_offer_flags_options 0
}

_abendrot_get() {
    repeating_flags=()
    non_repeating_flags=(--json --version -h --help)
    repeating_options=()
    non_repeating_options=()
    __abendrot_offer_flags_options 1
}

_abendrot_on() {
    repeating_flags=()
    non_repeating_flags=(--json --version -h --help)
    repeating_options=()
    non_repeating_options=()
    __abendrot_offer_flags_options 0
}

_abendrot_off() {
    repeating_flags=()
    non_repeating_flags=(--json --version -h --help)
    repeating_options=()
    non_repeating_options=()
    __abendrot_offer_flags_options 0
}

_abendrot_cozy() {
    repeating_flags=()
    non_repeating_flags=(--json --version -h --help)
    repeating_options=()
    non_repeating_options=()
    __abendrot_offer_flags_options 1

    # Offer the on|off positional value completions. positional_number is -1 when ${cur} is empty
    # (could be the positional) and 1 when a partial first positional has been typed; offer on|off in
    # both cases, but never when ${cur} is a flag (then only flags/options above are relevant).
    if [[ "${cur}" != -* && ( "${positional_number}" -eq 1 || "${positional_number}" -eq -1 ) ]]; then
        COMPREPLY+=($(compgen -W 'on off' -- "${cur}"))
    fi
}

_abendrot_set() {
    repeating_flags=()
    non_repeating_flags=(--version -h --help)
    repeating_options=()
    non_repeating_options=()
    __abendrot_offer_flags_options 0

    # Offer subcommand / subcommand argument completions
    local -r subcommand="${unparsed_words[0]}"
    unset 'unparsed_words[0]'
    unparsed_words=("${unparsed_words[@]}")
    case "${subcommand}" in
    warmth|mode|max-warmth|reveal-mode|location)
        # Offer subcommand argument completions
        "_abendrot_set_${subcommand}"
        ;;
    *)
        # Offer subcommand completions
        COMPREPLY+=($(compgen -W 'warmth mode max-warmth reveal-mode location' -- "${cur}"))
        ;;
    esac
}

_abendrot_set_warmth() {
    repeating_flags=()
    non_repeating_flags=(--json --version -h --help)
    repeating_options=()
    non_repeating_options=(--kelvin)
    __abendrot_offer_flags_options 1

    # Offer option value completions
    case "${prev}" in
    '--kelvin')
        return
        ;;
    esac
}

_abendrot_set_mode() {
    repeating_flags=()
    non_repeating_flags=(--json --version -h --help)
    repeating_options=()
    non_repeating_options=()
    __abendrot_offer_flags_options 1
}

_abendrot_set_max-warmth() {
    repeating_flags=()
    non_repeating_flags=(--json --version -h --help)
    repeating_options=()
    non_repeating_options=()
    __abendrot_offer_flags_options 1
}

_abendrot_set_reveal-mode() {
    repeating_flags=()
    non_repeating_flags=(--json --version -h --help)
    repeating_options=()
    non_repeating_options=()
    __abendrot_offer_flags_options 1
}

_abendrot_set_location() {
    repeating_flags=()
    non_repeating_flags=(--auto --json --version -h --help)
    repeating_options=()
    non_repeating_options=()
    __abendrot_offer_flags_options 2
}

_abendrot_exclude() {
    repeating_flags=()
    non_repeating_flags=(--version -h --help)
    repeating_options=()
    non_repeating_options=()
    __abendrot_offer_flags_options 0

    # Offer subcommand / subcommand argument completions
    local -r subcommand="${unparsed_words[0]}"
    unset 'unparsed_words[0]'
    unparsed_words=("${unparsed_words[@]}")
    case "${subcommand}" in
    add|remove|list)
        # Offer subcommand argument completions
        "_abendrot_exclude_${subcommand}"
        ;;
    *)
        # Offer subcommand completions
        COMPREPLY+=($(compgen -W 'add remove list' -- "${cur}"))
        ;;
    esac
}

_abendrot_exclude_add() {
    repeating_flags=()
    non_repeating_flags=(--json --version -h --help)
    repeating_options=()
    non_repeating_options=()
    __abendrot_offer_flags_options 1
}

_abendrot_exclude_remove() {
    repeating_flags=()
    non_repeating_flags=(--json --version -h --help)
    repeating_options=()
    non_repeating_options=()
    __abendrot_offer_flags_options 1
}

_abendrot_exclude_list() {
    repeating_flags=()
    non_repeating_flags=(--json --version -h --help)
    repeating_options=()
    non_repeating_options=()
    __abendrot_offer_flags_options 0
}

_abendrot_reveal() {
    repeating_flags=()
    non_repeating_flags=(--json --version -h --help)
    repeating_options=()
    non_repeating_options=(--hold)
    __abendrot_offer_flags_options 0

    # Offer option value completions
    case "${prev}" in
    '--hold')
        return
        ;;
    esac
}

_abendrot_help() {
    repeating_flags=()
    non_repeating_flags=(--version)
    repeating_options=()
    non_repeating_options=()
    __abendrot_offer_flags_options -1
}

complete -o filenames -F _abendrot abendrot
