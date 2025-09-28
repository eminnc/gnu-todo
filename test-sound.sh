#!/usr/bin/env bash

# Ses test fonksiyonu
test_sound() {
    local sound="$1"
    case "$sound" in
        "Freedesktop Bell")
            paplay /usr/share/sounds/freedesktop/stereo/bell.oga
            ;;
        "Yaru Complete")
            paplay /usr/share/sounds/Yaru/stereo/complete.oga
            ;;
        "Yaru Message")
            paplay /usr/share/sounds/Yaru/stereo/message.oga
            ;;
        "Yaru Bell")
            paplay /usr/share/sounds/Yaru/stereo/bell.oga
            ;;
        "Freedesktop Complete")
            paplay /usr/share/sounds/freedesktop/stereo/complete.oga
            ;;
        "Freedesktop Message")
            paplay /usr/share/sounds/freedesktop/stereo/message.oga
            ;;
    esac
}

# Ses seçimi
SOUND=$(
yad --form --center --borders=12 --width=400 --title="Ses Test" \
  --field="Ses Seç":C "Freedesktop Bell!Yaru Complete!Yaru Message!Yaru Bell!Freedesktop Complete!Freedesktop Message" \
  --button="Test Et:0" --button="İptal:1"
) || exit 0

IFS='|' read -r SELECTED_SOUND <<<"$SOUND"
test_sound "$SELECTED_SOUND"
