package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
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
	inTab := []TaskTemplate{}
	for _, tpl := range resp.Data {
		inFilial := len(tpl.FilialIDs) == 0
		for _, id := range tpl.FilialIDs {
			if id == filialID {
				inFilial = true
			}
		}
		if inFilial {
			inTab = append(inTab, tpl)
		}
	}
	ids := []string{}
	for _, tpl := range inTab {
		ids = append(ids, fmt.Sprint(tpl.ID))
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

func saveFilialOrderReq(t *testing.T, userID int, role string, filialID int, order string) {
	t.Helper()
	body := fmt.Sprintf(`{"filialId": %d, "order": [%s]}`, filialID, order)
	req := httptest.NewRequest(http.MethodPut, "/api/task-prefs/order", strings.NewReader(body))
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

// Tartib hamma uchun bitta: kim sudrasa (super admin yoki filialga kirish
// huquqi bor foydalanuvchi) - bosh sahifa ham, «Все задачи» ham, boshqa
// foydalanuvchilar ham shu tartibni ko'radi. Qayta so'ralganda (qayta kirish)
// o'zgarmaydi.
func TestOrderIsSharedForEveryone(t *testing.T) {
	wd, _ := os.Getwd()
	os.Chdir(t.TempDir())
	t.Cleanup(func() { os.Chdir(wd) })
	initDB()

	mainDB, _ := getMainDB()
	mainDB.Exec("INSERT INTO users (username, login, password_hash, role, filial_ids, categories) VALUES ('W', 'w', 'x', ?, '1,2', '[\"X\"]')", RoleWorker)
	mainDB.Exec("INSERT INTO users (username, login, password_hash, role, filial_ids, can_manage_tasks) VALUES ('C', 'c', 'x', ?, '1,2', 1)", RoleChecker)
	mainDB.Exec("INSERT INTO users (username, login, password_hash, role, filial_ids) VALUES ('O', 'o', 'x', ?, '2')", RoleChecker)
	var checker, other int
	mainDB.QueryRow("SELECT id FROM users WHERE login = 'c'").Scan(&checker)
	mainDB.QueryRow("SELECT id FROM users WHERE login = 'o'").Scan(&other)
	mainDB.Close()

	// Har bir yangi shablon umumiy tartibda birinchi bo'ladi: 3,2,1.
	// Kunlik bazada esa order_index kategoriya bo'yicha alohida beriladi
	// (1: A=1, B=1, C=2) — eski kodda bosh sahifa 1,2,3 ko'rsatar edi.
	createTemplate(t, `{"task":"A","type":1,"filialIds":[1],"category":""}`)
	createTemplate(t, `{"task":"B","type":1,"filialIds":[1],"category":"X"}`)
	createTemplate(t, `{"task":"C","type":1,"filialIds":[1],"category":""}`)
	createTemplate(t, `{"task":"D","type":1,"filialIds":[2],"category":""}`)
	createTemplate(t, `{"task":"E","type":1,"filialIds":[2],"category":""}`)

	expectAll := func(filialID int, want string) {
		t.Helper()
		expectSameOrder(t, 1, RoleSuperAdmin, filialID, want)
		if got := mainPageOrder(t, checker, RoleChecker, filialID); got != want {
			t.Fatalf("checker, filial %d: %s, kutilgan: %s", filialID, got, want)
		}
		if got := editPageOrder(t, checker, RoleChecker, filialID); got != want {
			t.Fatalf("checker «Все задачи», filial %d: %s, kutilgan: %s", filialID, got, want)
		}
	}
	expectAll(1, "3,2,1")
	expectAll(2, "5,4")

	// Super admin sudradi — hammada o'zgaradi
	saveFilialOrderReq(t, 1, RoleSuperAdmin, 1, "1,3,2")
	expectAll(1, "1,3,2")

	// Filialga kirish huquqi bor foydalanuvchi sudradi — super adminda ham
	saveFilialOrderReq(t, checker, RoleChecker, 1, "2,1,3")
	expectAll(1, "2,1,3")
	saveFilialOrderReq(t, checker, RoleChecker, 2, "4,5")
	expectAll(2, "4,5")
	expectAll(1, "2,1,3")

	// Filtr bilan faqat bir qismi sudraldi — qolganlari joyida; takror ID e'tiborsiz
	saveFilialOrderReq(t, checker, RoleChecker, 1, "3,2,3")
	expectAll(1, "3,1,2")

	// Filial 1 ga huquqi yo'q foydalanuvchi uning tartibini o'zgartira olmaydi
	saveFilialOrderReq(t, other, RoleChecker, 1, "1,2,3")
	expectAll(1, "3,1,2")

	// Eski versiyada qadalgan / shaxsiy tartib qoldiqlari ta'sir qilmaydi
	mainDB, _ = getMainDB()
	mainDB.Exec("INSERT INTO user_task_prefs (user_id, template_id, pinned, position) VALUES (?, 2, 1, 1)", checker)
	mainDB.Exec("INSERT INTO user_filial_task_order (user_id, filial_id, template_id, position) VALUES (?, 1, 2, 1)", checker)
	mainDB.Close()
	expectAll(1, "3,1,2")
}
