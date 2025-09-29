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
    while IFS='|' read -r id date time repeat_type description category; do
        ROWS+=("$id" "$date" "$time" "$repeat_type" "$description" "$category")
    done < <(sqlite3 -separator '|' "$DB_FILE" "SELECT id, date, time, repeat_type, description, category FROM reminders ORDER BY date, time")

    # Veri yoksa bilgi ver
    if [[ ${#ROWS[@]} -eq 0 ]]; then
  yad --info --title="Hatırlatmalar" --text="Henüz kayıt yok."
  exit 0
fi

    # Listeyi göster
SEL=$(
    yad --list --center --width=1000 --height=520 --borders=8 \
  --title="Kayıtlı Hatırlatmalar" \
      --column="ID" --column="Tarih" --column="Saat" --column="Tekrar" --column="Açıklama" --column="Kategori" \
      --separator=$'\t' --no-click \
      --button="Sil:2" --button="Düzenle:3" --button="Filtrele:4" --button="Ayarlar:5" --button="Kapat:1" \
  "${ROWS[@]}"
)
    RC=$?
    # Sadece Kapat butonuna basıldığında çık
    [[ $RC -eq 1 ]] && exit 0

    # Seçim kontrolü (sadece Sil/Düzenle için)
    if [[ $RC -eq 2 || $RC -eq 3 ]]; then
        # Boş seçim kontrolü
        if [[ -z "$SEL" ]]; then
            if [[ $RC -eq 2 ]]; then
                yad --info --title="Silme" --text="Silmek için bir öğe seçin."
            else
                yad --info --title="Düzenleme" --text="Düzenlemek için bir öğe seçin."
            fi
            continue
        fi
        
        # Çoklu seçim kontrolü kaldırıldı (--multiple parametresi kaldırıldı)
        
        # SEL tüm satırı içeriyor, ID'yi parse et
        IFS=$'\t' read -r SID SDATE STIME SREPEAT SDESC SCATEGORY <<<"$SEL"
        
        # ID kontrolü
        if [[ -z "$SID" ]]; then
            yad --error --text="Geçersiz seçim."
            continue
        fi
        
        # Orijinal veriyi al
        ORIGINAL=$(sqlite3 -separator '|' "$DB_FILE" "SELECT * FROM reminders WHERE id = $SID")
        [[ -z "$ORIGINAL" ]] && { yad --error --text="Kayıt bulunamadı."; continue; }
        
        IFS='|' read -r ID DATE TIME REPEAT_TYPE DESC CATEGORY JOBS_CSV CREATED_AT <<<"$ORIGINAL"
    fi

    if [[ $RC -eq 2 ]]; then
        # Sil - tek seçim
        # ID'yi al ve delete-reminder.sh'a gönder
        # SID zaten parse edildi
        "$(dirname "$0")/delete-reminder.sh" "$SID"
        continue
    fi

    if [[ $RC -eq 3 ]]; then
        # Düzenle - seçim kontrolü
        if [[ -z "$SEL" ]]; then
            yad --info --title="Düzenleme" --text="Düzenlemek için bir öğe seçin."
            continue
        fi
        
        # Çoklu seçim kontrolü kaldırıldı (--multiple parametresi kaldırıldı)
        
        # ID'yi al ve edit-reminder.sh'a gönder
        # SID zaten parse edildi
        "$(dirname "$0")/edit-reminder.sh" "$SID"
        continue
    fi

    if [[ $RC -eq 5 ]]; then
        # Ayarlar - direkt settings.sh'a git
        "$(dirname "$0")/settings.sh"
        continue
    fi

    if [[ $RC -eq 4 ]]; then
        # Filtrele
        FILTER_RES=$(
        yad --form --center --borders=12 --width=400 --title="Filtrele" \
          --field="Tarih Aralığı":CB "Tümü!Bugün!Bu Hafta!Bu Ay!Geçmiş!Gelecek" \
          --field="Tekrar Türü":CB "Tümü!Yok!Günlük!Haftalık!Aylık" \
          --field="Kategori":CB "Tümü!Genel!İş!Kişisel!Sağlık!Eğitim!Alışveriş!Diğer" \
          --field="Açıklama İçeriği":TXT "" \
          --separator="|"
        )
        if [[ $? -eq 0 ]]; then
            IFS='|' read -r DATE_FILTER REPEAT_FILTER CATEGORY_FILTER DESC_FILTER <<< "$FILTER_RES"
            
            # Filtreleme sorgusu oluştur
            WHERE_CLAUSE=""
            
            # Tarih filtresi
            case "$DATE_FILTER" in
                "Bugün")
                    WHERE_CLAUSE="date = '$(date +%Y-%m-%d)'"
                    ;;
                "Bu Hafta")
                    WHERE_CLAUSE="date >= '$(date -d 'monday this week' +%Y-%m-%d)' AND date <= '$(date -d 'sunday this week' +%Y-%m-%d)'"
                    ;;
                "Bu Ay")
                    WHERE_CLAUSE="date >= '$(date +%Y-%m-01)' AND date <= '$(date -d 'last day of this month' +%Y-%m-%d)'"
                    ;;
                "Geçmiş")
                    WHERE_CLAUSE="date < '$(date +%Y-%m-%d)'"
                    ;;
                "Gelecek")
                    WHERE_CLAUSE="date > '$(date +%Y-%m-%d)'"
                    ;;
            esac
            
            # Tekrar filtresi
            if [[ "$REPEAT_FILTER" != "Tümü" ]]; then
                if [[ -n "$WHERE_CLAUSE" ]]; then
                    WHERE_CLAUSE="$WHERE_CLAUSE AND repeat_type = '$REPEAT_FILTER'"
                else
                    WHERE_CLAUSE="repeat_type = '$REPEAT_FILTER'"
                fi
            fi
            
            # Kategori filtresi
            if [[ "$CATEGORY_FILTER" != "Tümü" ]]; then
                if [[ -n "$WHERE_CLAUSE" ]]; then
                    WHERE_CLAUSE="$WHERE_CLAUSE AND category = '$CATEGORY_FILTER'"
                else
                    WHERE_CLAUSE="category = '$CATEGORY_FILTER'"
                fi
            fi
            
            # Açıklama filtresi
            if [[ -n "${DESC_FILTER// }" ]]; then
                if [[ -n "$WHERE_CLAUSE" ]]; then
                    WHERE_CLAUSE="$WHERE_CLAUSE AND description LIKE '%$DESC_FILTER%'"
                else
                    WHERE_CLAUSE="description LIKE '%$DESC_FILTER%'"
                fi
            fi
            
            # Filtrelenmiş listeyi göster
            FILTERED_ROWS=()
            QUERY="SELECT id, date, time, repeat_type, description, category FROM reminders"
            [[ -n "$WHERE_CLAUSE" ]] && QUERY="$QUERY WHERE $WHERE_CLAUSE"
            QUERY="$QUERY ORDER BY date, time"
            
            while IFS='|' read -r id date time repeat_type description category; do
                FILTERED_ROWS+=("$id" "$date" "$time" "$repeat_type" "$description" "$category")
            done < <(sqlite3 -separator '|' "$DB_FILE" "$QUERY")
            
            if [[ ${#FILTERED_ROWS[@]} -eq 0 ]]; then
                yad --info --title="Filtre Sonucu" --text="Filtre kriterlerine uygun kayıt bulunamadı."
                continue
            fi
            
            # Filtrelenmiş listeyi göster
            FILTERED_SEL=$(
            yad --list --center --width=1000 --height=520 --borders=8 \
              --title="Filtrelenmiş Hatırlatmalar" \
              --column="ID" --column="Tarih" --column="Saat" --column="Tekrar" --column="Açıklama" --column="Kategori" \
              --separator=$'\t' --print-column=0 --no-click \
              --button="Sil:2" --button="Düzenle:3" --button="Geri:1" \
              "${FILTERED_ROWS[@]}"
            )
            FILTERED_RC=$?
            
            if [[ $FILTERED_RC -eq 2 ]]; then
                # Sil
                IFS=$'\t' read -r FID FDATE FTIME FREPEAT FDESC FCATEGORY <<< "$FILTERED_SEL"
                ORIGINAL=$(sqlite3 -separator '|' "$DB_FILE" "SELECT * FROM reminders WHERE id = $FID")
                [[ -z "$ORIGINAL" ]] && { yad --error --text="Kayıt bulunamadı."; continue; }
                IFS='|' read -r ID DATE TIME REPEAT_TYPE DESC JOBS_CSV CREATED_AT <<< "$ORIGINAL"
                
                # at job'larını iptal et
                if [[ -n "$JOBS_CSV" ]]; then
                    IFS=',' read -ra JOBS <<< "$JOBS_CSV"
                    for job in "${JOBS[@]}"; do
                        [[ -n "$job" ]] && atrm "$job" 2>/dev/null || true
                    done
                fi
                
                # Veritabanından sil
                sqlite3 "$DB_FILE" "DELETE FROM reminders WHERE id = $FID"
                continue
            elif [[ $FILTERED_RC -eq 3 ]]; then
                # Düzenle (mevcut düzenleme kodunu kullan)
                IFS=$'\t' read -r FID FDATE FTIME FREPEAT FDESC FCATEGORY <<< "$FILTERED_SEL"
                ORIGINAL=$(sqlite3 -separator '|' "$DB_FILE" "SELECT * FROM reminders WHERE id = $FID")
                [[ -z "$ORIGINAL" ]] && { yad --error --text="Kayıt bulunamadı."; continue; }
                IFS='|' read -r ID DATE TIME REPEAT_TYPE DESC JOBS_CSV CREATED_AT <<< "$ORIGINAL"
                
                # Düzenleme formu
                EDIT_RES=$(
                yad --form --center --borders=12 --width=520 --title="Hatırlatma Düzenle" \
                  --field="Başlık":TXT "$DESC" \
                  --field="Kategori":CB "Genel!İş!Kişisel!Sağlık!Eğitim!Alışveriş!Diğer" \
                  --field="Tarih":D "$DATE" \
                  --field="Saat":T "$TIME" \
                  --field="Tekrarlama":CB "Yok!Günlük!Haftalık!Aylık" \
                  --separator="|"
                ) || continue
                
                IFS='|' read -r NDESC NCATEGORY NDATE NTIME NREPEAT <<< "$EDIT_RES"
                [[ -z "${NDESC// }" ]] && { yad --image=dialog-error --text="Açıklama boş olamaz."; continue; }
                
                # Eski job'ları iptal et
                if [[ -n "$JOBS_CSV" ]]; then
                    IFS=',' read -ra JOBS <<< "$JOBS_CSV"
                    for job in "${JOBS[@]}"; do
                        [[ -n "$job" ]] && atrm "$job" 2>/dev/null || true
                    done
                fi
                
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
                sqlite3 "$DB_FILE" "UPDATE reminders SET date='$NDATE', time='$(date -d "$BASE_TS" +%H:%M)', repeat_type='$NREPEAT', description='$NDESC', category='$NCATEGORY', jobs_csv='$JOBS_CSV' WHERE id=$FID"
                continue
            fi
        fi
        continue
    fi
done