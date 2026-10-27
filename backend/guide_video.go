package main

import (
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/gorilla/mux"
)

// Namuna (etalon) videolar — vazifa qanday bajarilishi kerakligini ko'rsatadi.
// Ishchi vazifa kartasidagi ⓘ ni bossa shu video ochiladi.
//
// Fayllar ./videos/guides ichida: ./videos docker volume'da saqlanadi,
// cleanupOldData esa faqat sana nomli papkalarni o'chiradi.
const guideVideoDir = "./videos/guides"

// sameTaskTemplateIDs - matni bir xil shablonlar (bitta vazifa har filial
// uchun alohida shablon bo'lib saqlanadi). Namuna hammasiga birdan qo'yiladi.
func sameTaskTemplateIDs(templateID int) ([]int, error) {
	mainDB, err := getMainDB()
	if err != nil {
		return nil, err
	}
	defer mainDB.Close()

	var task string
	if err := mainDB.QueryRow("SELECT task FROM task_templates WHERE id = ?", templateID).Scan(&task); err != nil {
		return nil, err
	}
	rows, err := mainDB.Query("SELECT id, task FROM task_templates")
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	key := normalizeTaskText(task)
	ids := []int{}
	for rows.Next() {
		var id int
		var t string
		if rows.Scan(&id, &t) == nil && normalizeTaskText(t) == key {
			ids = append(ids, id)
		}
	}
	return ids, nil
}

func normalizeTaskText(s string) string {
	return strings.ToLower(strings.Join(strings.Fields(s), " "))
}

// setGuideVideo - shablonlarga namuna video yozadi. Boshqa shablon
// ishlatmayotgan eski fayllar o'chiriladi.
func setGuideVideo(templateIDs []int, url string) error {
	mainDB, err := getMainDB()
	if err != nil {
		return err
	}
	defer mainDB.Close()

	old := map[string]bool{}
	for _, id := range templateIDs {
		var prev string
		mainDB.QueryRow("SELECT COALESCE(guide_video, '') FROM task_templates WHERE id = ?", id).Scan(&prev)
		if prev != "" && prev != url {
			old[prev] = true
		}
		if _, err := mainDB.Exec("UPDATE task_templates SET guide_video = ? WHERE id = ?", url, id); err != nil {
			return err
		}
	}
	for prev := range old {
		var used int
		mainDB.QueryRow("SELECT COUNT(*) FROM task_templates WHERE guide_video = ?", prev).Scan(&used)
		if used == 0 && strings.HasPrefix(prev, "/videos/guides/") {
			os.Remove(filepath.Join(guideVideoDir, filepath.Base(prev)))
		}
	}
	return nil
}

func guideTemplateID(w http.ResponseWriter, r *http.Request) (int, bool) {
	id, err := strconv.Atoi(mux.Vars(r)["id"])
	if err != nil || id <= 0 {
		respondJSON(w, http.StatusBadRequest, map[string]interface{}{"success": false, "error": "Noto'g'ri ID"})
		return 0, false
	}
	return id, true
}

func guideForbidden(w http.ResponseWriter, msg string) {
	respondJSON(w, http.StatusForbidden, map[string]interface{}{"success": false, "error": msg})
}

// canUploadGuide - super admin har doim; worker esa o'z filialidagi vazifaga,
// namuna hali yo'q bo'lsa (bir marta yuklanadi, keyin hammaga shu ko'rinadi).
func canUploadGuide(r *http.Request, templateID int) (bool, string) {
	role := r.Header.Get("Role")
	if role == RoleSuperAdmin {
		return true, ""
	}
	if role != RoleWorker {
		return false, "Ruxsat yo'q"
	}
	userID, _ := strconv.Atoi(r.Header.Get("UserID"))
	mainDB, err := getMainDB()
	if err != nil {
		return false, "Database xatosi"
	}
	defer mainDB.Close()

	var filialIDs, guide string
	if mainDB.QueryRow("SELECT filial_ids, COALESCE(guide_video, '') FROM task_templates WHERE id = ?", templateID).
		Scan(&filialIDs, &guide) != nil {
		return false, "Vazifa topilmadi"
	}
	own := userFilialIDs(mainDB, userID)
	allowed := false
	for _, fid := range parseFilialIDs(filialIDs) {
		if containsInt(own, fid) {
			allowed = true
		}
	}
	if !allowed {
		return false, "Ruxsat yo'q"
	}
	if guide != "" {
		return false, "Образец уже загружен"
	}
	return true, ""
}

// POST /api/templates/{id}/guide-video (multipart: video) — super_admin yoki
// o'z filialidagi vazifaga namuna hali yo'q bo'lsa worker.
func uploadGuideVideo(w http.ResponseWriter, r *http.Request) {
	templateID, ok := guideTemplateID(w, r)
	if !ok {
		return
	}
	if ok, msg := canUploadGuide(r, templateID); !ok {
		guideForbidden(w, msg)
		return
	}
	ids, err := sameTaskTemplateIDs(templateID)
	if err != nil {
		respondJSON(w, http.StatusNotFound, map[string]interface{}{"success": false, "error": "Vazifa topilmadi"})
		return
	}

	if err := r.ParseMultipartForm(200 << 20); err != nil {
		respondJSON(w, http.StatusBadRequest, map[string]interface{}{"success": false, "error": "Form parse xatosi: " + err.Error()})
		return
	}
	os.MkdirAll(guideVideoDir, 0755)
	name := fmt.Sprintf("guide%d_%d", templateID, time.Now().UnixMilli())

	// Oddiy vazifa videosi kabi: bitta fayl ("video") yoki pauza bilan
	// olingan bo'laklar ("segment_count" + "video_0".."video_N")
	fields := []string{"video"}
	if n, err := strconv.Atoi(r.FormValue("segment_count")); err == nil && n > 0 {
		fields = fields[:0]
		for i := 0; i < n; i++ {
			fields = append(fields, fmt.Sprintf("video_%d", i))
		}
	}
	parts := []string{}
	defer func() {
		for _, p := range parts {
			os.Remove(p)
		}
	}()
	for i, field := range fields {
		path, err := saveGuidePart(r, field, filepath.Join(guideVideoDir, fmt.Sprintf("%s_part%d", name, i)))
		if err != nil {
			respondJSON(w, http.StatusBadRequest, map[string]interface{}{"success": false, "error": "Video topilmadi"})
			return
		}
		parts = append(parts, path)
	}

	// Oddiy videolar kabi 500x500 kvadrat (ilovada aylana bo'lib ko'rinadi).
	// ffmpeg bo'lmasa yoki xato bersa - birinchi bo'lak o'zi qoladi.
	finalPath := filepath.Join(guideVideoDir, name+".mp4")
	if err := processGuideParts(parts, finalPath); err != nil {
		log.Printf("⚠️ Namuna video qayta ishlanmadi, asl fayl: %v", err)
		finalPath = filepath.Join(guideVideoDir, name+filepath.Ext(parts[0]))
		if err := os.Rename(parts[0], finalPath); err != nil {
			respondJSON(w, http.StatusInternalServerError, map[string]interface{}{"success": false, "error": "Fayl saqlash xatosi"})
			return
		}
	}

	url := "/videos/guides/" + filepath.Base(finalPath)
	if err := setGuideVideo(ids, url); err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]interface{}{"success": false, "error": "Database xatosi"})
		return
	}
	log.Printf("✅ Namuna video: %s (%d ta shablon)", url, len(ids))
	hub.broadcast("task_updated", map[string]interface{}{"action": "guide_video_changed"})
	respondJSON(w, http.StatusOK, map[string]interface{}{
		"success":       true,
		"guideVideoUrl": url,
		"templateIds":   ids,
	})
}

// DELETE /api/templates/{id}/guide-video — faqat super_admin.
func deleteGuideVideo(w http.ResponseWriter, r *http.Request) {
	if r.Header.Get("Role") != RoleSuperAdmin {
		guideForbidden(w, "Ruxsat yo'q")
		return
	}
	templateID, ok := guideTemplateID(w, r)
	if !ok {
		return
	}
	ids, err := sameTaskTemplateIDs(templateID)
	if err != nil {
		respondJSON(w, http.StatusNotFound, map[string]interface{}{"success": false, "error": "Vazifa topilmadi"})
		return
	}
	if err := setGuideVideo(ids, ""); err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]interface{}{"success": false, "error": "Database xatosi"})
		return
	}
	hub.broadcast("task_updated", map[string]interface{}{"action": "guide_video_changed"})
	respondJSON(w, http.StatusOK, map[string]interface{}{"success": true, "templateIds": ids})
}

// saveGuidePart - formadagi bitta faylni [base]+kengaytma nomi bilan saqlaydi.
func saveGuidePart(r *http.Request, field, base string) (string, error) {
	file, handler, err := r.FormFile(field)
	if err != nil {
		return "", err
	}
	defer file.Close()
	ext := strings.ToLower(filepath.Ext(handler.Filename))
	if ext == "" {
		ext = ".mp4"
	}
	path := base + ext
	out, err := os.Create(path)
	if err != nil {
		return "", err
	}
	_, err = io.Copy(out, file)
	out.Close()
	if err != nil {
		os.Remove(path)
		return "", err
	}
	return path, nil
}

// processGuideParts - bo'laklarni birlashtirib (bitta bo'lsa shuning o'zi)
// 500x500 kvadrat mp4 qiladi.
func processGuideParts(parts []string, outputPath string) error {
	if len(parts) == 1 {
		return cropVideoTo500(parts[0], outputPath)
	}
	listPath := strings.TrimSuffix(outputPath, ".mp4") + "_concat.txt"
	var list strings.Builder
	for _, p := range parts {
		list.WriteString(fmt.Sprintf("file '%s'\n", filepath.Base(p)))
	}
	if err := os.WriteFile(listPath, []byte(list.String()), 0644); err != nil {
		return err
	}
	defer os.Remove(listPath)
	return mergeVideos(listPath, outputPath)
}
