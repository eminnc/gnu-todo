# Kral bu çok düzgün çalışmıyor. Eğer terminalden açarsan sorun yok ama yad ile açarsan sorun çıkıyor. Sebebi id gitmiyor.



#!/usr/bin/env bash
set -uo pipefail

# ID parametresi kontrolü
if [[ $# -eq 0 ]]; then
    echo "Kullanım: $0 <reminder_id>"
    exit 1
fi

REMINDER_ID="$1"
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

# Hatırlatmayı al
ORIGINAL=$(sqlite3 -separator '|' "$DB_FILE" "SELECT * FROM reminders WHERE id = $REMINDER_ID")
if [[ -z "$ORIGINAL" ]]; then
    yad --error --title="Hata" --text="Hatırlatma bulunamadı (ID: $REMINDER_ID)"
    exit 1
fi

IFS='|' read -r ID DATE TIME REPEAT_TYPE DESC CATEGORY JOBS_CSV CREATED_AT <<<"$ORIGINAL"

# Düzenleme formu
NEW=$(
yad --form --center --borders=12 --width=520 --title="Hatırlatma Düzenle" \
  --field="Başlık":TXT "$DESC" \
  --field="Kategori":CB "Genel!İş!Kişisel!Sağlık!Eğitim!Alışveriş!Diğer" \
  --field="Tarih":D "$DATE" \
  --field="Saat":T "$TIME" \
  --field="Tekrarlama":CB "Yok!Günlük!Haftalık!Aylık" \
  --separator="|"
) || exit 0

IFS='|' read -r NDESC NCATEGORY NDATE NTIME NREPEAT <<<"$NEW"
[[ -z "${NDESC// }" ]] && { yad --image=dialog-error --text="Açıklama boş olamaz."; exit 1; }

# Saniye yoksa :00 ekle
[[ "$NTIME" =~ ^[0-9]{2}:[0-9]{2}$ ]] && NTIME="${NTIME}:00"

# Eski job'ları iptal et
if [[ -n "${JOBS_CSV:-}" ]]; then
    IFS=',' read -ra ARR <<< "$JOBS_CSV"
    for j in "${ARR[@]}"; do [[ -n "$j" ]] && atrm "$j" 2>/dev/null || true; done
fi

# Ortam değişkenleri
DISPLAY_VAL="${DISPLAY:-:0}"
XDG_RUNTIME_DIR_VAL="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
DBUS_VAL="${DBUS_SESSION_BUS_ADDRESS:-}"

# Ses bloğu - Ubuntu varsayılan sesi
PLAY_SOUND_SNIPPET=''
PLAY_SOUND_SNIPPET=$'
if command -v paplay >/dev/null 2>&1 && [ -f /usr/share/sounds/ubuntu/stereo/notification.ogg ]; then
  paplay /usr/share/sounds/ubuntu/stereo/notification.ogg
elif command -v canberra-gtk-play >/dev/null 2>&1; then
  canberra-gtk-play -i message
fi
'

# Yeni job'ları oluştur
schedule_one() {
    local ts="$1"
    local at_ts; at_ts=$(date -d "$ts" +%Y%m%d%H%M)
    
    read -r -d '' JOB_SCRIPT <<EOF || true
export DISPLAY='${DISPLAY_VAL}'
export XDG_RUNTIME_DIR='${XDG_RUNTIME_DIR_VAL}'
${DBUS_VAL:+export DBUS_SESSION_BUS_ADDRESS='${DBUS_VAL}'}
notify-send -u normal -a 'Hatırlatma' '⏰ Hatırlatma' '${NDESC}'
${PLAY_SOUND_SNIPPET}
EOF
    JOB_LINE=$(printf "%s\n" "$JOB_SCRIPT" | at -t "$at_ts" 2>&1)
    echo "$JOB_LINE" | awk '/^job /{print $2; exit}'
}

# Tekrarlama ayarları
COUNT=1; STEP=""
case "$NREPEAT" in
    "Günlük")   COUNT=12; STEP="1 day" ;;
    "Haftalık") COUNT=12; STEP="1 week" ;;
    "Aylık")    COUNT=12; STEP="1 month" ;;
    *)          COUNT=1 ;;
esac

# Başlangıç zamanı
if ! BASE_EPOCH=$(date -d "$NDATE $NTIME" +%s 2>/dev/null); then
    yad --image=dialog-error --text="Tarih/saat hatalı."; exit 1
fi
NOW_EPOCH=$(date +%s); MIN_FUTURE=$((NOW_EPOCH + 60))
(( BASE_EPOCH < MIN_FUTURE )) && BASE_EPOCH=$((NOW_EPOCH + 90))
BASE_TS=$(date -d "@$BASE_EPOCH" "+%Y-%m-%d %H:%M")

JOB_IDS=()
for ((i=0; i<COUNT; i++)); do
    JOB_IDS+=("$(schedule_one "$BASE_TS")")
    if [[ $COUNT -gt 1 ]]; then
        BASE_TS=$(date -d "$BASE_TS + $STEP" "+%Y-%m-%d %H:%M")
        BE=$(date -d "$BASE_TS" +%s); NOW=$(date +%s)
        (( BE < NOW + 60 )) && BASE_TS=$(date -d "@$((NOW+90))" "+%Y-%m-%d %H:%M")
    fi
done
JOBS_CSV=$(IFS=,; echo "${JOB_IDS[*]}")

# Veritabanında güncelle
sqlite3 "$DB_FILE" "UPDATE reminders SET date='$NDATE', time='$(date -d "$BASE_TS" +%H:%M)', repeat_type='$NREPEAT', description='$NDESC', category='$NCATEGORY', jobs_csv='$JOBS_CSV' WHERE id=$REMINDER_ID"

# Başarı mesajı
yad --info --title="Düzenleme" --text="Hatırlatma başarıyla güncellendi!" --button="Tamam:0"
