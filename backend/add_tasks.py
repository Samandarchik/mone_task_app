import requests
import json
import time

# API konfiguratsiyasi
url = "http://127.0.0.1:8000/api/tasks"
token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VySWQiOjEsInVzZXJuYW1lIjoiU2FtYW5kYXIgYWRtaW4iLCJyb2xlIjoic3VwZXJfYWRtaW4iLCJleHAiOjUzNzAzNTU0Mzl9.di1cwAFRDe3DjNjavZvLsHjFxGVduy39ZmXeSV6Q3XQ"

headers = {
    "Content-Type": "application/json",
    "Authorization": f"Bearer {token}"
}

# tasks.json faylini o'qish
with open('tasks.json', 'r', encoding='utf-8') as file:
    tasks = json.load(file)

# Har bir vazifani yuborish
success_count = 0
error_count = 0

for index, task in enumerate(tasks, 1):
    try:
        response = requests.post(url, headers=headers, json=task)
        
        if response.status_code == 200 or response.status_code == 201:
            print(f"✅ {index}/{len(tasks)} - Muvaffaqiyatli yuborildi: {task['task'][:50]}...")
            success_count += 1
        else:
            print(f"❌ {index}/{len(tasks)} - Xatolik: {response.status_code} - {task['task'][:50]}...")
            print(f"   Javob: {response.text}")
            error_count += 1
            
    except Exception as e:
        print(f"❌ {index}/{len(tasks)} - Xatolik yuz berdi: {str(e)}")
        error_count += 1
    
    # Har bir so'rovdan keyin kichik pauza
    time.sleep(0.1)

print("\n" + "="*50)
print(f"Jami: {len(tasks)} ta vazifa")
print(f"Muvaffaqiyatli: {success_count}")
print(f"Xatolik: {error_count}")
print("="*50)