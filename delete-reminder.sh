#!/usr/bin/env bash
set -uo pipefail

DB_FILE="$HOME/.reminders.db"

# ID parametresini al
SID="$1"
if [[ -z "$SID" ]]; then
    yad --error --text="Silinecek hatırlatma ID'si belirtilmedi."
    exit 1
fi

# Orijinal veriyi al
ORIGINAL=$(sqlite3 -separator '|' "$DB_FILE" "SELECT * FROM reminders WHERE id = $SID")
if [[ -z "$ORIGINAL" ]]; then
    yad --error --text="Kayıt bulunamadı: ID=$SID"
    exit 1
fi

IFS='|' read -r ID DATE TIME REPEAT_TYPE DESC CATEGORY JOBS_CSV CREATED_AT <<<"$ORIGINAL"

# Onay iste
if yad --question --title="Silme Onayı" --text="'$DESC' hatırlatması silinecek. Emin misiniz?"; then
    # at job'larını iptal et
    if [[ -n "${JOBS_CSV:-}" ]]; then
        IFS=',' read -ra JOBS <<< "$JOBS_CSV"
        for job in "${JOBS[@]}"; do
            [[ -n "$job" ]] && atrm "$job" 2>/dev/null || true
        done
    fi
    
    # Veritabanından sil
    sqlite3 "$DB_FILE" "DELETE FROM reminders WHERE id = $SID"
    yad --info --title="Silme" --text="Hatırlatma başarıyla silindi!"
else
    yad --info --title="Silme" --text="Silme işlemi iptal edildi."
fi
