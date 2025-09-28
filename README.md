# Ubuntu Hatırlatıcı Projesi – Dokümantasyon

## 1. Amaç

Ubuntu üzerinde hızlıca hatırlatmalar oluşturmak, zamanı geldiğinde masaüstü bildirimi ve isteğe bağlı ses ile kullanıcıyı uyarmak. Klavye kısayolları ile tek pencereden hatırlatma ekleme, listeleme, silme ve düzenleme yapılabilir.

---

## 2. Kullanılan Araçlar

* **yad** – Grafiksel formlar ve listeler
* **at / atd** – Zamanlanmış işler (hatırlatma zamanı geldiğinde tetikler)
* **notify-send (libnotify-bin)** – Masaüstü bildirimleri
* **paplay / canberra-gtk-play** – Sesli uyarı (Freedesktop Bell varsayılan)
* **sqlite3** – Veritabanı yönetimi
* **bash** – İş mantığını sağlayan scriptler (`quick-reminder.sh` ve `show-reminders.sh`)

---

## 3. Kurulum

### Paket kurulumu

```bash
sudo apt update
sudo apt install -y yad at libnotify-bin pulseaudio-utils libcanberra-gtk3-module sqlite3
sudo systemctl enable --now atd
```

### Scriptlerin kurulması

* `~/bin/quick-reminder.sh` → yeni hatırlatma oluşturma
* `~/bin/show-reminders.sh` → mevcut hatırlatmaları listeleme, silme, düzenleme
* `~/bin/settings.sh` → ayarlar ekranı

Çalıştırılabilir yap:

```bash
chmod +x ~/bin/quick-reminder.sh
chmod +x ~/bin/show-reminders.sh
chmod +x ~/bin/settings.sh
```

---

## 4. Kullanım

### 4.1 Hatırlatma oluşturma

```bash
~/bin/quick-reminder.sh
```

* Açıklama girilir (zorunlu).
* Tarih varsayılan olarak bugünün tarihi gelir.
* Saat varsayılan olarak şu andan +1 dakika ileri gelir.
* Tekrarlama seçeneği: Yok / Günlük / Haftalık / Aylık.
* Ses seçenekleri: Freedesktop Bell (varsayılan), Yaru Complete, Yaru Message, Yaru Bell, Freedesktop Complete, Freedesktop Message, Ses Yok

Hatırlatma `at` servisi ile planlanır ve SQLite veritabanına kaydedilir.

### 4.2 Hatırlatma listesi

```bash
~/bin/show-reminders.sh
```

* Kayıtlı hatırlatmalar tablo halinde listelenir.
* **Sil**: Seçilen hatırlatma ve ilgili job iptal edilir, liste yenilenir.
* **Düzenle**: Tarih, saat, açıklama ve tekrarlama güncellenir, yeni job atanır, liste yenilenir.
* **Ayarlar**: Ayarlar ekranını açar.
* **Kapat**: Pencereyi kapatır.

### 4.3 Ayarlar

```bash
~/bin/settings.sh
```

* **Varsayılan Ses**: Hatırlatmalarda kullanılacak ses (test edilebilir)
* **Ses Yüksekliği**: Ses seviyesi (0-100)
* **Varsayılan Süre**: Yeni hatırlatmalar için varsayılan dakika (örn: 5 dakika sonra)
* **Varsayılan Tekrar**: Yeni hatırlatmalar için varsayılan tekrarlama
* **Do Not Disturb**: DND modunda da bildirim gönderilsin mi?

### 4.4 Klavye kısayolları

Ubuntu ayarlarından özel kısayollar tanımlayın:

* **Super+R** → `~/bin/quick-reminder.sh`
* **Super+L** → `~/bin/show-reminders.sh`
* **Super+S** → `~/bin/settings.sh` (opsiyonel)

---

## 5. Veri Yapısı

### SQLite Veritabanı (`~/.reminders.db`)

```sql
CREATE TABLE reminders (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    date TEXT NOT NULL,
    time TEXT NOT NULL,
    repeat_type TEXT DEFAULT 'Yok',
    description TEXT NOT NULL,
    jobs_csv TEXT DEFAULT '',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
```

### Veri Formatı

* **id**: Benzersiz kimlik (otomatik artan)
* **date**: Tarih (YYYY-MM-DD formatında)
* **time**: Saat (HH:MM formatında)
* **repeat_type**: Tekrarlama türü (Yok/Günlük/Haftalık/Aylık)
* **description**: Hatırlatma açıklaması
* **jobs_csv**: İlgili `at` job id'leri (virgülle ayrılmış)
* **created_at**: Oluşturulma tarihi

---

## 6. Örnek Çalışma Akışı

1. Kullanıcı **Super+R** tuşuna basar.
2. "Toplantı" açıklamalı, saat 16:00 için hatırlatma oluşturur.
3. Sistem `at` job'u kurar, SQLite veritabanına kaydeder.
4. Saat 16:00'da masaüstünde "⏰ Hatırlatma – Toplantı" bildirimi çıkar, opsiyonel Freedesktop Bell sesi çalar.
5. Kullanıcı **Super+L** ile listeyi açıp hatırlatmayı siler veya düzenler.

---

## 7. Özellikler

### ✅ Çalışan Özellikler

* Hatırlatma oluşturma (tek seferlik ve tekrarlayan)
* Hatırlatma listeleme
* Hatırlatma silme (job'ları da iptal eder)
* Hatırlatma düzenleme (job'ları yeniden planlar)
* Freedesktop Bell varsayılan ses
* Çift tıklama koruması (pencereyi kapatmaz)
* Silme/düzenleme sonrası otomatik liste yenileme
* SQLite veritabanı ile güvenilir veri saklama

### 🔧 Teknik Detaylar

* `--no-click` parametresi ile çift tıklama koruması
* `exec "$0"` ile silme/düzenleme sonrası liste yenileme
* SQLite ile veri bütünlüğü ve performans
* Freedesktop Bell ses dosyası (`/usr/share/sounds/freedesktop/stereo/bell.oga`)

---

## 8. Bilinen Kısıtlar

* Bilgisayar kapalı veya `atd` servisi çalışmıyorsa hatırlatma tetiklenmez.
* Tekrarlayan hatırlatmalar, şimdilik 12 kopya ileri planlanır (12 gün/hafta/ay). Sonsuz döngü değildir.
* SQLite veritabanı dosyası (`~/.reminders.db`) manuel olarak silinirse tüm veriler kaybolur.

---

## 9. Gelecek Geliştirmeler

* Hatırlatma geçmişini otomatik temizleme
* "Ertele (Snooze)" özelliği (+10dk vb.)
* Daha gelişmiş tekrarlama (ör. sadece iş günleri)
* Takvim entegrasyonu (Google Calendar / Evolution)
* CSV/JSON dışa aktarma
* Veritabanı yedekleme/geri yükleme