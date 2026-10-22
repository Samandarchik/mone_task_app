package main

import (
	"database/sql"
	"encoding/json"
	"log"
	"net/http"
	"sort"
	"strings"
	"time"
)

// ═══════════════════════════════════════════════════════════════════
// Vazifa eslatmalari
//
// - Vazifa vaqti (shablondagi notification_time) kelganda — shu filial
//   xodimlariga ilovada bir marta eslatma (WS "task_reminder").
// - Har 10 daqiqada — vaqti o'tib, hali bajarilmagan vazifalar ro'yxati
//   korrektor va super adminga (WS "overdue_tasks").
// ═══════════════════════════════════════════════════════════════════

// OverdueTask — vaqti kelgan, lekin xodim hali videolarni yuklamagan vazifa
type OverdueTask struct {
	TaskID     int    `json:"taskId"`
	TemplateID int    `json:"templateId"`
	FilialID   int    `json:"filialId"`
	FilialName string `json:"filialName"`
	Task       string `json:"task"`
	Category   string `json:"category"`
	Time       string `json:"time"`
	// LateMinutes — vaqtidan necha daqiqa o'tdi
	LateMinutes int `json:"lateMinutes"`
}

// sendTo — faqat shartga mos ulangan foydalanuvchilarga yuboradi
func (h *WSHub) sendTo(match func(c *WSClient) bool, event string, data map[string]interface{}) int {
	msgBytes, err := json.Marshal(map[string]interface{}{"event": event, "data": data})
	if err != nil {
		return 0
	}

	h.mu.RLock()
	defer h.mu.RUnlock()

	sent := 0
	for client := range h.clients {
		if !match(client) {
			continue
		}
		select {
		case client.send <- msgBytes:
			sent++
		default:
		}
	}
	return sent
}

// unfinishedTasksDue — bugungi, vaqti [now] dan oshmagan va hali bajarilmagan
// vazifalar. Vaqt shablondan olinadi (keyin o'zgartirilgan bo'lsa ham to'g'ri).
func unfinishedTasksDue(now time.Time) []OverdueTask {
	mainDB, err := getMainDB()
	if err != nil {
		return nil
	}
	defer mainDB.Close()

	times := map[int]string{}
	rows, err := mainDB.Query("SELECT id, notification_time FROM task_templates WHERE notification_time IS NOT NULL AND notification_time != ''")
	if err != nil {
		return nil
	}
	for rows.Next() {
		var id int
		var t string
		rows.Scan(&id, &t)
		if len(t) >= 5 {
			times[id] = t[:5]
		}
	}
	rows.Close()
	if len(times) == 0 {
		return nil
	}

	filialNames := map[int]string{}
	if rows, err := mainDB.Query("SELECT id, name FROM filials"); err == nil {
		for rows.Next() {
			var id int
			var name string
			rows.Scan(&id, &name)
			filialNames[id] = name
		}
		rows.Close()
	}

	taskDB, err := getTaskDB(now)
	if err != nil {
		return nil
	}
	defer taskDB.Close()

	configs := getTemplateVideoConfigs()
	current := now.Format("15:04")

	rows, err = taskDB.Query(`
		SELECT id, COALESCE(template_id, 0), filial_id, task, category, video_url
		FROM tasks
		WHERE status IS NULL OR status NOT IN (?, ?)`,
		StatusPending, StatusApproved)
	if err != nil {
		return nil
	}
	defer rows.Close()

	var result []OverdueTask
	for rows.Next() {
		var t OverdueTask
		var videoRaw *string
		rows.Scan(&t.TaskID, &t.TemplateID, &t.FilialID, &t.Task, &t.Category, &videoRaw)

		due, ok := times[t.TemplateID]
		if !ok || due > current {
			continue
		}
		// Barcha majburiy videolar yuklangan bo'lsa — bajarilgan
		required := 1
		if cfg, ok := configs[t.TemplateID]; ok {
			required = cfg.Count
		}
		if videos, _ := parseVideoURLs(videoRaw); len(videos) >= required {
			continue
		}

		t.Time = due
		t.FilialName = filialNames[t.FilialID]
		if at, err := time.ParseInLocation("15:04", due, now.Location()); err == nil {
			at = time.Date(now.Year(), now.Month(), now.Day(), at.Hour(), at.Minute(), 0, 0, now.Location())
			t.LateMinutes = int(now.Sub(at).Minutes())
		}
		result = append(result, t)
	}

	sort.Slice(result, func(i, j int) bool {
		if result[i].FilialName != result[j].FilialName {
			return result[i].FilialName < result[j].FilialName
		}
		return result[i].Time < result[j].Time
	})
	return result
}

// filialWorkers — vazifani bajaradigan xodimlar (filial + kategoriya bo'yicha,
// vazifa yaratilgandagi qoida bilan bir xil)
func filialWorkers(mainDB *sql.DB, filialID int, category string) map[int]bool {
	result := map[int]bool{}
	rows, err := mainDB.Query("SELECT id, COALESCE(filial_ids, ''), COALESCE(categories, '') FROM users WHERE role = ?", RoleWorker)
	if err != nil {
		return result
	}
	defer rows.Close()
	for rows.Next() {
		var id int
		var filialsStr, categoriesStr string
		rows.Scan(&id, &filialsStr, &categoriesStr)

		inFilial := false
		for _, f := range parseFilialIDs(filialsStr) {
			if f == filialID {
				inFilial = true
				break
			}
		}
		if !inFilial {
			continue
		}
		if category != "" && !strings.Contains(categoriesStr, category) {
			continue
		}
		result[id] = true
	}
	return result
}

// checkAndSendNotifications — har daqiqada chaqiriladi
func checkAndSendNotifications() {
	now := time.Now()
	current := now.Format("15:04")
	tasks := unfinishedTasksDue(now)

	// 1) Vaqti aynan hozir kelganlar — xodimlarga bir marta
	var mainDB *sql.DB
	for _, t := range tasks {
		if t.Time != current {
			continue
		}
		if mainDB == nil {
			db, err := getMainDB()
			if err != nil {
				break
			}
			mainDB = db
			defer mainDB.Close()
		}
		workers := filialWorkers(mainDB, t.FilialID, t.Category)
		sent := hub.sendTo(func(c *WSClient) bool { return workers[c.userID] }, "task_reminder", map[string]interface{}{
			"taskId":   t.TaskID,
			"filialId": t.FilialID,
			"task":     t.Task,
			"time":     t.Time,
		})
		log.Printf("⏰ Eslatma: '%s' (filial %d) — %d xodimga", t.Task, t.FilialID, sent)
	}

	// 2) Har 10 daqiqada — korrektor va super adminga bajarilmaganlar ro'yxati
	if now.Minute()%10 != 0 {
		return
	}
	var late []OverdueTask
	for _, t := range tasks {
		if t.LateMinutes > 0 {
			late = append(late, t)
		}
	}
	if len(late) == 0 {
		return
	}
	sent := hub.sendTo(func(c *WSClient) bool {
		return c.role == RoleChecker || c.role == RoleSuperAdmin
	}, "overdue_tasks", map[string]interface{}{
		"count": len(late),
		"tasks": late,
	})
	log.Printf("🔔 Bajarilmagan vazifalar: %d ta — %d ta korrektorga", len(late), sent)
}

// getOverdueTasks — GET /api/tasks/overdue: qo'ng'iroqcha ro'yxati
func getOverdueTasks(w http.ResponseWriter, r *http.Request) {
	role := r.Header.Get("Role")
	if role != RoleChecker && role != RoleSuperAdmin {
		respondJSON(w, http.StatusForbidden, map[string]interface{}{
			"success": false,
			"error":   "Ruxsat yo'q",
		})
		return
	}

	var late []OverdueTask
	for _, t := range unfinishedTasksDue(time.Now()) {
		if t.LateMinutes > 0 {
			late = append(late, t)
		}
	}
	if late == nil {
		late = []OverdueTask{}
	}
	respondJSON(w, http.StatusOK, map[string]interface{}{
		"success": true,
		"data":    late,
		"total":   len(late),
	})
}
