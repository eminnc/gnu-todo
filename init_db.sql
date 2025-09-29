CREATE TABLE IF NOT EXISTS reminders (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    date TEXT NOT NULL,
    time TEXT NOT NULL,
    repeat_type TEXT DEFAULT 'Yok',
    description TEXT NOT NULL,
    category TEXT DEFAULT 'Genel',
    jobs_csv TEXT DEFAULT '',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_date_time ON reminders(date, time);
CREATE INDEX IF NOT EXISTS idx_category ON reminders(category);
