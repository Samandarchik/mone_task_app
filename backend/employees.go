package main

// Сотрудник — worker o'zi uchun qo'shadigan yordamchi xodim.
//
// Worker (egasi) sotrudnikga login/parol beradi va o'z vazifalaridan
// birortasini unga biriktiradi. Sotrudnik faqat egasi biriktirgan vazifalarni
// ko'radi va ularni egasi nomidan bajaradi (video yuboradi). Biriktirish
// shablon (template) bo'yicha saqlanadi — har kuni yangi vazifa yaratilganda
// ham o'z kuchida qoladi.

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gorilla/mux"
	"golang.org/x/crypto/bcrypt"
)

const RoleEmployee = "sotrudnik"

type Employee struct {
	ID          int    `json:"userId"`
	Username    string `json:"username"`
	Login       string `json:"login"`
	Password    string `json:"password"`
	TemplateIDs []int  `json:"templateIds"`
}

func migrateEmployees(db *sql.DB) {
	db.Exec("ALTER TABLE users ADD COLUMN owner_id INTEGER NOT NULL DEFAULT 0")
	db.Exec(`CREATE TABLE IF NOT EXISTS task_delegations (
		owner_id INTEGER NOT NULL,
		employee_id INTEGER NOT NULL,
		template_id INTEGER NOT NULL,
		PRIMARY KEY (owner_id, employee_id, template_id)
	)`)
}

// employeeOwner — sotrudnikning egasi (worker) id si. Topilmasa 0.
func employeeOwner(db *sql.DB, employeeID int) int {
	var ownerID int
	db.QueryRow("SELECT owner_id FROM users WHERE id = ? AND role = ?", employeeID, RoleEmployee).Scan(&ownerID)
	return ownerID
}

// userFilialIDs — foydalanuvchining filiallari (DB dagi joriy qiymat).
func userFilialIDs(db *sql.DB, userID int) []int {
	var s sql.NullString
	db.QueryRow("SELECT filial_ids FROM users WHERE id = ?", userID).Scan(&s)
	if !s.Valid {
		return nil
	}
	return parseFilialIDs(s.String)
}

// employeeTemplateIDs — sotrudnikka egasi biriktirgan shablonlar.
func employeeTemplateIDs(db *sql.DB, ownerID, employeeID int) []int {
	rows, err := db.Query("SELECT template_id FROM task_delegations WHERE owner_id = ? AND employee_id = ? ORDER BY template_id",
		ownerID, employeeID)
	if err != nil {
		return []int{}
	}
	defer rows.Close()
	ids := []int{}
	for rows.Next() {
		var id int
		rows.Scan(&id)
		ids = append(ids, id)
	}
	return ids
}

func placeholders(n int) string {
	return strings.TrimSuffix(strings.Repeat("?,", n), ",")
}

// employeeTasksQuery — getTasks uchun sotrudnik ko'radigan vazifalar so'rovi:
// egasining filiallaridagi, egasi biriktirgan shablonlar. ok=false — hech narsa yo'q.
func employeeTasksQuery(employeeID int) (string, []interface{}, bool) {
	mainDB, err := getMainDB()
	if err != nil {
		return "", nil, false
	}
	defer mainDB.Close()

	ownerID := employeeOwner(mainDB, employeeID)
	if ownerID == 0 {
		return "", nil, false
	}
	filialIDs := userFilialIDs(mainDB, ownerID)
	templateIDs := employeeTemplateIDs(mainDB, ownerID, employeeID)
	if len(filialIDs) == 0 || len(templateIDs) == 0 {
		return "", nil, false
	}

	args := []interface{}{}
	for _, id := range filialIDs {
		args = append(args, id)
	}
	for _, id := range templateIDs {
		args = append(args, id)
	}
	query := fmt.Sprintf(`
		SELECT id, template_id, filial_id, worker_ids, task, type, status, video_url, checker_audio_url, submitted_at, submitted_by, days, category, notification_time, order_index
		FROM tasks
		WHERE filial_id IN (%s) AND template_id IN (%s)
		ORDER BY order_index ASC
	`, placeholders(len(filialIDs)), placeholders(len(templateIDs)))
	return query, args, true
}

// employeeCanAccessTask — sotrudnik shu kungi vazifaga tegishlimi
// (egasi biriktirgan shablon va egasining filiali).
func employeeCanAccessTask(employeeID int, taskID string, date time.Time) bool {
	taskDB, err := getTaskDB(date)
	if err != nil {
		return false
	}
	defer taskDB.Close()
	var templateID, filialID int
	if err := taskDB.QueryRow("SELECT COALESCE(template_id, 0), filial_id FROM tasks WHERE id = ?", taskID).
		Scan(&templateID, &filialID); err != nil {
		return false
	}

	mainDB, err := getMainDB()
	if err != nil {
		return false
	}
	defer mainDB.Close()
	ownerID := employeeOwner(mainDB, employeeID)
	if ownerID == 0 || !containsInt(userFilialIDs(mainDB, ownerID), filialID) {
		return false
	}
	var n int
	mainDB.QueryRow("SELECT COUNT(*) FROM task_delegations WHERE owner_id = ? AND employee_id = ? AND template_id = ?",
		ownerID, employeeID, templateID).Scan(&n)
	return n > 0
}

// employeeSubmitterName — sotrudnik yuborgan video egasi (vazifani bergan
// worker) nomidan yoziladi: hamma joyda muallif sifatida egasi ko'rinadi.
func employeeSubmitterName(employeeID int, employeeName string) string {
	mainDB, err := getMainDB()
	if err != nil {
		return employeeName
	}
	defer mainDB.Close()
	var ownerName string
	mainDB.QueryRow("SELECT u.username FROM users u JOIN users e ON e.owner_id = u.id WHERE e.id = ?", employeeID).Scan(&ownerName)
	if ownerName == "" {
		return employeeName
	}
	return ownerName
}

// fillDelegations — worker o'z vazifalarini kimga biriktirganini ko'radi.
func fillDelegations(ownerID int, tasks []Task) {
	if len(tasks) == 0 {
		return
	}
	mainDB, err := getMainDB()
	if err != nil {
		return
	}
	defer mainDB.Close()
	rows, err := mainDB.Query("SELECT template_id, employee_id FROM task_delegations WHERE owner_id = ? ORDER BY employee_id", ownerID)
	if err != nil {
		return
	}
	defer rows.Close()
	byTemplate := map[int][]int{}
	for rows.Next() {
		var tid, eid int
		rows.Scan(&tid, &eid)
		byTemplate[tid] = append(byTemplate[tid], eid)
	}
	for i := range tasks {
		tasks[i].DelegatedTo = byTemplate[tasks[i].TemplateID]
	}
}

// deleteEmployeesOf — worker o'chirilganda uning sotrudniklari ham o'chiriladi.
func deleteEmployeesOf(db *sql.DB, ownerID string) {
	db.Exec("DELETE FROM task_delegations WHERE owner_id = ? OR employee_id = ?", ownerID, ownerID)
	db.Exec("DELETE FROM users WHERE owner_id = ? AND role = ?", ownerID, RoleEmployee)
}

func containsInt(list []int, v int) bool {
	for _, x := range list {
		if x == v {
			return true
		}
	}
	return false
}

// passwordTaken — login faqat parol bilan, shuning uchun parol yagona bo'lishi shart.
func passwordTaken(db *sql.DB, password string, exceptID int) bool {
	var n int
	db.QueryRow("SELECT COUNT(*) FROM users WHERE password = ? AND id != ?", password, exceptID).Scan(&n)
	return n > 0
}

// requireOwner — faqat worker o'z sotrudniklarini boshqaradi.
func requireOwner(w http.ResponseWriter, r *http.Request) (int, bool) {
	if r.Header.Get("Role") != RoleWorker {
		respondJSON(w, http.StatusForbidden, map[string]interface{}{"success": false, "error": "Ruxsat yo'q"})
		return 0, false
	}
	ownerID, _ := strconv.Atoi(r.Header.Get("UserID"))
	return ownerID, ownerID > 0
}

// ownedEmployeeID — URL dagi {id} shu workerning sotrudnikimi.
func ownedEmployeeID(w http.ResponseWriter, r *http.Request, db *sql.DB, ownerID int) (int, bool) {
	id, _ := strconv.Atoi(mux.Vars(r)["id"])
	if id == 0 || employeeOwner(db, id) != ownerID {
		respondJSON(w, http.StatusNotFound, map[string]interface{}{"success": false, "error": "Сотрудник topilmadi"})
		return 0, false
	}
	return id, true
}

// GET /api/my/employees
func getMyEmployees(w http.ResponseWriter, r *http.Request) {
	ownerID, ok := requireOwner(w, r)
	if !ok {
		return
	}
	db, _ := getMainDB()
	defer db.Close()

	rows, err := db.Query("SELECT id, username, login, COALESCE(password, '') FROM users WHERE owner_id = ? AND role = ? ORDER BY id",
		ownerID, RoleEmployee)
	if err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]interface{}{"success": false, "error": "Server xatosi"})
		return
	}
	employees := []Employee{}
	for rows.Next() {
		var e Employee
		rows.Scan(&e.ID, &e.Username, &e.Login, &e.Password)
		employees = append(employees, e)
	}
	rows.Close()
	for i := range employees {
		employees[i].TemplateIDs = employeeTemplateIDs(db, ownerID, employees[i].ID)
	}
	respondJSON(w, http.StatusOK, map[string]interface{}{"success": true, "data": employees})
}

// POST /api/my/employees {username, login, password}
func createMyEmployee(w http.ResponseWriter, r *http.Request) {
	ownerID, ok := requireOwner(w, r)
	if !ok {
		return
	}
	var req struct {
		Username string `json:"username"`
		Login    string `json:"login"`
		Password string `json:"password"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		respondJSON(w, http.StatusBadRequest, map[string]interface{}{"success": false, "error": "Noto'g'ri ma'lumot"})
		return
	}
	req.Username = strings.TrimSpace(req.Username)
	req.Login = strings.TrimSpace(req.Login)
	req.Password = strings.TrimSpace(req.Password)
	if req.Username == "" || req.Login == "" || len(req.Password) < 4 {
		respondJSON(w, http.StatusBadRequest, map[string]interface{}{"success": false, "error": "Имя, логин и пароль (мин. 4 символа) обязательны"})
		return
	}

	db, _ := getMainDB()
	defer db.Close()
	if passwordTaken(db, req.Password, 0) {
		respondJSON(w, http.StatusBadRequest, map[string]interface{}{"success": false, "error": "Этот пароль уже занят, придумайте другой"})
		return
	}

	hash, _ := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	result, err := db.Exec(`INSERT INTO users (username, login, password_hash, password, role, filial_ids, categories, owner_id)
		VALUES (?, ?, ?, ?, ?, '', '[]', ?)`,
		req.Username, req.Login, string(hash), req.Password, RoleEmployee, ownerID)
	if err != nil {
		respondJSON(w, http.StatusBadRequest, map[string]interface{}{"success": false, "error": "Этот логин уже занят"})
		return
	}
	id, _ := result.LastInsertId()
	respondJSON(w, http.StatusCreated, map[string]interface{}{"success": true, "userId": id})
}

// PUT /api/my/employees/{id} {username?, password?}
func updateMyEmployee(w http.ResponseWriter, r *http.Request) {
	ownerID, ok := requireOwner(w, r)
	if !ok {
		return
	}
	db, _ := getMainDB()
	defer db.Close()
	id, ok := ownedEmployeeID(w, r, db, ownerID)
	if !ok {
		return
	}
	var req struct {
		Username string `json:"username"`
		Password string `json:"password"`
	}
	json.NewDecoder(r.Body).Decode(&req)
	req.Username = strings.TrimSpace(req.Username)
	req.Password = strings.TrimSpace(req.Password)

	if req.Username != "" {
		db.Exec("UPDATE users SET username = ? WHERE id = ?", req.Username, id)
	}
	if req.Password != "" {
		if len(req.Password) < 4 {
			respondJSON(w, http.StatusBadRequest, map[string]interface{}{"success": false, "error": "Пароль минимум 4 символа"})
			return
		}
		if passwordTaken(db, req.Password, id) {
			respondJSON(w, http.StatusBadRequest, map[string]interface{}{"success": false, "error": "Этот пароль уже занят, придумайте другой"})
			return
		}
		hash, _ := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
		db.Exec("UPDATE users SET password = ?, password_hash = ? WHERE id = ?", req.Password, string(hash), id)
	}
	respondJSON(w, http.StatusOK, map[string]interface{}{"success": true})
}

// DELETE /api/my/employees/{id}
func deleteMyEmployee(w http.ResponseWriter, r *http.Request) {
	ownerID, ok := requireOwner(w, r)
	if !ok {
		return
	}
	db, _ := getMainDB()
	defer db.Close()
	id, ok := ownedEmployeeID(w, r, db, ownerID)
	if !ok {
		return
	}
	db.Exec("DELETE FROM task_delegations WHERE employee_id = ?", id)
	db.Exec("DELETE FROM users WHERE id = ?", id)
	hub.broadcast("task_updated", map[string]interface{}{"action": "delegation_changed"})
	respondJSON(w, http.StatusOK, map[string]interface{}{"success": true})
}

// PUT /api/my/delegations/{templateId} {employeeIds: [...]}
// Vazifani tanlangan sotrudniklarga biriktiradi (bo'sh ro'yxat — hammasidan olinadi).
func setTaskDelegation(w http.ResponseWriter, r *http.Request) {
	ownerID, ok := requireOwner(w, r)
	if !ok {
		return
	}
	templateID, _ := strconv.Atoi(mux.Vars(r)["templateId"])
	var req struct {
		EmployeeIDs []int `json:"employeeIds"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || templateID == 0 {
		respondJSON(w, http.StatusBadRequest, map[string]interface{}{"success": false, "error": "Noto'g'ri ma'lumot"})
		return
	}

	db, _ := getMainDB()
	defer db.Close()

	// Worker faqat o'zi ko'radigan vazifani bera oladi
	var tplFilials, tplCategory string
	if err := db.QueryRow("SELECT filial_ids, category FROM task_templates WHERE id = ?", templateID).
		Scan(&tplFilials, &tplCategory); err != nil {
		respondJSON(w, http.StatusNotFound, map[string]interface{}{"success": false, "error": "Vazifa topilmadi"})
		return
	}
	var ownerFilials, ownerCategories sql.NullString
	db.QueryRow("SELECT filial_ids, categories FROM users WHERE id = ?", ownerID).Scan(&ownerFilials, &ownerCategories)
	sharesFilial := false
	for _, fid := range parseFilialIDs(tplFilials) {
		if containsInt(parseFilialIDs(ownerFilials.String), fid) {
			sharesFilial = true
			break
		}
	}
	var cats []string
	json.Unmarshal([]byte(ownerCategories.String), &cats)
	categoryOK := len(cats) == 0 || tplCategory == ""
	for _, c := range cats {
		if c == tplCategory {
			categoryOK = true
		}
	}
	if !sharesFilial || !categoryOK {
		respondJSON(w, http.StatusForbidden, map[string]interface{}{"success": false, "error": "Это не ваша задача"})
		return
	}

	for _, eid := range req.EmployeeIDs {
		if employeeOwner(db, eid) != ownerID {
			respondJSON(w, http.StatusForbidden, map[string]interface{}{"success": false, "error": "Сотрудник topilmadi"})
			return
		}
	}

	tx, err := db.Begin()
	if err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]interface{}{"success": false, "error": "Database xatosi"})
		return
	}
	defer tx.Rollback()
	tx.Exec("DELETE FROM task_delegations WHERE owner_id = ? AND template_id = ?", ownerID, templateID)
	for _, eid := range req.EmployeeIDs {
		tx.Exec("INSERT OR IGNORE INTO task_delegations (owner_id, employee_id, template_id) VALUES (?, ?, ?)",
			ownerID, eid, templateID)
	}
	if err := tx.Commit(); err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]interface{}{"success": false, "error": "Server xatosi"})
		return
	}

	hub.broadcast("task_updated", map[string]interface{}{"action": "delegation_changed", "templateId": templateID})
	respondJSON(w, http.StatusOK, map[string]interface{}{"success": true, "employeeIds": req.EmployeeIDs})
}

// employeeAudioAllowed — sotrudnik ovozli izohni faqat o'ziga biriktirilgan vazifaga qoldiradi.
func employeeAudioAllowed(w http.ResponseWriter, r *http.Request, taskID string, date time.Time) bool {
	if r.Header.Get("Role") != RoleEmployee {
		return true
	}
	employeeID, _ := strconv.Atoi(r.Header.Get("UserID"))
	if employeeCanAccessTask(employeeID, taskID, date) {
		return true
	}
	respondJSON(w, http.StatusForbidden, map[string]interface{}{"success": false, "error": "Bu vazifa sizga biriktirilmagan"})
	return false
}
