package main

// Kategoriyalar ("kim qilishi kerak") ro'yxatini yangilash:
//   1. Утренний админ  (eski: Bar)
//   2. Вечерний админ  (eski: Magazin)
//   3. Шеф повар       (eski: Povar)
//
// Kategoriyalar vazifa va xodimlarga NOM bo'yicha bog'langan (task_templates,
// users.categories, kunlik tasks/voice_tasks), shuning uchun nom hamma joyda
// birga o'zgartiriladi. Migratsiya bir marta ishlaydi (app_migrations).

import (
	"database/sql"
	"encoding/json"
	"log"
	"os"
	"path/filepath"
	"strings"
)

const categoriesMigrationName = "categories_admin_shift_v1"

// defaultCategories — tartib bo'yicha (sort_order = index + 1).
var defaultCategories = []string{
	"Утренний админ",
	"Вечерний админ",
	"Шеф повар",
}

// oldCategoryRename — eski nom (kichik harfda) → yangi nom.
var oldCategoryRename = map[string]string{
	"bar":     "Утренний админ",
	"бар":     "Утренний админ",
	"magazin": "Вечерний админ",
	"магазин": "Вечерний админ",
	"povar":   "Шеф повар",
	"повар":   "Шеф повар",
}

func migrateCategories(db *sql.DB) {
	db.Exec("ALTER TABLE categories ADD COLUMN sort_order INTEGER DEFAULT 0")
	db.Exec("CREATE TABLE IF NOT EXISTS app_migrations (name TEXT PRIMARY KEY)")

	var done int
	db.QueryRow("SELECT COUNT(*) FROM app_migrations WHERE name = ?", categoriesMigrationName).Scan(&done)
	if done > 0 {
		return
	}

	// Eski nom → yangi nom (bazada aynan qanday yozilgan bo'lsa).
	rename := map[string]string{}
	rows, err := db.Query("SELECT name FROM categories")
	if err != nil {
		log.Printf("Categories migration: %v\n", err)
		return
	}
	var existing []string
	for rows.Next() {
		var name string
		rows.Scan(&name)
		existing = append(existing, name)
	}
	rows.Close()
	for _, name := range existing {
		if newName, ok := oldCategoryRename[strings.ToLower(strings.TrimSpace(name))]; ok {
			rename[name] = newName
		}
	}

	// Ro'yxatni qaytadan yaratish: faqat 3 ta yangi kategoriya.
	db.Exec("DELETE FROM categories")
	for i, name := range defaultCategories {
		db.Exec("INSERT INTO categories (name, sort_order) VALUES (?, ?)", name, i+1)
	}

	for oldName, newName := range rename {
		db.Exec("UPDATE task_templates SET category = ? WHERE category = ?", newName, oldName)
	}
	migrateUserCategories(db, rename)
	migrateDailyTaskCategories(rename)

	db.Exec("INSERT INTO app_migrations (name) VALUES (?)", categoriesMigrationName)
	log.Printf("Categories migrated: %v\n", rename)
}

// migrateUserCategories — users.categories (JSON massiv) dagi nomlarni almashtirish.
func migrateUserCategories(db *sql.DB, rename map[string]string) {
	rows, err := db.Query("SELECT id, categories FROM users WHERE categories IS NOT NULL AND categories != ''")
	if err != nil {
		return
	}
	type userCats struct {
		id   int
		cats []string
	}
	var users []userCats
	for rows.Next() {
		var id int
		var s string
		rows.Scan(&id, &s)
		var cats []string
		if json.Unmarshal([]byte(s), &cats) == nil {
			users = append(users, userCats{id, cats})
		}
	}
	rows.Close()

	for _, u := range users {
		seen := map[string]bool{}
		updated := []string{}
		for _, c := range u.cats {
			if newName, ok := rename[c]; ok {
				c = newName
			}
			if !seen[c] {
				seen[c] = true
				updated = append(updated, c)
			}
		}
		b, _ := json.Marshal(updated)
		db.Exec("UPDATE users SET categories = ? WHERE id = ?", string(b), u.id)
	}
}

// migrateDailyTaskCategories — kunlik tasks_*.db fayllaridagi nomlarni almashtirish.
func migrateDailyTaskCategories(rename map[string]string) {
	if len(rename) == 0 {
		return
	}
	files, err := os.ReadDir("./db")
	if err != nil {
		return
	}
	for _, f := range files {
		if f.IsDir() || !strings.HasSuffix(f.Name(), ".db") || f.Name() == "main.db" {
			continue
		}
		db, err := sql.Open("sqlite3", filepath.Join("./db", f.Name()))
		if err != nil {
			continue
		}
		for oldName, newName := range rename {
			db.Exec("UPDATE tasks SET category = ? WHERE category = ?", newName, oldName)
			db.Exec("UPDATE voice_tasks SET category = ? WHERE category = ?", newName, oldName)
		}
		db.Close()
	}
}
