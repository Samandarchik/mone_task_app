import sqlite3
import os

db_files = [
    "db/tasks_2026-02-23.db",
    "db/tasks_2026-02-22.db",
    "db/tasks_2026-02-21.db",
    "db/tasks_2026-02-20.db",
    "db/tasks_2026-02-19.db",
    "db/tasks_2026-02-18.db",
]

for db_path in db_files:
    if not os.path.exists(db_path):
        print(f"❌ Topilmadi: {db_path}")
        continue

    try:
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()

        # Ustun mavjudligini tekshirish
        cursor.execute("PRAGMA table_info(tasks)")
        columns = [row[1] for row in cursor.fetchall()]

        if "checker_audio_url" in columns:
            print(f"✅ Allaqachon mavjud: {db_path}")
        else:
            cursor.execute("ALTER TABLE tasks ADD COLUMN checker_audio_url TEXT")
            conn.commit()
            print(f"✅ Qo'shildi: {db_path}")

        conn.close()
    except Exception as e:
        print(f"❌ Xato ({db_path}): {e}")

print("\nMigration tugadi!")
