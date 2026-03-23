from openpyxl import Workbook

# Provided JSON
data = {
    "data": [
        {
            "date": "06.02.2026",
            "tasks": [
                {
                    "taskName": "Ешикларни очиш",
                    "status": 3,
                    "submittedAt": "2026-02-06T13:51:25+05:00",
                    "submittedBy": "Bobur",
                    "videoUrl": "/videos/2026-02-06/video1_1770367882838.mp4",
                    "statusText": "Tasdiqlandi",
                    "submittedTime": "13:51"
                },
                {
                    "taskName": "Хамма столлардаги сервировкаларni текшириб чикиш",
                    "status": 3,
                    "submittedAt": "2026-02-06T13:52:11+05:00",
                    "submittedBy": "Bobur",
                    "videoUrl": "/videos/2026-02-06/video2_1770367930894.mp4",
                    "statusText": "Tasdiqlandi",
                    "submittedTime": "13:52"
                }
            ]
        }
    ],
    "filialName": "Сибирские",
}

filial_name = data["filialName"]

wb = Workbook()
ws = wb.active
ws.title = "Report"

# FIRST ROW: "Filial || Date"
for entry in data["data"]:
    ws.append([f"{filial_name} || {entry['date']}"])
    ws.append([])  # Empty row

    # Headings
    ws.append(["Task Name", "Submitted Info"])

    for task in entry["tasks"]:
        if task["status"] == 3:
            submitted_info = (
                f"{task['submittedBy']}\n"
                f"{task['submittedTime']}"
            )
        else:
            submitted_info = ""
        ws.append([task["taskName"], submitted_info])

    ws.append([])

filepath = "filial_report.xlsx"
wb.save(filepath)

filepath
