package main

import (
	"database/sql"
	"encoding/json"
	"net/http"
	"path/filepath"
	"strings"
	"time"

	"github.com/gorilla/mux"
)

// Kategoriyalar nomi bo'yicha bog'langan: task_templates.category,
// tasks.category (kunlik bazalar) va users.categories (JSON massiv) —
// shuning uchun nom o'zgarsa, hammasi birga yangilanadi.

// migrateCategoryOrder — sort_order ustuni; eski bazada hammasi 0 bo'lsa,
// avvalgi ko'rinish (nom bo'yicha) saqlanib qoladi.
func migrateCategoryOrder(db *sql.DB) {
	db.Exec("ALTER TABLE categories ADD COLUMN sort_order INTEGER DEFAULT 0")
	var ordered int
	db.QueryRow("SELECT COUNT(*) FROM categories WHERE COALESCE(sort_order, 0) > 0").Scan(&ordered)
	if ordered > 0 {
		return
	}
	rows, err := db.Query("SELECT id FROM categories ORDER BY name ASC")
	if err != nil {
		return
	}
	var ids []int
	for rows.Next() {
		var id int
		rows.Scan(&id)
		ids = append(ids, id)
	}
	rows.Close()
	for i, id := range ids {
		db.Exec("UPDATE categories SET sort_order = ? WHERE id = ?", i+1, id)
	}
}

func respondCategoryError(w http.ResponseWriter, status int, msg string) {
	respondJSON(w, status, map[string]interface{}{
		"success": false,
		"error":   msg,
	})
}

func getCategories(w http.ResponseWriter, r *http.Request) {
	db, _ := getMainDB()
	defer db.Close()

	rows, err := db.Query("SELECT id, name FROM categories ORDER BY COALESCE(sort_order, 0), id")
	if err != nil {
		respondCategoryError(w, http.StatusInternalServerError, "Server xatosi")
		return
	}
	defer rows.Close()

	categories := []Category{}
	for rows.Next() {
		var c Category
		rows.Scan(&c.ID, &c.Name)
		categories = append(categories, c)
	}

	respondJSON(w, http.StatusOK, map[string]interface{}{
		"success": true,
		"data":    categories,
	})
}

func createCategory(w http.ResponseWriter, r *http.Request) {
	if r.Header.Get("Role") != RoleSuperAdmin {
		respondCategoryError(w, http.StatusForbidden, "Ruxsat yo'q")
		return
	}

	var req struct {
		Name string `json:"name"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || strings.TrimSpace(req.Name) == "" {
		respondCategoryError(w, http.StatusBadRequest, "Noto'g'ri ma'lumot")
		return
	}

	db, _ := getMainDB()
	defer db.Close()

	result, err := db.Exec(
		"INSERT INTO categories (name, sort_order) VALUES (?, (SELECT COALESCE(MAX(sort_order), 0) + 1 FROM categories))",
		strings.TrimSpace(req.Name))
	if err != nil {
		respondCategoryError(w, http.StatusBadRequest, "Bu category allaqachon mavjud")
		return
	}

	id, _ := result.LastInsertId()
	respondJSON(w, http.StatusCreated, map[string]interface{}{
		"success":    true,
		"categoryId": id,
	})
}

// reorderCategories — yangi tartib: {"categoryIds": [3, 1, 2, ...]}
func reorderCategories(w http.ResponseWriter, r *http.Request) {
	if r.Header.Get("Role") != RoleSuperAdmin {
		respondCategoryError(w, http.StatusForbidden, "Ruxsat yo'q")
		return
	}

	var req struct {
		CategoryIDs []int `json:"categoryIds"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || len(req.CategoryIDs) == 0 {
		respondCategoryError(w, http.StatusBadRequest, "Noto'g'ri ma'lumot")
		return
	}

	db, _ := getMainDB()
	defer db.Close()

	tx, err := db.Begin()
	if err != nil {
		respondCategoryError(w, http.StatusInternalServerError, "Server xatosi")
		return
	}
	for i, id := range req.CategoryIDs {
		if _, err := tx.Exec("UPDATE categories SET sort_order = ? WHERE id = ?", i+1, id); err != nil {
			tx.Rollback()
			respondCategoryError(w, http.StatusInternalServerError, "Server xatosi")
			return
		}
	}
	if err := tx.Commit(); err != nil {
		respondCategoryError(w, http.StatusInternalServerError, "Server xatosi")
		return
	}

	respondJSON(w, http.StatusOK, map[string]interface{}{"success": true})
}

// replaceUserCategory — users.categories JSON massivida nomni almashtiradi
// (newName bo'sh bo'lsa — olib tashlaydi). O'zgargan userlar sonini qaytaradi.
func replaceUserCategory(tx *sql.Tx, oldName, newName string) (int, error) {
	rows, err := tx.Query("SELECT id, categories FROM users WHERE categories LIKE ?", "%"+oldName+"%")
	if err != nil {
		return 0, err
	}
	type upd struct {
		id   int
		cats string
	}
	var updates []upd
	for rows.Next() {
		var id int
		var raw sql.NullString
		rows.Scan(&id, &raw)
		var cats []string
		if json.Unmarshal([]byte(raw.String), &cats) != nil {
			continue
		}
		next := make([]string, 0, len(cats))
		changed := false
		for _, c := range cats {
			if c == oldName {
				changed = true
				if newName == "" {
					continue
				}
				c = newName
			}
			next = append(next, c)
		}
		if changed {
			b, _ := json.Marshal(next)
			updates = append(updates, upd{id, string(b)})
		}
	}
	rows.Close()
	for _, u := range updates {
		if _, err := tx.Exec("UPDATE users SET categories = ? WHERE id = ?", u.cats, u.id); err != nil {
			return 0, err
		}
	}
	return len(updates), nil
}

// renameCategoryInTaskDBs — bugungi va keyingi kunlar bazalaridagi vazifalar
// (o'tgan kunlar tarix sifatida qoladi).
func renameCategoryInTaskDBs(oldName, newName string) {
	today := time.Now().Format("2006-01-02")
	files, _ := filepath.Glob("./db/tasks_*.db")
	for _, f := range files {
		date := strings.TrimSuffix(strings.TrimPrefix(filepath.Base(f), "tasks_"), ".db")
		if date < today {
			continue
		}
		taskDB, err := sql.Open("sqlite3", f)
		if err != nil {
			continue
		}
		taskDB.Exec("UPDATE tasks SET category = ? WHERE category = ?", newName, oldName)
		taskDB.Close()
	}
}

func updateCategory(w http.ResponseWriter, r *http.Request) {
	if r.Header.Get("Role") != RoleSuperAdmin {
		respondCategoryError(w, http.StatusForbidden, "Ruxsat yo'q")
		return
	}

	id := mux.Vars(r)["id"]

	var req struct {
		Name string `json:"name"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || strings.TrimSpace(req.Name) == "" {
		respondCategoryError(w, http.StatusBadRequest, "Noto'g'ri ma'lumot")
		return
	}
	newName := strings.TrimSpace(req.Name)

	db, _ := getMainDB()
	defer db.Close()

	var oldName string
	if err := db.QueryRow("SELECT name FROM categories WHERE id = ?", id).Scan(&oldName); err != nil {
		respondCategoryError(w, http.StatusNotFound, "Category topilmadi")
		return
	}
	if oldName == newName {
		respondJSON(w, http.StatusOK, map[string]interface{}{"success": true})
		return
	}

	tx, err := db.Begin()
	if err != nil {
		respondCategoryError(w, http.StatusInternalServerError, "Server xatosi")
		return
	}
	if _, err := tx.Exec("UPDATE categories SET name = ? WHERE id = ?", newName, id); err != nil {
		tx.Rollback()
		respondCategoryError(w, http.StatusBadRequest, "Bu category allaqachon mavjud")
		return
	}
	if _, err := tx.Exec("UPDATE task_templates SET category = ? WHERE category = ?", newName, oldName); err != nil {
		tx.Rollback()
		respondCategoryError(w, http.StatusInternalServerError, "Server xatosi")
		return
	}
	if _, err := replaceUserCategory(tx, oldName, newName); err != nil {
		tx.Rollback()
		respondCategoryError(w, http.StatusInternalServerError, "Server xatosi")
		return
	}
	if err := tx.Commit(); err != nil {
		respondCategoryError(w, http.StatusInternalServerError, "Server xatosi")
		return
	}
	renameCategoryInTaskDBs(oldName, newName)

	respondJSON(w, http.StatusOK, map[string]interface{}{"success": true})
}

// countUsersWithCategory — LIKE emas, aniq nom bo'yicha
// ("Admin" "Admin 2" ga ham mos tushib qolmasin)
func countUsersWithCategory(db *sql.DB, name string) int {
	rows, err := db.Query("SELECT categories FROM users WHERE categories LIKE ?", "%"+name+"%")
	if err != nil {
		return 0
	}
	defer rows.Close()
	count := 0
	for rows.Next() {
		var raw sql.NullString
		rows.Scan(&raw)
		var cats []string
		json.Unmarshal([]byte(raw.String), &cats)
		for _, c := range cats {
			if c == name {
				count++
				break
			}
		}
	}
	return count
}

// deleteCategory — kategoriya darhol o'chiriladi: userlardan olib tashlanadi,
// shablon va bugungi/keyingi vazifalarda kategoriya bo'shatiladi.
func deleteCategory(w http.ResponseWriter, r *http.Request) {
	if r.Header.Get("Role") != RoleSuperAdmin {
		respondCategoryError(w, http.StatusForbidden, "Ruxsat yo'q")
		return
	}

	id := mux.Vars(r)["id"]

	db, _ := getMainDB()
	defer db.Close()

	var name string
	if err := db.QueryRow("SELECT name FROM categories WHERE id = ?", id).Scan(&name); err != nil {
		respondCategoryError(w, http.StatusNotFound, "Category topilmadi")
		return
	}

	tx, err := db.Begin()
	if err != nil {
		respondCategoryError(w, http.StatusInternalServerError, "Server xatosi")
		return
	}
	if _, err := tx.Exec("UPDATE task_templates SET category = '' WHERE category = ?", name); err != nil {
		tx.Rollback()
		respondCategoryError(w, http.StatusInternalServerError, "Server xatosi")
		return
	}
	if _, err := replaceUserCategory(tx, name, ""); err != nil {
		tx.Rollback()
		respondCategoryError(w, http.StatusInternalServerError, "Server xatosi")
		return
	}
	if _, err := tx.Exec("DELETE FROM categories WHERE id = ?", id); err != nil {
		tx.Rollback()
		respondCategoryError(w, http.StatusInternalServerError, "Server xatosi")
		return
	}
	if err := tx.Commit(); err != nil {
		respondCategoryError(w, http.StatusInternalServerError, "Server xatosi")
		return
	}
	renameCategoryInTaskDBs(name, "")

	respondJSON(w, http.StatusOK, map[string]interface{}{
		"success": true,
		"message": "Category o'chirildi",
	})
}
