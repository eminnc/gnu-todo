#!/usr/bin/env bash
set -uo pipefail

SETTINGS_FILE="$HOME/.reminder-settings"

# Ayarları yükle (jq olmadan)
load_settings() {
    if [[ ! -f "$SETTINGS_FILE" ]]; then
        cat > "$SETTINGS_FILE" << 'EOF'
DEFAULT_SOUND="Freedesktop Bell"
SOUND_VOLUME="100"
DEFAULT_DURATION="1"
DEFAULT_REPEAT="Yok"
DO_NOT_DISTURB="false"
EOF
    fi
    
    source "$SETTINGS_FILE"
}

# Ayarları kaydet (jq olmadan)
save_settings() {
    cat > "$SETTINGS_FILE" << EOF
DEFAULT_SOUND="$1"
SOUND_VOLUME="$2"
DEFAULT_DURATION="$3"
DEFAULT_REPEAT="$4"
DO_NOT_DISTURB="$5"
EOF
}

# Ayarları yükle
load_settings

# CB içeriklerini dinamik oluştur
REPEAT_OPTIONS="Yok!Günlük!Haftalık!Aylık"
SOUND_OPTIONS="Freedesktop Bell!Yaru Complete!Yaru Message!Yaru Bell!Freedesktop Complete!Freedesktop Message!Ses Yok"

# Varsayılan değeri başa al
if [[ "$DEFAULT_REPEAT" != "Yok" ]]; then
    REPEAT_OPTIONS="$DEFAULT_REPEAT!${REPEAT_OPTIONS//$DEFAULT_REPEAT!/}"
fi

if [[ "$DEFAULT_SOUND" != "Freedesktop Bell" ]]; then
    SOUND_OPTIONS="$DEFAULT_SOUND!${SOUND_OPTIONS//$DEFAULT_SOUND!/}"
fi

# Ayarlar formu - varsayılan değerlerle
RES=$(
yad --form --center --borders=12 --width=600 --title="Hatırlatma Ayarları" \
  --field="Varsayılan Ses":CB "$SOUND_OPTIONS" \
  --field="Ses Yüksekliği":SCL "$SOUND_VOLUME" \
  --field="Varsayılan Süre (dakika)":NUM "$DEFAULT_DURATION" \
  --field="Varsayılan Tekrar":CB "$REPEAT_OPTIONS" \
  --field="Do Not Disturb'de Çalışsın":CHK "$DO_NOT_DISTURB" \
  --field="Ses Test Et":BTN "$(dirname "$0")/test-sound.sh" \
  --separator="|"
) || exit 0

IFS='|' read -r SOUND VOLUME DURATION REPEAT DND TEST_BTN <<<"$RES"

# Varsayılan değerleri ayarla (eğer boşsa)
[[ -z "${SOUND// }" ]] && SOUND="$DEFAULT_SOUND"
[[ -z "${REPEAT// }" ]] && REPEAT="$DEFAULT_REPEAT"

# Ayarları kaydet
save_settings "$SOUND" "$VOLUME" "$DURATION" "$REPEAT" "$DND"

# Başarı mesajı
yad --info --title="Ayarlar" --text="Ayarlar kaydedildi!" --button="Tamam:0"