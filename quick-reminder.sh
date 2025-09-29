#!/usr/bin/env bash
set -uo pipefail

DB_FILE="$HOME/.reminders.db"
SETTINGS_FILE="$HOME/.reminder-settings"

# Veritabanı yoksa oluştur
if [[ ! -f "$DB_FILE" ]]; then
    sqlite3 "$DB_FILE" < "$(dirname "$0")/init_db.sql"
fi

# Ayarları yükle
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

# Ayarları yükle
load_settings

# CB içeriklerini dinamik oluştur
REPEAT_OPTIONS="Yok!Günlük!Haftalık!Aylık"
SOUND_OPTIONS="Freedesktop Bell!Ses Yok!Yaru Complete!Yaru Message!Yaru Bell!Freedesktop Complete!Freedesktop Message"

# Varsayılan değeri başa al
if [[ "$DEFAULT_REPEAT" != "Yok" ]]; then
    REPEAT_OPTIONS="$DEFAULT_REPEAT!${REPEAT_OPTIONS//$DEFAULT_REPEAT!/}"
fi

if [[ "$DEFAULT_SOUND" != "Freedesktop Bell" ]]; then
    SOUND_OPTIONS="$DEFAULT_SOUND!${SOUND_OPTIONS//$DEFAULT_SOUND!/}"
fi

# --- Form (yad) tek pencerede; varsayılanlar ayarlardan ---
RES=$(
yad --form --center --borders=12 --width=520 --title="Hızlı Hatırlatma" \
  --field="Başlık":TXT "" \
  --field="Kategori":CB "Genel!İş!Kişisel!Sağlık!Eğitim!Alışveriş!Diğer" \
  --field="Tarih":D "$(date +%Y-%m-%d)" \
  --field="Saat":T "$(date -d "+${DEFAULT_DURATION} minute" +%H:%M)" \
  --field="Tekrarlama":CB "$REPEAT_OPTIONS" \
  --field="Ses":CB "$SOUND_OPTIONS" \
  --tab-order="1,2,3,4,5,6" \
  --separator="|"
) || exit 0

IFS='|' read -r DESC CATEGORY DATE_IN TIME_IN REPEAT SOUND <<<"$RES"
[[ -z "${DESC// }" ]] && yad --image=dialog-error --text="Açıklama boş olamaz." && exit 1

# Varsayılan değerleri ayarla (eğer boşsa veya ilk seçenekse)
[[ -z "${CATEGORY// }" ]] && CATEGORY="Genel"
[[ -z "${REPEAT// }" ]] && REPEAT="$DEFAULT_REPEAT"
[[ -z "${SOUND// }" ]] && SOUND="$DEFAULT_SOUND"

# Eğer form ilk seçenekleri döndürdüyse varsayılanları kullan
[[ "$CATEGORY" == "Genel" ]] && CATEGORY="Genel"
[[ "$REPEAT" == "Yok" ]] && REPEAT="$DEFAULT_REPEAT"
[[ "$SOUND" == "Freedesktop Bell" ]] && SOUND="$DEFAULT_SOUND"

# Saniye yoksa :00 ekle (bazı yad sürümleri saniye vermez)
[[ "$TIME_IN" =~ ^[0-9]{2}:[0-9]{2}$ ]] && TIME_IN="${TIME_IN}:00"

# --- En az +60sn geleceğe zorla ---
if ! TARGET_EPOCH=$(date -d "${DATE_IN} ${TIME_IN}" +%s 2>/dev/null); then
  yad --image=dialog-error --text="Tarih/saat hatalı."
  exit 1
fi
NOW_EPOCH=$(date +%s)
MIN_FUTURE=$((NOW_EPOCH + 60))
(( TARGET_EPOCH < MIN_FUTURE )) && TARGET_EPOCH=$((NOW_EPOCH + 90))

# --- Ortam değişkenleri (Wayland/DBus için şart) ---
DISPLAY_VAL="${DISPLAY:-:0}"
XDG_RUNTIME_DIR_VAL="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
DBUS_VAL="${DBUS_SESSION_BUS_ADDRESS:-}"

# --- Ses bloğu - Seçilen ses ---
PLAY_SOUND_SNIPPET=''
if [[ "$SOUND" != "Ses Yok" ]]; then
  case "$SOUND" in
    "Yaru Complete")
      PLAY_SOUND_SNIPPET='
if command -v paplay >/dev/null 2>&1 && [ -f /usr/share/sounds/Yaru/stereo/complete.oga ]; then
  paplay /usr/share/sounds/Yaru/stereo/complete.oga
elif command -v canberra-gtk-play >/dev/null 2>&1; then
  canberra-gtk-play -i complete
fi
'
      ;;
    "Yaru Message")
      PLAY_SOUND_SNIPPET='
if command -v paplay >/dev/null 2>&1 && [ -f /usr/share/sounds/Yaru/stereo/message.oga ]; then
  paplay /usr/share/sounds/Yaru/stereo/message.oga
elif command -v canberra-gtk-play >/dev/null 2>&1; then
  canberra-gtk-play -i message
fi
'
      ;;
    "Yaru Bell")
      PLAY_SOUND_SNIPPET='
if command -v paplay >/dev/null 2>&1 && [ -f /usr/share/sounds/Yaru/stereo/bell.oga ]; then
  paplay /usr/share/sounds/Yaru/stereo/bell.oga
elif command -v canberra-gtk-play >/dev/null 2>&1; then
  canberra-gtk-play -i bell
fi
'
      ;;
    "Freedesktop Complete")
      PLAY_SOUND_SNIPPET='
if command -v paplay >/dev/null 2>&1 && [ -f /usr/share/sounds/freedesktop/stereo/complete.oga ]; then
  paplay /usr/share/sounds/freedesktop/stereo/complete.oga
elif command -v canberra-gtk-play >/dev/null 2>&1; then
  canberra-gtk-play -i complete
fi
'
      ;;
    "Freedesktop Message")
      PLAY_SOUND_SNIPPET='
if command -v paplay >/dev/null 2>&1 && [ -f /usr/share/sounds/freedesktop/stereo/message.oga ]; then
  paplay /usr/share/sounds/freedesktop/stereo/message.oga
elif command -v canberra-gtk-play >/dev/null 2>&1; then
  canberra-gtk-play -i message
fi
'
      ;;
    "Freedesktop Bell")
      PLAY_SOUND_SNIPPET='
if command -v paplay >/dev/null 2>&1 && [ -f /usr/share/sounds/freedesktop/stereo/bell.oga ]; then
  paplay /usr/share/sounds/freedesktop/stereo/bell.oga
elif command -v canberra-gtk-play >/dev/null 2>&1; then
  canberra-gtk-play -i bell
fi
'
      ;;
  esac
fi

schedule_one() {
  local epoch="$1"
  local at_ts; at_ts=$(date -d "@$epoch" +%Y%m%d%H%M)

  # Job içeriği: export + notify + (opsiyonel ses)
  read -r -d '' JOB_SCRIPT <<EOF || true
export DISPLAY='${DISPLAY_VAL}'
export XDG_RUNTIME_DIR='${XDG_RUNTIME_DIR_VAL}'
${DBUS_VAL:+export DBUS_SESSION_BUS_ADDRESS='${DBUS_VAL}'}
notify-send -u normal -a 'Hatırlatma' '${DESC}'
${PLAY_SOUND_SNIPPET}
EOF

  JOB_LINE=$(printf "%s\n" "$JOB_SCRIPT" | at -t "$at_ts" 2>&1)
  echo "$JOB_LINE" | awk '/^job /{print $2; exit}'
}

# --- Tekrarlama: pratik olarak 12 ileri (gün/hafta/ay) planla ---
COUNT=1; STEP=""
case "$REPEAT" in
  "Günlük")   COUNT=12; STEP="1 day" ;;
  "Haftalık") COUNT=12; STEP="1 week" ;;
  "Aylık")    COUNT=12; STEP="1 month" ;;
esac

JOB_IDS=()
BASE_EPOCH="$TARGET_EPOCH"
for ((i=0; i<COUNT; i++)); do
  JOB_IDS+=("$(schedule_one "$BASE_EPOCH")")
        if [[ $COUNT -gt 1 ]]; then
            BASE_EPOCH=$(date -d "@$BASE_EPOCH + $STEP" +%s 2>/dev/null || date +%s)
            # Emniyet: her kurulan job en az +60sn gelecekte olsun
            NOW_EPOCH=$(date +%s)
            MIN_FUTURE=$((NOW_EPOCH + 60))
            (( BASE_EPOCH < MIN_FUTURE )) && BASE_EPOCH=$((NOW_EPOCH + 90))
        fi
done
JOBS_CSV=$(IFS=,; echo "${JOB_IDS[*]}")

# --- SQLite veritabanına kaydet ---
FINAL_DATE=$(date -d "@$TARGET_EPOCH" +%Y-%m-%d)
FINAL_TIME=$(date -d "@$TARGET_EPOCH" +%H:%M)
sqlite3 "$DB_FILE" "INSERT INTO reminders (date, time, repeat_type, description, category, jobs_csv) VALUES ('$FINAL_DATE', '$FINAL_TIME', '$REPEAT', '$DESC', '$CATEGORY', '$JOBS_CSV')"

# Test: Eğer şu anki tarih/saat/dakika ise hemen bildirim gönder (saniye yok)
CURRENT_DATE_TIME=$(date +%Y-%m-%d_%H:%M)
TARGET_DATE_TIME=$(date -d "@$TARGET_EPOCH" +%Y-%m-%d_%H:%M)
if [[ "$TARGET_DATE_TIME" == "$CURRENT_DATE_TIME" ]]; then
    # Do Not Disturb kontrolü
    if [[ "$DO_NOT_DISTURB" == "true" ]] || ! pgrep -f "do-not-disturb\|dnd" >/dev/null 2>&1; then
        notify-send -u normal -a 'Hatırlatma' "$DESC"
        if [[ "$SOUND" != "Ses Yok" ]]; then
        case "$SOUND" in
            "Yaru Complete")
                if command -v paplay >/dev/null 2>&1 && [ -f /usr/share/sounds/Yaru/stereo/complete.oga ]; then
                    paplay /usr/share/sounds/Yaru/stereo/complete.oga
                elif command -v canberra-gtk-play >/dev/null 2>&1; then
                    canberra-gtk-play -i complete
                fi
                ;;
            "Yaru Message")
                if command -v paplay >/dev/null 2>&1 && [ -f /usr/share/sounds/Yaru/stereo/message.oga ]; then
                    paplay /usr/share/sounds/Yaru/stereo/message.oga
                elif command -v canberra-gtk-play >/dev/null 2>&1; then
                    canberra-gtk-play -i message
                fi
                ;;
            "Yaru Bell")
                if command -v paplay >/dev/null 2>&1 && [ -f /usr/share/sounds/Yaru/stereo/bell.oga ]; then
                    paplay /usr/share/sounds/Yaru/stereo/bell.oga
                elif command -v canberra-gtk-play >/dev/null 2>&1; then
                    canberra-gtk-play -i bell
                fi
                ;;
            "Freedesktop Complete")
                if command -v paplay >/dev/null 2>&1 && [ -f /usr/share/sounds/freedesktop/stereo/complete.oga ]; then
                    paplay /usr/share/sounds/freedesktop/stereo/complete.oga
                elif command -v canberra-gtk-play >/dev/null 2>&1; then
                    canberra-gtk-play -i complete
                fi
                ;;
            "Freedesktop Message")
                if command -v paplay >/dev/null 2>&1 && [ -f /usr/share/sounds/freedesktop/stereo/message.oga ]; then
                    paplay /usr/share/sounds/freedesktop/stereo/message.oga
                elif command -v canberra-gtk-play >/dev/null 2>&1; then
                    canberra-gtk-play -i message
                fi
                ;;
            "Freedesktop Bell")
                if command -v paplay >/dev/null 2>&1 && [ -f /usr/share/sounds/freedesktop/stereo/bell.oga ]; then
                    paplay /usr/share/sounds/freedesktop/stereo/bell.oga
                elif command -v canberra-gtk-play >/dev/null 2>&1; then
                    canberra-gtk-play -i bell
                fi
                ;;
        esac
        fi
    fi
fi