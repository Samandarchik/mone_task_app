package main

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gorilla/mux"
)

// credBotToken — login ma'lumotlarini (login + parol + ilova linklari) Telegram
// orqali yuborish uchun ishlatiladigan bot tokeni (boshqa mone loyihalari bilan
// bir xil bot).
const credBotToken = "8550220546:AAFEII8AzNdMapEqT_VFtqiqv6h0obbLgzQ"

// telegramIDFromProfileJSON — rezume `profile_json` satridan `tg_user_id`
// raqamli qiymatini ajratib oladi. JSON bo'sh/buzuq yoki maydon yo'q bo'lsa 0.
func telegramIDFromProfileJSON(profileJSON string) int64 {
	if strings.TrimSpace(profileJSON) == "" {
		return 0
	}
	var m map[string]interface{}
	if err := json.Unmarshal([]byte(profileJSON), &m); err != nil {
		return 0
	}
	switch v := m["tg_user_id"].(type) {
	case float64:
		return int64(v)
	case json.Number:
		n, _ := v.Int64()
		return n
	case string:
		n, _ := strconv.ParseInt(strings.TrimSpace(v), 10, 64)
		return n
	}
	return 0
}

// buildCredentialsMessage — bitta foydalanuvchi uchun login xabari matnini
// quradi: ism (salomlashish), login, parol va ilova (iOS/Android) yuklab olish
// havolalari (AppStoreURL / PlayStoreURL konstantalaridan).
func buildCredentialsMessage(username, login, password string) string {
	name := strings.TrimSpace(username)
	if name == "" {
		name = strings.TrimSpace(login)
	}
	iosLink := AppStoreURL
	if strings.TrimSpace(iosLink) == "" {
		iosLink = "—"
	}
	androidLink := PlayStoreURL
	if strings.TrimSpace(androidLink) == "" {
		androidLink = "—"
	}
	return fmt.Sprintf(
		"Assalomu alaykum, %s!\n\nTizimga kirish ma'lumotlaringiz:\nLogin: %s\nParol: %s\n\niOS linki: %s\nAndroid linki: %s",
		name, strings.TrimSpace(login), password, iosLink, androidLink,
	)
}

// sendCredsTgMessage — credentials xabarini berilgan chat ID'ga yuboradi va
// Telegram rad etsa xato qaytaradi (yuborildi/xato hisobi aniq bo'lishi uchun).
func sendCredsTgMessage(chatID int64, text string) error {
	url := fmt.Sprintf("https://api.telegram.org/bot%s/sendMessage", credBotToken)
	payload, _ := json.Marshal(map[string]interface{}{
		"chat_id":                  chatID,
		"text":                     text,
		"disable_web_page_preview": true,
	})
	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Post(url, "application/json", strings.NewReader(string(payload)))
	if err != nil {
		return fmt.Errorf("Telegram'ga ulanib bo'lmadi: %w", err)
	}
	defer resp.Body.Close()
	var tgResp struct {
		OK          bool   `json:"ok"`
		Description string `json:"description"`
	}
	_ = json.NewDecoder(resp.Body).Decode(&tgResp)
	if !tgResp.OK {
		desc := tgResp.Description
		if desc == "" {
			desc = "noma'lum xato"
		}
		return fmt.Errorf("Telegram rad etdi: %s", desc)
	}
	return nil
}

// sendCredentials — POST /api/users/{id}/send-credentials (faqat super_admin).
// Bitta foydalanuvchiga login ma'lumotlarini (ism + login + parol + ilova
// iOS/Android linklari) Telegram orqali yuboradi. Chat ID rezume `profile_json`
// ichidagi `tg_user_id` orqali olinadi; profil bo'sh bo'lsa HR API'dan
// to'ldirishga urinadi (fillMissingProfiles).
func sendCredentials(w http.ResponseWriter, r *http.Request) {
	if r.Header.Get("Role") != RoleSuperAdmin {
		respondJSON(w, http.StatusForbidden, map[string]interface{}{
			"success": false,
			"error":   "Faqat super admin uchun",
		})
		return
	}

	idStr := mux.Vars(r)["id"]

	db, err := getMainDB()
	if err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]interface{}{
			"success": false,
			"error":   "Database xatosi",
		})
		return
	}

	var u User
	var profileJSON, phone sql.NullString
	err = db.QueryRow(
		"SELECT id, username, COALESCE(login,''), COALESCE(password,''), profile_json, phone_number FROM users WHERE id = ?",
		idStr,
	).Scan(&u.ID, &u.Username, &u.Login, &u.Password, &profileJSON, &phone)
	if err != nil {
		db.Close()
		respondJSON(w, http.StatusNotFound, map[string]interface{}{
			"success": false,
			"error":   "Foydalanuvchi topilmadi",
		})
		return
	}
	if profileJSON.Valid && profileJSON.String != "" {
		s := profileJSON.String
		u.ProfileJSON = &s
	}
	if phone.Valid && phone.String != "" {
		p := phone.String
		u.PhoneNumber = &p
	}
	db.Close()

	// profile_json bo'sh bo'lsa HR API'dan to'ldirishga urinamiz.
	users := []User{u}
	fillMissingProfiles(users)
	u = users[0]

	var profileStr string
	if u.ProfileJSON != nil {
		profileStr = *u.ProfileJSON
	}
	chatID := telegramIDFromProfileJSON(profileStr)
	if chatID == 0 {
		respondJSON(w, http.StatusBadRequest, map[string]interface{}{
			"success": false,
			"error":   "Bu foydalanuvchining Telegram'i bog'lanmagan",
		})
		return
	}

	msg := buildCredentialsMessage(u.Username, u.Login, u.Password)
	if err := sendCredsTgMessage(chatID, msg); err != nil {
		respondJSON(w, http.StatusBadGateway, map[string]interface{}{
			"success": false,
			"error":   err.Error(),
		})
		return
	}

	respondJSON(w, http.StatusOK, map[string]interface{}{
		"success": true,
		"message": "Telegram orqali yuborildi",
	})
}

// sendAllCredentials — POST /api/users/send-all-credentials (faqat super_admin).
// super_admin'dan boshqa har bir foydalanuvchiga login ma'lumotlarini (ism +
// login + parol + ilova iOS/Android linklari) Telegram orqali yuboradi.
// Foydalanuvchining Telegram chat ID'si rezume `profile_json` ichidagi
// `tg_user_id` orqali olinadi; profil bo'sh bo'lsa, HR API'dan to'ldirishga
// urinadi (fillMissingProfiles). Javob: yuborilganlar soni, Telegram'i yo'q
// (skipped) va xatolik bo'lganlar (failed) ro'yxati.
func sendAllCredentials(w http.ResponseWriter, r *http.Request) {
	if r.Header.Get("Role") != RoleSuperAdmin {
		respondJSON(w, http.StatusForbidden, map[string]interface{}{
			"success": false,
			"error":   "Faqat super admin uchun",
		})
		return
	}

	db, err := getMainDB()
	if err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]interface{}{
			"success": false,
			"error":   "Database xatosi",
		})
		return
	}

	rows, err := db.Query(
		"SELECT id, username, COALESCE(login,''), COALESCE(password,''), profile_json, phone_number FROM users WHERE role != ?",
		RoleSuperAdmin,
	)
	if err != nil {
		db.Close()
		respondJSON(w, http.StatusInternalServerError, map[string]interface{}{
			"success": false,
			"error":   "Foydalanuvchilarni o'qib bo'lmadi",
		})
		return
	}

	var users []User
	for rows.Next() {
		var u User
		var profileJSON, phone sql.NullString
		if err := rows.Scan(&u.ID, &u.Username, &u.Login, &u.Password, &profileJSON, &phone); err != nil {
			continue
		}
		if profileJSON.Valid && profileJSON.String != "" {
			s := profileJSON.String
			u.ProfileJSON = &s
		}
		if phone.Valid && phone.String != "" {
			p := phone.String
			u.PhoneNumber = &p
		}
		users = append(users, u)
	}
	rows.Close()
	db.Close()

	// profile_json bo'sh userlar uchun HR API'dan rezume olib, tg_user_id'ni
	// to'ldirishga urinamiz (qo'shimcha qamrov uchun).
	fillMissingProfiles(users)

	sent := 0
	failed := []map[string]string{}
	skipped := []string{}
	for _, u := range users {
		label := strings.TrimSpace(u.Username)
		if label == "" {
			label = strings.TrimSpace(u.Login)
		}
		var profileStr string
		if u.ProfileJSON != nil {
			profileStr = *u.ProfileJSON
		}
		chatID := telegramIDFromProfileJSON(profileStr)
		if chatID == 0 {
			skipped = append(skipped, label)
			continue
		}
		msg := buildCredentialsMessage(u.Username, u.Login, u.Password)
		if err := sendCredsTgMessage(chatID, msg); err != nil {
			failed = append(failed, map[string]string{"name": label, "error": err.Error()})
			continue
		}
		sent++
	}

	log.Printf("send-all-credentials: %d yuborildi, %d skipped, %d xato", sent, len(skipped), len(failed))
	respondJSON(w, http.StatusOK, map[string]interface{}{
		"success": true,
		"message": fmt.Sprintf("%d ta foydalanuvchiga yuborildi", sent),
		"sent":    sent,
		"skipped": skipped,
		"failed":  failed,
	})
}
