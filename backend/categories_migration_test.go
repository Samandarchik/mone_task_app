package main

import (
	"os"
	"testing"
	"time"
)

func TestMigrateCategoriesRenamesOldNames(t *testing.T) {
	wd, _ := os.Getwd()
	os.Chdir(t.TempDir())
	t.Cleanup(func() { os.Chdir(wd) })
	initDB()

	mainDB, _ := getMainDB()
	defer mainDB.Close()

	// Eski holat: Bar / Magazin / Povar, migratsiya hali ishlamagan
	mainDB.Exec("DELETE FROM categories")
	mainDB.Exec("DELETE FROM app_migrations")
	for _, name := range []string{"Bar", "Magazin", "Povar"} {
		mainDB.Exec("INSERT INTO categories (name) VALUES (?)", name)
	}
	mainDB.Exec(`INSERT INTO task_templates (task, type, filial_ids, category) VALUES ('Svet', 1, '1', 'Magazin')`)
	mainDB.Exec(`INSERT INTO users (username, login, password_hash, role, categories) VALUES ('w', 'w', 'x', 'worker', '["Bar","Povar"]')`)

	taskDB, _ := getTaskDB(time.Now())
	taskDB.Exec(`INSERT INTO tasks (filial_id, task, type, category) VALUES (1, 'Svet', 1, 'Povar')`)
	taskDB.Close()

	migrateCategories(mainDB)

	rows, _ := mainDB.Query("SELECT name FROM categories ORDER BY sort_order = 0, sort_order, id")
	var names []string
	for rows.Next() {
		var n string
		rows.Scan(&n)
		names = append(names, n)
	}
	rows.Close()
	if len(names) != 3 || names[0] != "Утренний админ" || names[1] != "Вечерний админ" || names[2] != "Шеф повар" {
		t.Fatalf("kategoriyalar: %v", names)
	}

	var templateCat, userCats, taskCat string
	mainDB.QueryRow("SELECT category FROM task_templates WHERE task = 'Svet'").Scan(&templateCat)
	mainDB.QueryRow("SELECT categories FROM users WHERE login = 'w'").Scan(&userCats)
	taskDB, _ = getTaskDB(time.Now())
	taskDB.QueryRow("SELECT category FROM tasks WHERE task = 'Svet'").Scan(&taskCat)
	taskDB.Close()

	if templateCat != "Вечерний админ" {
		t.Fatalf("template: %q", templateCat)
	}
	if userCats != `["Утренний админ","Шеф повар"]` {
		t.Fatalf("user: %s", userCats)
	}
	if taskCat != "Шеф повар" {
		t.Fatalf("task: %q", taskCat)
	}
}
