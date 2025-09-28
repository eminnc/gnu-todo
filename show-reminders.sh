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

# Ana döngü
while true; do
    # Hatırlatmaları listele
    ROWS=()
    while IFS='|' read -r id date time repeat_type description jobs_csv; do
        ROWS+=("$id" "$date" "$time" "$repeat_type" "$description")
    done < <(sqlite3 -separator '|' "$DB_FILE" "SELECT id, date, time, repeat_type, description FROM reminders ORDER BY date, time")

    # Veri yoksa bilgi ver
    if [[ ${#ROWS[@]} -eq 0 ]]; then
        yad --info --title="Hatırlatmalar" --text="Henüz kayıt yok."
        exit 0
    fi

    # Listeyi göster
    SEL=$(
    yad --list --center --width=900 --height=520 --borders=8 \
      --title="Kayıtlı Hatırlatmalar" \
      --column="ID" --column="Tarih" --column="Saat" --column="Tekrar" --column="Açıklama" \
      --separator=$'\t' --print-column=0 --no-click \
      --button="Sil:2" --button="Düzenle:3" --button="Ayarlar:4" --button="Kapat:1" \
      "${ROWS[@]}"
    )
    RC=$?
    [[ $RC -eq 1 || -z "${SEL}" ]] && exit 0

    # Seçimi ayrıştır
    IFS=$'\t' read -r SID SDATE STIME SREPEAT SDESC <<<"$SEL"

    # Orijinal veriyi al
    ORIGINAL=$(sqlite3 -separator '|' "$DB_FILE" "SELECT * FROM reminders WHERE id = $SID")
    [[ -z "$ORIGINAL" ]] && { yad --error --text="Kayıt bulunamadı."; continue; }

    IFS='|' read -r ID DATE TIME REPEAT_TYPE DESC JOBS_CSV CREATED_AT <<<"$ORIGINAL"

    if [[ $RC -eq 2 ]]; then
        # Sil
        IFS=',' read -ra ARR <<< "${JOBS_CSV:-}"
        for j in "${ARR[@]}"; do [[ -n "$j" ]] && atrm "$j" 2>/dev/null || true; done
        
        sqlite3 "$DB_FILE" "DELETE FROM reminders WHERE id = $SID"
        continue
    fi

    if [[ $RC -eq 3 ]]; then
        # Düzenle
        NEW=$(
        yad --form --center --borders=12 --width=520 --title="Hatırlatma Düzenle" \
            --field="Açıklama":TXT "$DESC" \
            --field="Tarih":D "$DATE" \
            --field="Saat":T "$TIME" \
            --field="Tekrarlama":C "Yok!Günlük!Haftalık!Aylık" \
            --field="Ses Çal":CHK TRUE \
            --separator="|"
        ) || continue

        IFS='|' read -r NDESC NDATE NTIME NREPEAT NSOUND <<<"$NEW"
        [[ -z "${NDESC// }" ]] && { yad --image=dialog-error --text="Açıklama boş olamaz."; continue; }
        [[ "$NTIME" =~ ^[0-9]{2}:[0-9]{2}$ ]] && NTIME="${NTIME}:00"

        # Eski job'ları iptal et
        IFS=',' read -ra ARR <<< "${JOBS_CSV:-}"
        for j in "${ARR[@]}"; do [[ -n "$j" ]] && atrm "$j" 2>/dev/null || true; done

        # Ortam değişkenleri
        DISPLAY_VAL="${DISPLAY:-:0}"
        XDG_RUNTIME_DIR_VAL="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
        DBUS_VAL="${DBUS_SESSION_BUS_ADDRESS:-}"

        # Ses bloğu - Ubuntu varsayılan sesi
        PLAY_SOUND_SNIPPET=''
        [[ "$NSOUND" == "TRUE" ]] && PLAY_SOUND_SNIPPET=$'
if command -v paplay >/dev/null 2>&1 && [ -f /usr/share/sounds/ubuntu/stereo/notification.ogg ]; then
  paplay /usr/share/sounds/ubuntu/stereo/notification.ogg
elif command -v canberra-gtk-play >/dev/null 2>&1; then
  canberra-gtk-play -i message
fi
'

        schedule_one() {
            local when_str="$1"
            local at_ts; at_ts=$(date -d "$when_str" +%Y%m%d%H%M)
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

        # En az +60sn geleceğe zorla ve tekrarlamayı uygula (12 ileri)
        COUNT=1; STEP=""
        case "$NREPEAT" in
            "Günlük")   COUNT=12; STEP="1 day" ;;
            "Haftalık") COUNT=12; STEP="1 week" ;;
            "Aylık")    COUNT=12; STEP="1 month" ;;
            *)          COUNT=1 ;;
        esac

        # başlangıç zamanı
        if ! BASE_EPOCH=$(date -d "$NDATE $NTIME" +%s 2>/dev/null); then
            yad --image=dialog-error --text="Tarih/saat hatalı."; continue
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
        sqlite3 "$DB_FILE" "UPDATE reminders SET date='$NDATE', time='$(date -d "$BASE_TS" +%H:%M)', repeat_type='$NREPEAT', description='$NDESC', jobs_csv='$JOBS_CSV' WHERE id=$SID"
        continue
    fi

    if [[ $RC -eq 4 ]]; then
        # Ayarlar
        "$(dirname "$0")/settings.sh"
        continue
    fi
done