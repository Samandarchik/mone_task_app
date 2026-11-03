package main

import (
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/gorilla/mux"
)

// Shablon o'chirilsa yoki boshqa filialga ko'chirilsa, bugungi bo'sh nusxasi
// tekshiruvchida «bajarilmagan» bo'lib qolmasligi kerak. Videosi borlari
// tarix sifatida qoladi.
func TestOrphanTodayTasksAreRemoved(t *testing.T) {
	wd, _ := os.Getwd()
	os.Chdir(t.TempDir())
	t.Cleanup(func() { os.Chdir(wd) })
	initDB()

	mainDB, _ := getMainDB()
	mainDB.Exec("INSERT INTO users (username, login, password_hash, role, filial_ids, categories) VALUES ('W', 'w', 'x', ?, '1,2', '[\"Kassa\"]')", RoleWorker)
	mainDB.Close()

	createTemplate(t, `{"task":"O'chiriladi","type":1,"filialIds":[1],"category":"Kassa"}`)
	createTemplate(t, `{"task":"Videoli","type":1,"filialIds":[1],"category":"Kassa"}`)
	createTemplate(t, `{"task":"Ko'chadi","type":1,"filialIds":[1],"category":"Kassa"}`)
	createTemplate(t, `{"task":"Qoladi","type":1,"filialIds":[1],"category":"Kassa"}`)
	refreshTodayTasks()

	taskDB, _ := getTaskDB(time.Now())
	defer taskDB.Close()
	taskDB.Exec(`UPDATE tasks SET video_url = '["v.mp4"]' WHERE template_id = 2`)

	deleteTemplate := func(id string) {
		req := httptest.NewRequest(http.MethodDelete, "/api/tasks/"+id, nil)
		req.Header.Set("Role", RoleSuperAdmin)
		req = mux.SetURLVars(req, map[string]string{"id": id})
		rec := httptest.NewRecorder()
		deleteTask(rec, req)
		if rec.Code != http.StatusOK {
			t.Fatalf("deleteTask %s: %d %s", id, rec.Code, rec.Body.String())
		}
	}
	deleteTemplate("1")
	deleteTemplate("2")

	// 3-shablon 2-filialga ko'chirildi
	req := httptest.NewRequest(http.MethodPut, "/api/tasks/3",
		strings.NewReader(`{"task":"Ko'chadi","type":1,"filialIds":[2],"category":"Kassa"}`))
	req.Header.Set("Role", RoleSuperAdmin)
	req = mux.SetURLVars(req, map[string]string{"id": "3"})
	rec := httptest.NewRecorder()
	updateTask(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("updateTask: %d %s", rec.Code, rec.Body.String())
	}
	refreshTodayTasks()

	got := map[string]int{}
	rows, _ := taskDB.Query("SELECT task, filial_id FROM tasks")
	for rows.Next() {
		var name string
		var filial int
		rows.Scan(&name, &filial)
		got[name] = filial
	}
	rows.Close()

	if _, ok := got["O'chiriladi"]; ok {
		t.Error("o'chirilgan shablonning bo'sh vazifasi qolib ketdi")
	}
	if got["Videoli"] != 1 {
		t.Error("videosi bor vazifa o'chmasligi kerak edi")
	}
	if got["Ko'chadi"] != 2 {
		t.Errorf("ko'chirilgan vazifa 2-filialda bo'lishi kerak: %v", got)
	}
	if got["Qoladi"] != 1 {
		t.Errorf("tegilmagan oddiy vazifa qolishi kerak: %v", got)
	}
	if len(got) != 3 {
		t.Errorf("kutilgan 3 ta vazifa: %v", got)
	}
}

// Filial o'chirilsa — bo'sh vazifa tushadi, videolisi qoladi; DB'da shablon
// hali bor bo'lsa (shu orada yaratilgan) — tegilmaydi.
func TestOrphanCheckForDeletedFilial(t *testing.T) {
	wd, _ := os.Getwd()
	os.Chdir(t.TempDir())
	t.Cleanup(func() { os.Chdir(wd) })
	initDB()

	mainDB, _ := getMainDB()
	defer mainDB.Close()
	mainDB.Exec("INSERT INTO task_templates (id, task, type, filial_ids, category) VALUES (50, 'A', 1, '2', ''), (51, 'B', 1, '2', '')")
	taskDB, _ := getTaskDB(time.Now())
	defer taskDB.Close()
	taskDB.Exec(`INSERT INTO tasks (template_id, filial_id, task, type, category) VALUES (50, 2, 'A', 1, '')`)
	taskDB.Exec(`INSERT INTO tasks (template_id, filial_id, task, type, category, video_url) VALUES (51, 2, 'B', 1, '', '["v.mp4"]')`)

	if isOrphanTask(mainDB, 50, 2) {
		t.Fatal("shablon va filial bor — yetim emas")
	}
	mainDB.Exec("DELETE FROM filials WHERE id = 2")
	if !isOrphanTask(mainDB, 50, 2) {
		t.Fatal("filial o'chgan — yetim bo'lishi kerak")
	}
	removeUntouchedOrphans(mainDB, taskDB)

	var left []string
	rows, _ := taskDB.Query("SELECT task FROM tasks ORDER BY task")
	for rows.Next() {
		var s string
		rows.Scan(&s)
		left = append(left, s)
	}
	rows.Close()
	if len(left) != 1 || left[0] != "B" {
		t.Fatalf("faqat videoli 'B' qolishi kerak: %v", left)
	}
}
