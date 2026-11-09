#!/usr/bin/env bash

set -euo pipefail

# ---- DDC input source values (decimal) ------------------------------------
HP_MAC=17
HP_PC=15
MSI_MAC=16
MSI_PC=15

HP_NAME="HP E243"
MSI_NAME="MPG341CX OLED"

# ---- Tools ----------------------------------------------------------------
CLI="/Users/schampilomat/.local/bin/betterdisplaycli"   # free DDC features
DP="/opt/homebrew/bin/displayplacer"                     # free arrangement tool

# ---- displayplacer display IDs --------------------------------------------
# From `displayplacer list` (persistent IDs). If these change (rare, on replug),
# run `./switch.sh snapshot` and paste the EXTEND_ARGS block below.
BUILTIN_ID="37D8832A-2D66-02CA-B9F7-8F30A301B230"
MSI_ID="46109167-CB2C-44BE-8B67-0F74C993A9AE"
HP_ID="2F227DF6-02B6-48BA-BA00-222E94EF501D"

# Extended-mode (Mac) arrangement — this is the "normal desktop" layout.
EXTEND_ARGS=(
    "id:$BUILTIN_ID res:1512x982 hz:120 color_depth:8 enabled:true scaling:on origin:(0,0) degree:0"
    "id:$MSI_ID res:3440x1440 hz:240 color_depth:8 enabled:true scaling:off origin:(1920,-1440) degree:0"
    "id:$HP_ID res:1920x1080 hz:60 color_depth:8 enabled:true scaling:off origin:(0,-1080) degree:0"
)

# Mirrored-mode (PC) arrangement — mirror both externals into the built-in so
# windows migrate back and the cursor can't fly off into a dead area.
MIRROR_ARG="id:$BUILTIN_ID+$MSI_ID+$HP_ID res:1512x982 hz:120 color_depth:8 enabled:true scaling:on origin:(0,0) degree:0"
# ---------------------------------------------------------------------------

for tool in "$CLI" "$DP"; do
    [[ -x "$tool" ]] || { echo "$tool not found" >&2; exit 1; }
done

# BetterDisplay.app (free) must be running for the CLI; auto-launch if not.
if ! pgrep -qf "BetterDisplay.app"; then
    echo "Launching BetterDisplay..."
    open -g -a BetterDisplay
    for _ in $(seq 1 20); do
        if "$CLI" get --identifiers >/dev/null 2>&1; then break; fi
        sleep 0.5
    done
fi

target="${1:-toggle}"

if [[ "$target" == "snapshot" ]]; then
    echo "# Paste the IDs and EXTEND_ARGS from the command below into switch.sh"
    echo
    "$DP" list | tail -1
    exit 0
fi

if [[ "$target" == "toggle" ]]; then
    current=$("$CLI" get --name="$MSI_NAME" --feature=ddc --vcp=inputSelect 2>/dev/null | tr -d '[:space:]')
    echo "MSI current input: ${current:-unknown}"
    if [[ "$current" == "$MSI_MAC" ]]; then
        target=pc
    else
        target=mac
    fi
    echo "Toggling to: $target"
fi

case "$target" in
    pc)
        # Switch DDC inputs FIRST, while the Mac still drives the ports.
        echo "Switching HP E243 -> input $HP_PC"
        "$CLI" set --name="$HP_NAME" --vcp=inputSelect --ddc="$HP_PC"
        echo "Switching MSI MPG341CX -> input $MSI_PC"
        "$CLI" set --name="$MSI_NAME" --vcp=inputSelect --ddc="$MSI_PC"

        # Then mirror both externals into the built-in: windows migrate home,
        # cursor is contained, and the externals effectively "disappear" from
        # the Mac's desktop even though the GPU is still driving the ports.
        echo "Mirroring externals to built-in"
        "$DP" "$MIRROR_ARG"
        ;;
    mac)
        # Restore extended arrangement FIRST so the Mac is driving the ports
        # and DDC/CI is reliably reachable.
        echo "Restoring extended arrangement"
        "$DP" "${EXTEND_ARGS[@]}"
        sleep 1

        echo "Switching HP E243 -> input $HP_MAC"
        "$CLI" set --name="$HP_NAME" --vcp=inputSelect --ddc="$HP_MAC"
        echo "Switching MSI MPG341CX -> input $MSI_MAC"
        "$CLI" set --name="$MSI_NAME" --vcp=inputSelect --ddc="$MSI_MAC"
        ;;
    *)
        echo "usage: $0 [pc|mac|toggle|snapshot]" >&2
        exit 1
        ;;
esac

echo "Done."
