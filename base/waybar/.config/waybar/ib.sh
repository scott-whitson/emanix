#!/bin/bash
# Waybar custom module: IB Gateway status. Outputs JSON.
# class drives CSS color (live=green, paper=yellow, both=cyan, down=dim).

live=0; paper=0
ss -tln 2>/dev/null | grep -q ':4001 ' && live=1
ss -tln 2>/dev/null | grep -q ':4002 ' && paper=1

if   (( live && paper )); then text="󰪥 LP"; class="both"
elif (( live ));           then text="󰪥 L";  class="live"
elif (( paper ));          then text="󰪥 P";  class="paper"
else                            text="󰧞";    class="down"
fi

printf '{"text":"%s","class":"%s","tooltip":"IB Gateway — live=%s paper=%s"}\n' \
       "$text" "$class" "$live" "$paper"
