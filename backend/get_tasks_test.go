package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"strconv"
	"testing"
	"time"
)

// Worker: filial bor, lekin kategoriya tanlanmagan — hech qanday vazifa
// ko'rmaydi. Kategoriya tanlangach — kategoriyasiz va o'z kategoriyasidagi
// vazifalarni ko'radi, boshqa kategoriyadagini ko'rmaydi.
func TestGetTasksWorkerWithoutCategories(t *testing.T) {
	wd, _ := os.Getwd()
	os.Chdir(t.TempDir())
	t.Cleanup(func() { os.Chdir(wd) })
	initDB()

	mainDB, _ := getMainDB()
	defer mainDB.Close()
	res, err := mainDB.Exec(`INSERT INTO users (username, login, password_hash, password, role, filial_ids, categories)
		VALUES ('Ali', 'ali', '', '1111', ?, '1', '[]')`, RoleWorker)
	if err != nil {
		t.Fatalf("user: %v", err)
	}
	userID, _ := res.LastInsertId()

	taskDB, err := getTaskDB(time.Now())
	if err != nil {
		t.Fatalf("task db: %v", err)
	}
	taskDB.Exec(`INSERT INTO tasks (template_id, filial_id, task, type, category, order_index) VALUES (1, 1, 'Svet', 1, '', 1)`)
	taskDB.Exec(`INSERT INTO tasks (template_id, filial_id, task, type, category, order_index) VALUES (2, 1, 'Kassa', 1, 'Kassa', 2)`)
	taskDB.Exec(`INSERT INTO tasks (template_id, filial_id, task, type, category, order_index) VALUES (3, 1, 'Oshxona', 1, 'Oshxona', 3)`)
	taskDB.Close()

	fetch := func() []string {
		req := httptest.NewRequest(http.MethodGet, "/api/tasks", nil)
		req.Header.Set("Role", RoleWorker)
		req.Header.Set("UserID", strconv.FormatInt(userID, 10))
		rec := httptest.NewRecorder()
		getTasks(rec, req)
		var body struct {
			Success bool   `json:"success"`
			Data    []Task `json:"data"`
		}
		if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil || !body.Success {
			t.Fatalf("javob: %s", rec.Body.String())
		}
		names := []string{}
		for _, task := range body.Data {
			names = append(names, task.Task)
		}
		return names
	}

	if got := fetch(); len(got) != 0 {
		t.Fatalf("kategoriya tanlanmagan — bo'sh bo'lishi kerak, olindi: %v", got)
	}

	mainDB.Exec(`UPDATE users SET categories = '["Kassa"]' WHERE id = ?`, userID)
	if got := fetch(); len(got) != 2 || got[0] != "Svet" || got[1] != "Kassa" {
		t.Fatalf("'Kassa' tanlangan — Svet + Kassa kutilgan, olindi: %v", got)
	}
}
