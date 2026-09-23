if status is-interactive
    if type -q fastfetch
        fastfetch
    end

    if type -q starship
        function starship_transient_prompt_func
            starship module character
        end
        function starship_transient_rprompt_func
            starship module custom.transient_time
        end
        starship init fish | source
    end
end
