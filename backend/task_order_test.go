package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"sort"
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
	// Ilova kabi: filial tabi shaxsiy kalit bo'yicha saralanadi (bo'lsa)
	sort.SliceStable(inTab, func(a, b int) bool {
		pa, okA := inTab[a].Positions[filialID]
		pb, okB := inTab[b].Positions[filialID]
		return okA && okB && pa < pb
	})
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

// Bosh sahifa va «Все задачи» bir xil ketma-ketlikda bo'lishi kerak:
// umumiy tartib va shaxsiy tartib — ikkalasida ham bir xil qo'llanadi.
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
	createTemplate(t, `{"task":"C","type":1,"filialIds":[1],"category":""}`)
	createTemplate(t, `{"task":"C","type":1,"filialIds":[2],"category":""}`)

	expectSameOrder(t, 1, RoleSuperAdmin, 1, "3,2,1")
	expectSameOrder(t, 1, RoleSuperAdmin, 2, "4")

	// Super admin bosh sahifada sudradi — ikkala sahifa ham yangi tartibda,
	// umumiy tartib ham shu bo'ladi (boshqa foydalanuvchi ham shuni ko'radi).
	savePersonalOrder(t, 1, RoleSuperAdmin, "1,3,2")
	expectSameOrder(t, 1, RoleSuperAdmin, 1, "1,3,2")
	expectSameOrder(t, 2, RoleSuperAdmin, 1, "1,3,2")
	expectSameOrder(t, 2, RoleSuperAdmin, 2, "4")

	// Checker'ning shaxsiy tartibi faqat o'ziga ta'sir qiladi.
	savePersonalOrder(t, 5, RoleChecker, "2,1,3")
	expectSameOrder(t, 5, RoleChecker, 1, "2,1,3")
	expectSameOrder(t, 2, RoleSuperAdmin, 1, "1,3,2")

	// Eski versiyada qadalgan vazifa endi tepaga chiqmaydi - faqat shaxsiy tartib.
	mainDB, _ = getMainDB()
	mainDB.Exec("INSERT INTO user_task_prefs (user_id, template_id, pinned) VALUES (2, 2, 1) ON CONFLICT(user_id, template_id) DO UPDATE SET pinned = 1")
	mainDB.Close()
	expectSameOrder(t, 2, RoleSuperAdmin, 1, "1,3,2")
}

// Shaxsiy tartib har bir filial uchun alohida; tartib qayta so'ralganda (qayta kirish)
// ham saqlanib qoladi va ikkala sahifada bir xil.
func TestPersonalOrderIsPerFilial(t *testing.T) {
	wd, _ := os.Getwd()
	os.Chdir(t.TempDir())
	t.Cleanup(func() { os.Chdir(wd) })
	initDB()

	mainDB, _ := getMainDB()
	mainDB.Exec("INSERT INTO users (username, login, password_hash, role, filial_ids, categories) VALUES ('W', 'w', 'x', ?, '1,2', '[\"X\"]')", RoleWorker)
	mainDB.Exec("INSERT INTO users (username, login, password_hash, role, filial_ids, can_manage_tasks) VALUES ('C', 'c', 'x', ?, '1,2', 1)", RoleChecker)
	var checker int
	mainDB.QueryRow("SELECT id FROM users WHERE login = 'c'").Scan(&checker)
	mainDB.Close()

	createTemplate(t, `{"task":"A","type":1,"filialIds":[1],"category":""}`)
	createTemplate(t, `{"task":"B","type":1,"filialIds":[1],"category":""}`)
	createTemplate(t, `{"task":"C","type":1,"filialIds":[1],"category":""}`)
	createTemplate(t, `{"task":"D","type":1,"filialIds":[2],"category":""}`)
	createTemplate(t, `{"task":"E","type":1,"filialIds":[2],"category":""}`)

	expect := func(filialID int, want string) {
		t.Helper()
		if got := mainPageOrder(t, checker, RoleChecker, filialID); got != want {
			t.Fatalf("filial %d — bosh sahifa: %s, kutilgan: %s", filialID, got, want)
		}
		if got := editPageOrder(t, checker, RoleChecker, filialID); got != want {
			t.Fatalf("filial %d — «Все задачи»: %s, kutilgan: %s", filialID, got, want)
		}
	}
	expect(1, "3,2,1")
	expect(2, "5,4")

	saveFilialOrderReq(t, checker, RoleChecker, 1, "1,2,3")
	saveFilialOrderReq(t, checker, RoleChecker, 2, "4,5")
	expect(1, "1,2,3")
	expect(2, "4,5")

	// Filtr bilan faqat bir qismi sudraldi — qolganlari joyida qoladi;
	// takrorlangan ID e'tiborga olinmaydi.
	saveFilialOrderReq(t, checker, RoleChecker, 1, "3,1,3")
	expect(1, "3,2,1")
	expect(2, "4,5")

	// Boshqa foydalanuvchiga ta'sir qilmaydi
	if got := mainPageOrder(t, 99, RoleChecker, 1); got != "3,2,1" {
		t.Fatalf("boshqa foydalanuvchi: %s", got)
	}

	// Yangi shablon shaxsiy tartibi bor filialda oxirida chiqadi
	createTemplate(t, `{"task":"F","type":1,"filialIds":[1],"category":""}`)
	expect(1, "3,2,1,6")
}
