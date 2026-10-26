package main

import (
	"database/sql"
	"fmt"
	"io"
	"log"
	"os"
	"path/filepath"
	"strings"
)

// Har bir vazifa shabloni faqat BITTA filialga tegishli. Ilgari bitta shablon
// bir nechta filialga (yoki filial_ids bo'sh = hamma filialga) bog'lanar edi;
// splitMultiFilialTemplates bunday shablonni har bir filial uchun alohida
// shablonga ajratadi. Birinchi filial eski ID ni saqlaydi, qolganlari uchun
// nusxa yaratiladi va shu filialdagi kunlik vazifalar, shaxsiy tartib va
// sotrudnik biriktirishlari yangi ID ga o'tkaziladi. Bo'linadigan shablon
// qolmagach hech narsa qilmaydi (har ishga tushganda xavfsiz).
func splitMultiFilialTemplates() {
	mainDB, err := getMainDB()
	if err != nil {
		return
	}
	defer mainDB.Close()

	type tmpl struct {
		id      int
		filials []int
	}
	var todo []tmpl
	allFilials := allFilialIDs(mainDB)
	rows, err := mainDB.Query("SELECT id, COALESCE(filial_ids, '') FROM task_templates ORDER BY order_index ASC, id ASC")
	if err != nil {
		return
	}
	for rows.Next() {
		var id int
		var filialIDs string
		if rows.Scan(&id, &filialIDs) != nil {
			continue
		}
		ids := uniqueIDs(parseFilialIDs(filialIDs))
		if len(ids) == 0 {
			ids = allFilials
		}
		if len(ids) == 1 && strings.TrimSpace(filialIDs) == fmt.Sprint(ids[0]) {
			continue
		}
		if len(ids) > 0 {
			todo = append(todo, tmpl{id, ids})
		}
	}
	rows.Close()
	if len(todo) == 0 {
		return
	}

	backupFile("./db/main.db", "./db/main.db.before-template-split")

	// Nusxada filial_ids va id dan boshqa hamma ustun aynan ko'chiriladi
	cols := []string{}
	colRows, err := mainDB.Query("PRAGMA table_info(task_templates)")
	if err != nil {
		return
	}
	for colRows.Next() {
		var cid, notNull, pk int
		var name, typ string
		var def sql.NullString
		if colRows.Scan(&cid, &name, &typ, &notNull, &def, &pk) == nil && name != "id" && name != "filial_ids" {
			cols = append(cols, name)
		}
	}
	colRows.Close()
	colList := strings.Join(cols, ", ")

	// (eski ID, filial) → yangi ID
	type remap struct{ oldID, filialID, newID int }
	var remaps []remap

	tx, err := mainDB.Begin()
	if err != nil {
		return
	}
	defer tx.Rollback()
	for _, t := range todo {
		if _, err := tx.Exec("UPDATE task_templates SET filial_ids = ? WHERE id = ?", fmt.Sprint(t.filials[0]), t.id); err != nil {
			log.Printf("Template split: %v\n", err)
			return
		}
		for _, fid := range t.filials[1:] {
			res, err := tx.Exec(fmt.Sprintf("INSERT INTO task_templates (filial_ids, %s) SELECT ?, %s FROM task_templates WHERE id = ?", colList, colList),
				fmt.Sprint(fid), t.id)
			if err != nil {
				log.Printf("Template split: %v\n", err)
				return
			}
			newID, _ := res.LastInsertId()
			remaps = append(remaps, remap{t.id, fid, int(newID)})
		}
	}

	for _, m := range remaps {
		// Shaxsiy tartib: filialdagisi yangi ID ga, eskisi (filialsiz) nusxalanadi
		tx.Exec("UPDATE user_filial_task_order SET template_id = ? WHERE template_id = ? AND filial_id = ?", m.newID, m.oldID, m.filialID)
		tx.Exec(`INSERT OR IGNORE INTO user_task_prefs (user_id, template_id, pinned, position)
			SELECT user_id, ?, pinned, position FROM user_task_prefs WHERE template_id = ?`, m.newID, m.oldID)
		// Worker o'z sotrudnikiga biriktirgan vazifa har bir filialda qoladi
		tx.Exec(`INSERT OR IGNORE INTO task_delegations (owner_id, employee_id, template_id)
			SELECT owner_id, employee_id, ? FROM task_delegations WHERE template_id = ?`, m.newID, m.oldID)
	}

	// Umumiy tartib: nusxa asl shablondan keyin turadi, raqamlar ketma-ket
	idRows, err := tx.Query("SELECT id FROM task_templates ORDER BY order_index ASC, id ASC")
	if err != nil {
		return
	}
	var ordered []int
	for idRows.Next() {
		var id int
		if idRows.Scan(&id) == nil {
			ordered = append(ordered, id)
		}
	}
	idRows.Close()
	for i, id := range ordered {
		tx.Exec("UPDATE task_templates SET order_index = ? WHERE id = ?", i+1, id)
	}
	if err := tx.Commit(); err != nil {
		log.Printf("Template split: %v\n", err)
		return
	}

	// Kunlik bazalardagi vazifalar o'z filialidagi shablonga bog'lanadi
	dbFiles, _ := filepath.Glob("./db/tasks_*.db")
	for _, path := range dbFiles {
		taskDB, err := sql.Open("sqlite3", path)
		if err != nil {
			continue
		}
		for _, m := range remaps {
			taskDB.Exec("UPDATE tasks SET template_id = ? WHERE template_id = ? AND filial_id = ?", m.newID, m.oldID, m.filialID)
			taskDB.Exec("UPDATE voice_tasks SET template_id = ? WHERE template_id = ? AND filial_id = ?", m.newID, m.oldID, m.filialID)
		}
		taskDB.Close()
	}
	log.Printf("Template split: %d ta shablon filiallar bo'yicha ajratildi (%d ta yangi)\n", len(todo), len(remaps))
}

// backupFile - migratsiyadan oldingi nusxa (bo'lsa qayta yozilmaydi).
func backupFile(src, dst string) {
	if _, err := os.Stat(dst); err == nil {
		return
	}
	in, err := os.Open(src)
	if err != nil {
		return
	}
	defer in.Close()
	out, err := os.Create(dst)
	if err != nil {
		return
	}
	defer out.Close()
	io.Copy(out, in)
}
