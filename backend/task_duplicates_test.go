package main

import (
	"os"
	"testing"
	"time"
)

// Shablon kategoriyasi o'zgarganda (tahrirlash / kategoriya o'chirilishi)
// refresh dublikat yaratmasligi, mavjud vazifani yangilashi kerak.
func TestRefreshDoesNotDuplicateTaskAfterCategoryChange(t *testing.T) {
	wd, _ := os.Getwd()
	os.Chdir(t.TempDir())
	t.Cleanup(func() { os.Chdir(wd) })
	initDB()

	mainDB, _ := getMainDB()
	mainDB.Exec("INSERT INTO users (username, login, password_hash, role, filial_ids, categories) VALUES ('W', 'w', 'x', ?, '1', '[\"Kassa\"]')", RoleWorker)
	mainDB.Close()

	createTemplate(t, `{"task":"A","type":1,"filialIds":[1],"category":"Kassa"}`)

	// Kategoriya o'chirildi: shablonda '' bo'ldi, bugungi vazifada eski nom qoldi
	mainDB, _ = getMainDB()
	mainDB.Exec("UPDATE task_templates SET category = '' WHERE id = 1")
	mainDB.Close()

	refreshTodayTasks()

	taskDB, _ := getTaskDB(time.Now())
	var count int
	var category string
	taskDB.QueryRow("SELECT COUNT(*) FROM tasks WHERE template_id = 1 AND filial_id = 1").Scan(&count)
	taskDB.QueryRow("SELECT category FROM tasks WHERE template_id = 1 AND filial_id = 1").Scan(&category)
	if count != 1 || category != "" {
		t.Fatalf("refresh'dan keyin: %d ta vazifa, kategoriya %q (kutilgan: 1 ta, '')", count, category)
	}

	// Avval yaratilib qolgan dublikatlar: bo'shi o'chadi, ma'lumotlisi qoladi
	taskDB.Exec("INSERT INTO tasks (template_id, filial_id, task, type, category) VALUES (1, 1, 'A', 1, 'Kassa')")
	taskDB.Exec("INSERT INTO tasks (template_id, filial_id, task, type, category, status) VALUES (1, 1, 'A', 1, 'Kassa', 2)")
	taskDB.Close()

	// Tozalashgacha ham bosh sahifa bitta karta ko'rsatadi
	if got := mainPageOrder(t, 1, RoleSuperAdmin, 1); got != "1" {
		t.Fatalf("dublikatlar bilan bosh sahifa: %s, kutilgan: 1", got)
	}

	refreshTodayTasks()

	taskDB, _ = getTaskDB(time.Now())
	defer taskDB.Close()
	var status int
	taskDB.QueryRow("SELECT COUNT(*) FROM tasks WHERE template_id = 1 AND filial_id = 1").Scan(&count)
	taskDB.QueryRow("SELECT COALESCE(status, -1) FROM tasks WHERE template_id = 1 AND filial_id = 1").Scan(&status)
	if count != 1 || status != 2 {
		t.Fatalf("tozalashdan keyin: %d ta vazifa, status %d (kutilgan: 1 ta, status 2)", count, status)
	}
}

func TestDedupeTasksKeepsRowWithData(t *testing.T) {
	st := 2
	tasks := []Task{
		{ID: 1, TemplateID: 5, FilialID: 1},
		{ID: 2, TemplateID: 5, FilialID: 1, Status: &st}, // ma'lumotlisi qoladi
		{ID: 3, TemplateID: 5, FilialID: 2},              // boshqa filial - alohida
		{ID: 4, TemplateID: 0, FilialID: 1},              // shablonsiz - tegilmaydi
		{ID: 5, TemplateID: 0, FilialID: 1},
	}
	got := dedupeTasks(tasks)
	want := []int{2, 3, 4, 5}
	if len(got) != len(want) {
		t.Fatalf("uzunlik: %d, kutilgan %d", len(got), len(want))
	}
	for i, id := range want {
		if got[i].ID != id {
			t.Fatalf("%d-o'rin: id %d, kutilgan %d", i, got[i].ID, id)
		}
	}
}
