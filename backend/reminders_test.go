package main

import (
	"os"
	"testing"
	"time"
)

func TestUnfinishedTasksDue(t *testing.T) {
	wd, _ := os.Getwd()
	os.Chdir(t.TempDir())
	t.Cleanup(func() { os.Chdir(wd) })
	initDB()

	mainDB, _ := getMainDB()
	defer mainDB.Close()
	res, err := mainDB.Exec(`INSERT INTO task_templates (task, type, filial_ids, category, notification_time, order_index, video_count)
		VALUES ('Svet', 1, '1', '', '09:00', 1, 2)`)
	if err != nil {
		t.Fatalf("template: %v", err)
	}
	templateID, _ := res.LastInsertId()

	now := time.Date(2026, 10, 22, 9, 30, 0, 0, time.Local)
	taskDB, err := getTaskDB(now)
	if err != nil {
		t.Fatalf("task db: %v", err)
	}
	defer taskDB.Close()
	taskDB.Exec(`INSERT INTO tasks (template_id, filial_id, task, type, category) VALUES (?, 1, 'Svet', 1, '')`, templateID)

	// Vaqtidan oldin — ro'yxatda yo'q
	if got := unfinishedTasksDue(now.Add(-time.Hour)); len(got) != 0 {
		t.Fatalf("09:00 dan oldin bo'sh bo'lishi kerak: %+v", got)
	}

	got := unfinishedTasksDue(now)
	if len(got) != 1 || got[0].LateMinutes != 30 || got[0].Time != "09:00" || got[0].FilialName == "" {
		t.Fatalf("kechikkan vazifa: %+v", got)
	}

	// Bitta video — hali tugallanmagan (2 ta kerak)
	taskDB.Exec(`UPDATE tasks SET video_url = '["a.mp4"]'`)
	if got := unfinishedTasksDue(now); len(got) != 1 {
		t.Fatalf("1/2 video — hali bajarilmagan: %+v", got)
	}

	// Ikkala video — bajarilgan
	taskDB.Exec(`UPDATE tasks SET video_url = '["a.mp4","b.mp4"]'`)
	if got := unfinishedTasksDue(now); len(got) != 0 {
		t.Fatalf("videolar to'liq — ro'yxatda bo'lmasligi kerak: %+v", got)
	}
}
