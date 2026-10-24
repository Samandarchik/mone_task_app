package main

import (
	"database/sql"
	"log"
)

// taskHasData - vazifaga biror narsa kiritilganmi (status, video, ovozli izoh,
// yuborilgan vaqt).
func taskHasData(t Task) bool {
	return t.Status != nil ||
		(t.VideoURL != nil && *t.VideoURL != "") ||
		len(t.VideoURLs) > 0 ||
		len(t.CheckerAudioURLs) > 0 ||
		(t.SubmittedAt != nil && *t.SubmittedAt != "")
}

// dedupeTasks - bir shablonning bitta filialda ikkita vazifasi bo'lsa
// (kategoriya o'zgarganda refresh yaratib qo'ygan dublikat) faqat bittasini
// qoldiradi: ma'lumoti borini, aks holda birinchisini. Ilova bitta shablon
// uchun bitta karta kutadi - ikkitasi ro'yxatni buzadi.
func dedupeTasks(tasks []Task) []Task {
	type key struct{ template, filial int }
	index := map[key]int{}
	result := make([]Task, 0, len(tasks))
	for _, t := range tasks {
		if t.TemplateID == 0 {
			result = append(result, t)
			continue
		}
		k := key{t.TemplateID, t.FilialID}
		if i, ok := index[k]; ok {
			if taskHasData(t) && !taskHasData(result[i]) {
				result[i] = t
			}
			continue
		}
		index[k] = len(result)
		result = append(result, t)
	}
	return result
}

// removeUntouchedDuplicates - kunlik bazadagi dublikatlardan hech narsa
// kiritilmaganlarini o'chiradi: har bir shablon+filial uchun bittasi qoladi
// (ma'lumotlisi bo'lsa - o'sha, aks holda eng birinchisi).
func removeUntouchedDuplicates(taskDB *sql.DB) {
	rows, err := taskDB.Query(`
		SELECT id, template_id, filial_id,
			(status IS NOT NULL
				OR COALESCE(video_url, '') != ''
				OR COALESCE(checker_audio_url, '') != ''
				OR COALESCE(submitted_at, '') != '') AS has_data
		FROM tasks
		WHERE template_id IS NOT NULL AND template_id != 0
		ORDER BY has_data DESC, id ASC`)
	if err != nil {
		return
	}
	type key struct{ template, filial int }
	seen := map[key]bool{}
	var remove []int
	for rows.Next() {
		var id, template, filial int
		var hasData bool
		if rows.Scan(&id, &template, &filial, &hasData) != nil {
			continue
		}
		k := key{template, filial}
		if !seen[k] {
			seen[k] = true // birinchisi (ma'lumotlisi) qoladi
			continue
		}
		if !hasData {
			remove = append(remove, id)
		}
	}
	rows.Close()
	for _, id := range remove {
		if _, err := taskDB.Exec("DELETE FROM tasks WHERE id = ?", id); err == nil {
			log.Printf("Bo'sh dublikat vazifa o'chirildi: id=%d", id)
		}
	}
}
