#!/usr/bin/env bash

DB_FILE="$HOME/.reminders.db"
OLD_FILE="$HOME/.reminders"

# Veritabanı yoksa oluştur
if [[ ! -f "$DB_FILE" ]]; then
    sqlite3 "$DB_FILE" < "$(dirname "$0")/init_db.sql"
fi

# Eski dosya yoksa çık
if [[ ! -f "$OLD_FILE" ]]; then
    echo "Eski .reminders dosyası bulunamadı."
    exit 0
fi

echo "Mevcut .reminders dosyasını SQLite veritabanına migrate ediliyor..."

# Dosyayı oku ve migrate et
while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "${line// }" ]] && continue
    line="${line%$'\r'}"
    
    # Alan sayısı
    nf=$(awk -F'|' '{print NF}' <<< "$line")
    
    # Geçerli satırları migrate et
    if (( nf >= 6 )) && [[ "$line" =~ ^[0-9]{13}\| ]]; then
        IFS='|' read -r id date time repeat_type desc jobs_csv <<< "$line"
        # Sadece ilk 6 alanı al
        sqlite3 "$DB_FILE" "INSERT OR IGNORE INTO reminders (id, date, time, repeat_type, description, jobs_csv) VALUES ($id, '$date', '$time', '$repeat_type', '$desc', '$jobs_csv')"
    fi
done < "$OLD_FILE"

echo "Migration tamamlandı. Eski dosya yedeklendi: $OLD_FILE.backup"
mv "$OLD_FILE" "$OLD_FILE.backup"

echo "Artık SQLite veritabanı kullanılıyor: $DB_FILE"
