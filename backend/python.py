import pandas as pd
import json

def excel_to_json(excel_path, output_path="output.json"):
    
    df = pd.read_excel("Рабочий устав Сибирский 21.01.2026 (2).xlsx", header=None)

    tasks = []

    for _, row in df.iterrows():
        num = row[0]            # Vazifa raqami
        task = row[1]           # Vazifa matni
        raw = row[3] if 3 in row.index else None  # Vaqt + kim qilgani

        # Faqat haqiqiy satrlarni olish
        if pd.isna(num) or pd.isna(task):
            continue

        # Raqamni integerga aylantirishga harakat
        try:
            num_int = int(str(num).strip())
        except:
            continue

        assigned_time = None
        assigned_person = None

        # "15:26:10 Халилов Бахтиёр" formatini ajratish
        if isinstance(raw, str):
            parts = raw.split(" ", 1)
            if len(parts) == 2:
                assigned_time = parts[0]
                assigned_person = parts[1]

        tasks.append({
            "number": num_int,
            "task": str(task),
            "assigned_time": assigned_time,
            "assigned_person": assigned_person
        })

    # JSON filega yozish
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(tasks, f, ensure_ascii=False, indent=2)

    print(f"JSON saved as {output_path}")


# --- USE EXAMPLE ---
# excel_to_json("your_file.xlsx", "output.json")
