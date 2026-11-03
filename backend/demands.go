package main

// ═══════════════════════════════════════════════════════════════════
// Revizor talabi («Потребовать»)
//
// Vaqti o'tib bajarilmagan vazifa uchun revizor (checker / super_admin)
// mas'ul xodimlardan bajarishni talab qiladi:
//   - xodimga (va vazifa biriktirilgan sotrudnikka) ilovada yopib bo'lmaydigan
//     oyna (WS "task_demand"), telefonga ovozli push (FCM) + Telegram xabar;
//   - vazifa bajarilmaguncha har 10 daqiqada WS va push eslatma qaytariladi;
//   - videolar yuklangach talab o'z-o'zidan tushadi (alohida yopish shart emas).
//
// Talab faqat bugungi vazifaga beriladi va main DB'dagi task_demands da
// (sana + task_id) saqlanadi — kunlik task DB'lar sxemasiga tegmaymiz.
// ═══════════════════════════════════════════════════════════════════

import (
	"database/sql"
	"fmt"
	"log"
	"net/http"
	"strconv"
	"time"

	"github.com/gorilla/mux"
)

// Responsible — vazifani bajarishi kerak bo'lgan odam
type Responsible struct {
	UserID   int    `json:"userId"`
	Username string `json:"username"`
	Role     string `json:"role"`
}

// DemandInfo — vazifaga qo'yilgan revizor talabi
type DemandInfo struct {
	DemandedBy string `json:"demandedBy"`
	FirstAt    string `json:"firstAt"`
	LastAt     string `json:"lastAt"`
	Count      int    `json:"count"`
}

// MyDemand — xodimga ko'rsatiladigan faol talab
type MyDemand struct {
	TaskID     int    `json:"taskId"`
	FilialID   int    `json:"filialId"`
	FilialName string `json:"filialName"`
	Task       string `json:"task"`
	Time       string `json:"time"`
	DemandInfo
}

func migrateDemands(db *sql.DB) {
	db.Exec(`CREATE TABLE IF NOT EXISTS task_demands (
		date TEXT NOT NULL,
		task_id INTEGER NOT NULL,
		demanded_by TEXT NOT NULL DEFAULT '',
		first_at TEXT NOT NULL,
		last_at TEXT NOT NULL,
		count INTEGER NOT NULL DEFAULT 1,
		PRIMARY KEY (date, task_id)
	)`)
}

// taskResponsibles — vazifa uchun mas'ullar: filial+kategoriya bo'yicha
// workerlar va ular shu shablonni biriktirgan sotrudniklar.
func taskResponsibles(mainDB *sql.DB, filialID, templateID int, category string) []Responsible {
	workers := filialWorkers(mainDB, filialID, category)
	if len(workers) == 0 {
		return []Responsible{}
	}
	ids := map[int]bool{}
	for id := range workers {
		ids[id] = true
	}
	if templateID > 0 {
		rows, err := mainDB.Query("SELECT owner_id, employee_id FROM task_delegations WHERE template_id = ?", templateID)
		if err == nil {
			for rows.Next() {
				var owner, emp int
				rows.Scan(&owner, &emp)
				if workers[owner] {
					ids[emp] = true
				}
			}
			rows.Close()
		}
	}

	args := []interface{}{}
	for id := range ids {
		args = append(args, id)
	}
	rows, err := mainDB.Query(
		fmt.Sprintf("SELECT id, username, role FROM users WHERE id IN (%s) ORDER BY role DESC, username", placeholders(len(args))),
		args...)
	if err != nil {
		return []Responsible{}
	}
	defer rows.Close()
	result := []Responsible{}
	for rows.Next() {
		var p Responsible
		rows.Scan(&p.UserID, &p.Username, &p.Role)
		result = append(result, p)
	}
	return result
}

// todayDemands — bugungi talablar, task_id bo'yicha
func todayDemands(mainDB *sql.DB, now time.Time) map[int]DemandInfo {
	result := map[int]DemandInfo{}
	rows, err := mainDB.Query("SELECT task_id, demanded_by, first_at, last_at, count FROM task_demands WHERE date = ?",
		now.Format("2006-01-02"))
	if err != nil {
		return result
	}
	defer rows.Close()
	for rows.Next() {
		var id int
		var d DemandInfo
		rows.Scan(&id, &d.DemandedBy, &d.FirstAt, &d.LastAt, &d.Count)
		result[id] = d
	}
	return result
}

// withResponsibles — overdue ro'yxatini mas'ullar va talab holati bilan to'ldiradi
func withResponsibles(tasks []OverdueTask) []OverdueTask {
	if len(tasks) == 0 {
		return tasks
	}
	mainDB, err := getMainDB()
	if err != nil {
		return tasks
	}
	defer mainDB.Close()
	demands := todayDemands(mainDB, time.Now())
	for i := range tasks {
		t := &tasks[i]
		t.Responsible = taskResponsibles(mainDB, t.FilialID, t.TemplateID, t.Category)
		if d, ok := demands[t.TaskID]; ok {
			d := d
			t.Demand = &d
		}
	}
	return tasks
}

// activeDemandTasks — bugungi, hali bajarilmagan va talab qo'yilgan vazifalar
func activeDemandTasks(now time.Time) []OverdueTask {
	var result []OverdueTask
	for _, t := range withResponsibles(unfinishedTasksDue(now)) {
		if t.Demand != nil {
			result = append(result, t)
		}
	}
	return result
}

// userTelegramID — HR sinxronidagi telegram_id, bo'lmasa rezumedagi tg_user_id
func userTelegramID(mainDB *sql.DB, userID int) int64 {
	var tgID int64
	var profile sql.NullString
	mainDB.QueryRow("SELECT COALESCE(telegram_id, 0), profile_json FROM users WHERE id = ?", userID).Scan(&tgID, &profile)
	if tgID == 0 && profile.Valid {
		tgID = telegramIDFromProfileJSON(profile.String)
	}
	return tgID
}

func demandEventData(t OverdueTask) map[string]interface{} {
	d := t.Demand
	return map[string]interface{}{
		"taskId":     t.TaskID,
		"filialId":   t.FilialID,
		"filialName": t.FilialName,
		"task":       t.Task,
		"time":       t.Time,
		"demandedBy": d.DemandedBy,
		"lastAt":     d.LastAt,
		"count":      d.Count,
	}
}

// demandDelivery — talab kimga qaysi yo'l bilan yetgani
type demandDelivery struct {
	Online map[int]bool // ilovasi ochiq (WS)
	Pushed map[int]bool // telefonga bildirishnoma (FCM)
}

// pushDemand — mas'ullarga talabni yuboradi: ilovasi ochiq bo'lsa majburiy
// oyna (WS), ilova yopiq yoki telefon qulflangan bo'lsa ovozli push (FCM).
func pushDemand(mainDB *sql.DB, t OverdueTask) demandDelivery {
	who := map[int]bool{}
	ids := make([]int, 0, len(t.Responsible))
	for _, p := range t.Responsible {
		who[p.UserID] = true
		ids = append(ids, p.UserID)
	}
	// Har biriga alohida: «ilovada» faqat xabar haqiqatan navbatga tushganda
	// hisoblanadi (WS buferi to'la bo'lsa yuborilmaydi)
	online := map[int]bool{}
	event := demandEventData(t)
	for id := range who {
		uid := id
		if hub.sendTo(func(c *WSClient) bool { return c.userID == uid }, "task_demand", event) > 0 {
			online[uid] = true
		}
	}

	body := t.Task
	if t.FilialName != "" {
		body = t.FilialName + " · " + t.Task
	}
	pushed := pushToUsers(mainDB, ids, "Ревизор требует выполнить", body, map[string]string{
		"type":   "task_demand",
		"taskId": strconv.Itoa(t.TaskID),
	})
	return demandDelivery{Online: online, Pushed: pushed}
}

func lateText(minutes int) string {
	if minutes < 60 {
		return fmt.Sprintf("%d daqiqa", minutes)
	}
	if minutes%60 == 0 {
		return fmt.Sprintf("%d soat", minutes/60)
	}
	return fmt.Sprintf("%d soat %d daqiqa", minutes/60, minutes%60)
}

// POST /api/tasks/{id}/demand — revizor bugungi bajarilmagan vazifani talab qiladi
func demandTask(w http.ResponseWriter, r *http.Request) {
	role := r.Header.Get("Role")
	if role != RoleChecker && role != RoleSuperAdmin {
		respondJSON(w, http.StatusForbidden, map[string]interface{}{
			"success": false,
			"error":   "Ruxsat yo'q",
		})
		return
	}
	taskID, _ := strconv.Atoi(mux.Vars(r)["id"])
	now := time.Now()

	var task *OverdueTask
	for _, t := range unfinishedTasksDue(now) {
		if t.TaskID == taskID {
			t := t
			task = &t
			break
		}
	}
	if task == nil {
		respondJSON(w, http.StatusBadRequest, map[string]interface{}{
			"success": false,
			"error":   "Vazifa bajarilgan yoki hali vaqti kelmagan",
		})
		return
	}

	mainDB, err := getMainDB()
	if err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]interface{}{
			"success": false,
			"error":   "Server xatosi",
		})
		return
	}
	defer mainDB.Close()

	by := r.Header.Get("Username")
	at := now.Format("15:04")
	mainDB.Exec(`INSERT INTO task_demands (date, task_id, demanded_by, first_at, last_at, count)
		VALUES (?, ?, ?, ?, ?, 1)
		ON CONFLICT(date, task_id) DO UPDATE SET demanded_by = excluded.demanded_by, last_at = excluded.last_at, count = count + 1`,
		now.Format("2006-01-02"), taskID, by, at, at)

	task.Responsible = taskResponsibles(mainDB, task.FilialID, task.TemplateID, task.Category)
	if d, ok := todayDemands(mainDB, now)[taskID]; ok {
		task.Demand = &d
	}
	if task.Demand == nil {
		respondJSON(w, http.StatusInternalServerError, map[string]interface{}{
			"success": false,
			"error":   "Talab saqlanmadi",
		})
		return
	}

	delivery := pushDemand(mainDB, *task)

	msg := fmt.Sprintf(
		"⚠️ REVIZOR TALABI\n\nFilial: %s\nVazifa: %s\nVaqti: %s (%s kechikdi)\nTalab qildi: %s\n\nDarhol bajaring va videoni ilovaga yuklang!",
		task.FilialName, task.Task, task.Time, lateText(task.LateMinutes), by)
	tgSent := 0
	var noTelegram []string
	notReached := []string{} // hech qaysi yo'l bilan yetmaganlar
	for _, p := range task.Responsible {
		sent := false
		if chatID := userTelegramID(mainDB, p.UserID); chatID != 0 {
			if err := sendCredsTgMessage(chatID, msg); err != nil {
				log.Printf("demand: %s ga Telegram yuborilmadi: %v", p.Username, err)
			} else {
				sent = true
				tgSent++
			}
		}
		if !sent {
			noTelegram = append(noTelegram, p.Username)
		}
		if !sent && !delivery.Online[p.UserID] && !delivery.Pushed[p.UserID] {
			notReached = append(notReached, p.Username)
		}
	}
	if noTelegram == nil {
		noTelegram = []string{}
	}
	log.Printf("📣 Talab: '%s' (filial %d) — %s, %d mas'ul, ilovada %d, push %d, Telegram %d, yetmadi %d",
		task.Task, task.FilialID, by, len(task.Responsible), len(delivery.Online), len(delivery.Pushed), tgSent, len(notReached))

	hub.sendTo(func(c *WSClient) bool {
		return c.role == RoleChecker || c.role == RoleSuperAdmin
	}, "task_demand_updated", map[string]interface{}{"taskId": taskID})

	respondJSON(w, http.StatusOK, map[string]interface{}{
		"success":     true,
		"responsible": task.Responsible,
		"demand":      task.Demand,
		"online":      len(delivery.Online),
		"push":        len(delivery.Pushed),
		"telegram":    tgSent,
		"noTelegram":  noTelegram,
		"notReached":  notReached,
	})
}

// GET /api/my/demands — xodimga qo'yilgan, hali bajarilmagan talablar
func getMyDemands(w http.ResponseWriter, r *http.Request) {
	userID, _ := strconv.Atoi(r.Header.Get("UserID"))
	result := []MyDemand{}
	for _, t := range activeDemandTasks(time.Now()) {
		for _, p := range t.Responsible {
			if p.UserID != userID {
				continue
			}
			result = append(result, MyDemand{
				TaskID:     t.TaskID,
				FilialID:   t.FilialID,
				FilialName: t.FilialName,
				Task:       t.Task,
				Time:       t.Time,
				DemandInfo: *t.Demand,
			})
			break
		}
	}
	respondJSON(w, http.StatusOK, map[string]interface{}{
		"success": true,
		"data":    result,
	})
}

// remindDemands — scheduler: bajarilmagan talablarni har 10 daqiqada qaytaradi
func remindDemands(now time.Time) {
	tasks := activeDemandTasks(now)
	if len(tasks) == 0 {
		return
	}
	mainDB, err := getMainDB()
	if err != nil {
		return
	}
	defer mainDB.Close()
	for _, t := range tasks {
		d := pushDemand(mainDB, t)
		log.Printf("📣 Talab eslatmasi: '%s' (filial %d) — ilovada %d, push %d",
			t.Task, t.FilialID, len(d.Online), len(d.Pushed))
	}
}
