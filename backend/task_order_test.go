package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"

	"github.com/gorilla/mux"
)

// mainPageOrder — GET /api/tasks (bosh sahifa) javobidagi shablon ID lari,
// berilgan filial uchun, ekrandagi tartibda.
func mainPageOrder(t *testing.T, userID int, role string, filialID int) string {
	t.Helper()
	req := httptest.NewRequest(http.MethodGet, "/api/tasks", nil)
	req.Header.Set("Role", role)
	req.Header.Set("UserID", fmt.Sprint(userID))
	rec := httptest.NewRecorder()
	getTasks(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("GET /api/tasks status: %d", rec.Code)
	}
	var resp struct {
		Data []Task `json:"data"`
	}
	if err := json.NewDecoder(rec.Body).Decode(&resp); err != nil {
		t.Fatalf("javob o'qilmadi: %v", err)
	}
	ids := []string{}
	for _, task := range resp.Data {
		if task.FilialID == filialID {
			ids = append(ids, fmt.Sprint(task.TemplateID))
		}
	}
	return strings.Join(ids, ",")
}

// editPageOrder — GET /api/tasks/all («Все задачи») javobidagi shablon ID lari,
// berilgan filialga tegishlilari, ekrandagi tartibda.
func editPageOrder(t *testing.T, userID int, role string, filialID int) string {
	t.Helper()
	req := httptest.NewRequest(http.MethodGet, "/api/tasks/all", nil)
	req.Header.Set("Role", role)
	req.Header.Set("UserID", fmt.Sprint(userID))
	rec := httptest.NewRecorder()
	getAllTasks(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("GET /api/tasks/all status: %d", rec.Code)
	}
	var resp struct {
		Data []TaskTemplate `json:"data"`
	}
	if err := json.NewDecoder(rec.Body).Decode(&resp); err != nil {
		t.Fatalf("javob o'qilmadi: %v", err)
	}
	ids := []string{}
	for _, tpl := range resp.Data {
		inFilial := len(tpl.FilialIDs) == 0
		for _, id := range tpl.FilialIDs {
			if id == filialID {
				inFilial = true
			}
		}
		if inFilial {
			ids = append(ids, fmt.Sprint(tpl.ID))
		}
	}
	return strings.Join(ids, ",")
}

func createTemplate(t *testing.T, body string) {
	t.Helper()
	req := httptest.NewRequest(http.MethodPost, "/api/tasks", strings.NewReader(body))
	req.Header.Set("Role", RoleSuperAdmin)
	req.Header.Set("UserID", "1")
	rec := httptest.NewRecorder()
	createTask(rec, req)
	if rec.Code != http.StatusCreated {
		t.Fatalf("createTask status: %d (%s)", rec.Code, rec.Body.String())
	}
}

func savePersonalOrder(t *testing.T, userID int, role string, order string) {
	t.Helper()
	req := httptest.NewRequest(http.MethodPut, "/api/task-prefs/order", strings.NewReader(`{"order": [`+order+`]}`))
	req.Header.Set("Role", role)
	req.Header.Set("UserID", fmt.Sprint(userID))
	rec := httptest.NewRecorder()
	setTaskOrder(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("setTaskOrder status: %d", rec.Code)
	}
}

// expectSameOrder — ikkala sahifa ham aynan [want] tartibini bersin.
func expectSameOrder(t *testing.T, userID int, role string, filialID int, want string) {
	t.Helper()
	if got := mainPageOrder(t, userID, role, filialID); got != want {
		t.Fatalf("user %d, filial %d — bosh sahifa: %s, kutilgan: %s", userID, filialID, got, want)
	}
	if role == RoleSuperAdmin {
		if got := editPageOrder(t, userID, role, filialID); got != want {
			t.Fatalf("user %d, filial %d — «Все задачи»: %s, kutilgan: %s", userID, filialID, got, want)
		}
	}
}

// Bosh sahifa va «Все задачи» bir xil ketma-ketlikda bo'lishi kerak:
// umumiy tartib, shaxsiy tartib va pin — ikkalasida ham bir xil qo'llanadi.
func TestMainAndEditPagesShareOrder(t *testing.T) {
	wd, _ := os.Getwd()
	os.Chdir(t.TempDir())
	t.Cleanup(func() { os.Chdir(wd) })
	initDB()

	// Kunlik vazifa faqat ishchisi bor filialda yaratiladi
	mainDB, _ := getMainDB()
	mainDB.Exec("INSERT INTO users (username, login, password_hash, role, filial_ids, categories) VALUES ('W', 'w', 'x', ?, '1,2', '[\"X\"]')", RoleWorker)
	mainDB.Close()

	// Har bir yangi shablon umumiy tartibda birinchi bo'ladi: 3,2,1.
	// Kunlik bazada esa order_index kategoriya bo'yicha alohida beriladi
	// (1: A=1, B=1, C=2) — eski kodda bosh sahifa 1,2,3 ko'rsatar edi.
	createTemplate(t, `{"task":"A","type":1,"filialIds":[1],"category":""}`)
	createTemplate(t, `{"task":"B","type":1,"filialIds":[1],"category":"X"}`)
	createTemplate(t, `{"task":"C","type":1,"filialIds":[1,2],"category":""}`)

	expectSameOrder(t, 1, RoleSuperAdmin, 1, "3,2,1")
	expectSameOrder(t, 1, RoleSuperAdmin, 2, "3")

	// Super admin bosh sahifada sudradi — ikkala sahifa ham yangi tartibda,
	// umumiy tartib ham shu bo'ladi (boshqa foydalanuvchi ham shuni ko'radi).
	savePersonalOrder(t, 1, RoleSuperAdmin, "1,3,2")
	expectSameOrder(t, 1, RoleSuperAdmin, 1, "1,3,2")
	expectSameOrder(t, 2, RoleSuperAdmin, 1, "1,3,2")
	expectSameOrder(t, 2, RoleSuperAdmin, 2, "3")

	// Checker'ning shaxsiy tartibi faqat o'ziga ta'sir qiladi.
	savePersonalOrder(t, 5, RoleChecker, "2,1,3")
	expectSameOrder(t, 5, RoleChecker, 1, "2,1,3")
	expectSameOrder(t, 2, RoleSuperAdmin, 1, "1,3,2")

	// Pin — ikkala sahifada ham tepaga chiqadi.
	req := httptest.NewRequest(http.MethodPut, "/api/task-prefs/pin/2", strings.NewReader(`{"pinned": true}`))
	req = mux.SetURLVars(req, map[string]string{"templateId": "2"})
	req.Header.Set("Role", RoleSuperAdmin)
	req.Header.Set("UserID", "2")
	rec := httptest.NewRecorder()
	setTaskPin(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("setTaskPin status: %d", rec.Code)
	}
	expectSameOrder(t, 2, RoleSuperAdmin, 1, "2,1,3")
	// Boshqalarga pin ta'sir qilmaydi
	expectSameOrder(t, 1, RoleSuperAdmin, 1, "1,3,2")
}
