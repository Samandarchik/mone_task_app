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

func templateFilials(t *testing.T) map[int]string {
	t.Helper()
	mainDB, _ := getMainDB()
	defer mainDB.Close()
	rows, err := mainDB.Query("SELECT id, filial_ids FROM task_templates")
	if err != nil {
		t.Fatal(err)
	}
	defer rows.Close()
	out := map[int]string{}
	for rows.Next() {
		var id int
		var f string
		rows.Scan(&id, &f)
		out[id] = f
	}
	return out
}

// Bir nechta filial tanlab yaratilgan vazifa - har bir filial uchun alohida
// shablon (alohida ID), har birining bugungi vazifasi o'z shablonida.
func TestCreateTaskMakesOneTemplatePerFilial(t *testing.T) {
	wd, _ := os.Getwd()
	os.Chdir(t.TempDir())
	t.Cleanup(func() { os.Chdir(wd) })
	initDB()
	mainDB, _ := getMainDB()
	mainDB.Exec("INSERT INTO users (username, login, password_hash, role, filial_ids, categories) VALUES ('W', 'w', 'x', ?, '1,2', '[\"X\"]')", RoleWorker)
	mainDB.Close()

	createTemplate(t, `{"task":"Pol","type":1,"filialIds":[1,2,2],"category":""}`)

	got := templateFilials(t)
	if len(got) != 2 || got[1] != "1" || got[2] != "2" {
		t.Fatalf("shablonlar: %v, kutilgan: 1→1, 2→2", got)
	}
	if o := mainPageOrder(t, 1, RoleSuperAdmin, 1); o != "1" {
		t.Fatalf("filial 1 vazifasi: %s", o)
	}
	if o := mainPageOrder(t, 1, RoleSuperAdmin, 2); o != "2" {
		t.Fatalf("filial 2 vazifasi: %s", o)
	}

	// Filial tanlanmasa - xato
	req := httptest.NewRequest(http.MethodPost, "/api/tasks", strings.NewReader(`{"task":"X","type":1,"filialIds":[],"category":""}`))
	req.Header.Set("Role", RoleSuperAdmin)
	req.Header.Set("UserID", "1")
	rec := httptest.NewRecorder()
	createTask(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("filialsiz yaratish status: %d", rec.Code)
	}

	// Tahrirlashda ikkinchi filial qo'shib bo'lmaydi
	req = httptest.NewRequest(http.MethodPut, "/api/tasks/1", strings.NewReader(`{"task":"Pol","type":1,"filialIds":[1,2],"category":""}`))
	req = mux.SetURLVars(req, map[string]string{"id": "1"})
	req.Header.Set("Role", RoleSuperAdmin)
	req.Header.Set("UserID", "1")
	rec = httptest.NewRecorder()
	updateTask(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("ikki filialli tahrirlash status: %d", rec.Code)
	}
	if f := templateFilials(t)[1]; f != "1" {
		t.Fatalf("shablon 1 filiali o'zgardi: %s", f)
	}
}

// Eski bazadagi ko'p filialli shablon ishga tushganda alohida shablonlarga
// ajraladi; kunlik vazifa, shaxsiy tartib va biriktirishlar o'z filialidagi
// shablonga o'tadi. Qayta ishga tushirish hech narsani o'zgartirmaydi.
func TestSplitMultiFilialTemplates(t *testing.T) {
	wd, _ := os.Getwd()
	os.Chdir(t.TempDir())
	t.Cleanup(func() { os.Chdir(wd) })
	initDB()

	mainDB, _ := getMainDB()
	mainDB.Exec("INSERT INTO users (username, login, password_hash, role, filial_ids, categories) VALUES ('W', 'w', 'x', ?, '1,2,3,4,5', '[\"X\"]')", RoleWorker)
	mainDB.Exec(`INSERT INTO task_templates (id, task, type, filial_ids, category, notification_time, order_index, video_count)
		VALUES (10, 'Ikki filial', 1, '1,2', 'X', '09:00', 1, 3), (11, 'Bitta', 1, '1', 'X', '', 2, 1), (12, 'Hamma', 1, '', 'X', '', 3, 1)`)
	mainDB.Exec("INSERT INTO user_filial_task_order (user_id, filial_id, template_id, position) VALUES (7, 1, 10, 2), (7, 2, 10, 1)")
	mainDB.Exec("INSERT INTO task_delegations (owner_id, employee_id, template_id) VALUES (3, 4, 10)")
	mainDB.Close()
	createTasksForDate(10, "Ikki filial", TypeDaily, []int{1, 2}, nil, "X", "09:00", time.Now())

	splitMultiFilialTemplates()

	got := templateFilials(t)
	// 10: 1,2 → 10 (1) + yangi (2); 12: hamma (5 filial) → 12 (1) + 4 ta yangi
	if len(got) != 3+1+4 {
		t.Fatalf("shablonlar soni: %d (%v)", len(got), got)
	}
	newID := 0
	for id, f := range got {
		if strings.Contains(f, ",") || f == "" {
			t.Fatalf("shablon %d hali ko'p filialli: %q", id, f)
		}
		if id > 12 && f == "2" && newID == 0 {
			newID = id
		}
	}
	if got[10] != "1" || got[11] != "1" || got[12] != "1" {
		t.Fatalf("asl shablonlar: %v", got)
	}

	mainDB, _ = getMainDB()
	defer mainDB.Close()
	var task, notif string
	var videoCount, order10, orderNew int
	mainDB.QueryRow("SELECT task, notification_time, video_count, order_index FROM task_templates WHERE id = ?", newID).Scan(&task, &notif, &videoCount, &orderNew)
	mainDB.QueryRow("SELECT order_index FROM task_templates WHERE id = 10").Scan(&order10)
	if task != "Ikki filial" || notif != "09:00" || videoCount != 3 {
		t.Fatalf("nusxa to'liq emas: %q %q %d", task, notif, videoCount)
	}
	if orderNew != order10+1 {
		t.Fatalf("nusxa asl shablondan keyin turishi kerak: %d, %d", order10, orderNew)
	}

	taskDB, _ := getTaskDB(time.Now())
	defer taskDB.Close()
	byFilial := map[int]int{}
	rows, _ := taskDB.Query("SELECT filial_id, template_id FROM tasks")
	for rows.Next() {
		var f, tid int
		rows.Scan(&f, &tid)
		byFilial[f] = tid
	}
	rows.Close()
	if byFilial[1] != 10 || byFilial[2] != newID {
		t.Fatalf("kunlik vazifalar: %v, kutilgan 1→10, 2→%d", byFilial, newID)
	}

	var pos int
	mainDB.QueryRow("SELECT position FROM user_filial_task_order WHERE user_id = 7 AND filial_id = 2 AND template_id = ?", newID).Scan(&pos)
	if pos != 1 {
		t.Fatalf("filial 2 shaxsiy tartibi ko'chmadi")
	}
	var delegated int
	mainDB.QueryRow("SELECT COUNT(*) FROM task_delegations WHERE owner_id = 3 AND template_id IN (10, ?)", newID).Scan(&delegated)
	if delegated != 2 {
		t.Fatalf("biriktirish nusxalanmadi: %d", delegated)
	}
	if _, err := os.Stat("./db/main.db.before-template-split"); err != nil {
		t.Fatalf("zaxira nusxa yo'q: %v", err)
	}

	splitMultiFilialTemplates()
	if again := templateFilials(t); len(again) != len(got) {
		t.Fatalf("qayta ishga tushirish o'zgartirdi: %d → %d", len(got), len(again))
	}
}
