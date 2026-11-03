package main

// ═══════════════════════════════════════════════════════════════════
// Telefonga push (Firebase Cloud Messaging, HTTP v1)
//
// WS xabari faqat ilovasi ochiq odamga yetadi; ilova yopiq yoki telefon
// qulflangan bo'lsa ovozli bildirishnoma faqat FCM orqali boradi.
//
// Firebase service account JSON fayli bo'lmasa push jimgina o'chiq turadi —
// WS va Telegram avvalgidek ishlaydi. Fayl yo'li: FIREBASE_CREDENTIALS
// (standart: ./db/firebase-service-account.json).
// ═══════════════════════════════════════════════════════════════════

import (
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

const (
	fcmScope          = "https://www.googleapis.com/auth/firebase.messaging"
	demandPushChannel = "task_demands" // Android: MainActivity dagi kanal bilan bir xil
)

var (
	errPushDisabled = errors.New("push sozlanmagan")

	fcmBaseURL = "https://fcm.googleapis.com"
	fcmClient  = &http.Client{Timeout: 10 * time.Second}

	fcmMu          sync.Mutex
	fcmAccessToken string
	fcmTokenExpiry time.Time
)

type fcmCredentials struct {
	ProjectID   string `json:"project_id"`
	ClientEmail string `json:"client_email"`
	PrivateKey  string `json:"private_key"`
	TokenURI    string `json:"token_uri"`
}

func migrateDeviceTokens(db *sql.DB) {
	db.Exec(`CREATE TABLE IF NOT EXISTS device_tokens (
		token TEXT PRIMARY KEY,
		user_id INTEGER NOT NULL,
		platform TEXT NOT NULL DEFAULT '',
		updated_at TEXT NOT NULL
	)`)
	db.Exec("CREATE INDEX IF NOT EXISTS idx_device_tokens_user ON device_tokens(user_id)")
}

func fcmCredentialsPath() string {
	if p := strings.TrimSpace(os.Getenv("FIREBASE_CREDENTIALS")); p != "" {
		return p
	}
	return "./db/firebase-service-account.json"
}

func loadFCMCredentials() (*fcmCredentials, error) {
	raw, err := os.ReadFile(fcmCredentialsPath())
	if err != nil {
		if os.IsNotExist(err) {
			return nil, errPushDisabled
		}
		return nil, err
	}
	var creds fcmCredentials
	if err := json.Unmarshal(raw, &creds); err != nil {
		return nil, err
	}
	if creds.ProjectID == "" || creds.ClientEmail == "" || creds.PrivateKey == "" {
		return nil, errors.New("service account fayli to'liq emas")
	}
	if creds.TokenURI == "" {
		creds.TokenURI = "https://oauth2.googleapis.com/token"
	}
	return &creds, nil
}

// fcmAuthToken — service account bilan OAuth token (muddati tugaguncha keshda)
func fcmAuthToken(creds *fcmCredentials) (string, error) {
	fcmMu.Lock()
	defer fcmMu.Unlock()
	if fcmAccessToken != "" && time.Now().Before(fcmTokenExpiry) {
		return fcmAccessToken, nil
	}

	key, err := jwt.ParseRSAPrivateKeyFromPEM([]byte(creds.PrivateKey))
	if err != nil {
		return "", fmt.Errorf("private key: %w", err)
	}
	now := time.Now()
	assertion, err := jwt.NewWithClaims(jwt.SigningMethodRS256, jwt.MapClaims{
		"iss":   creds.ClientEmail,
		"scope": fcmScope,
		"aud":   creds.TokenURI,
		"iat":   now.Unix(),
		"exp":   now.Add(time.Hour).Unix(),
	}).SignedString(key)
	if err != nil {
		return "", err
	}

	resp, err := fcmClient.PostForm(creds.TokenURI, url.Values{
		"grant_type": {"urn:ietf:params:oauth:grant-type:jwt-bearer"},
		"assertion":  {assertion},
	})
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	var out struct {
		AccessToken string `json:"access_token"`
		ExpiresIn   int    `json:"expires_in"`
		Error       string `json:"error_description"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return "", err
	}
	if out.AccessToken == "" {
		return "", fmt.Errorf("OAuth rad etdi: %s", out.Error)
	}
	fcmAccessToken = out.AccessToken
	// Muddati tugashidan biroz oldin yangilanadi
	fcmTokenExpiry = now.Add(time.Duration(out.ExpiresIn-60) * time.Second)
	return fcmAccessToken, nil
}

// fcmMessage — ilova yopiq bo'lsa ham ovoz bilan ko'rinadigan bildirishnoma
func fcmMessage(token, title, body string, data map[string]string) map[string]interface{} {
	return map[string]interface{}{
		"message": map[string]interface{}{
			"token":        token,
			"notification": map[string]string{"title": title, "body": body},
			"data":         data,
			"android": map[string]interface{}{
				"priority": "HIGH",
				"notification": map[string]string{
					"channel_id": demandPushChannel,
					"sound":      "default",
				},
			},
			"apns": map[string]interface{}{
				"headers": map[string]string{"apns-priority": "10"},
				"payload": map[string]interface{}{
					"aps": map[string]interface{}{"sound": "default"},
				},
			},
		},
	}
}

// fcmSend — bitta qurilmaga yuboradi. stale=true: token endi yaroqsiz.
func fcmSend(projectID, accessToken string, message map[string]interface{}) (stale bool, err error) {
	payload, err := json.Marshal(message)
	if err != nil {
		return false, err
	}
	endpoint := fmt.Sprintf("%s/v1/projects/%s/messages:send", fcmBaseURL, projectID)
	req, err := http.NewRequest(http.MethodPost, endpoint, strings.NewReader(string(payload)))
	if err != nil {
		return false, err
	}
	req.Header.Set("Authorization", "Bearer "+accessToken)
	req.Header.Set("Content-Type", "application/json")

	resp, err := fcmClient.Do(req)
	if err != nil {
		return false, err
	}
	defer resp.Body.Close()
	if resp.StatusCode == http.StatusOK {
		return false, nil
	}
	body, _ := io.ReadAll(io.LimitReader(resp.Body, 1024))
	stale = resp.StatusCode == http.StatusNotFound || strings.Contains(string(body), "UNREGISTERED")
	return stale, fmt.Errorf("FCM %d: %s", resp.StatusCode, body)
}

// pushToUsers — foydalanuvchilarning barcha qurilmalariga yuboradi va kamida
// bitta qurilmasiga yetgan foydalanuvchilarni qaytaradi.
func pushToUsers(mainDB *sql.DB, userIDs []int, title, body string, data map[string]string) map[int]bool {
	reached := map[int]bool{}
	if len(userIDs) == 0 {
		return reached
	}
	creds, err := loadFCMCredentials()
	if err != nil {
		if !errors.Is(err, errPushDisabled) {
			log.Printf("push: %v", err)
		}
		return reached
	}

	args := make([]interface{}, len(userIDs))
	for i, id := range userIDs {
		args[i] = id
	}
	rows, err := mainDB.Query(
		fmt.Sprintf("SELECT token, user_id FROM device_tokens WHERE user_id IN (%s)", placeholders(len(args))),
		args...)
	if err != nil {
		log.Printf("push: tokenlar o'qilmadi: %v", err)
		return reached
	}
	type device struct {
		token  string
		userID int
	}
	var devices []device
	for rows.Next() {
		var d device
		if rows.Scan(&d.token, &d.userID) == nil {
			devices = append(devices, d)
		}
	}
	rows.Close()
	if len(devices) == 0 {
		return reached
	}

	accessToken, err := fcmAuthToken(creds)
	if err != nil {
		log.Printf("push: OAuth xatosi: %v", err)
		return reached
	}
	// Parallel: revizor «Потребовать» bosganda har qurilmani navbat kutmasin
	type outcome struct {
		d     device
		stale bool
		err   error
	}
	results := make(chan outcome, len(devices))
	for _, d := range devices {
		go func(d device) {
			stale, err := fcmSend(creds.ProjectID, accessToken, fcmMessage(d.token, title, body, data))
			results <- outcome{d, stale, err}
		}(d)
	}
	for range devices {
		r := <-results
		if r.stale {
			mainDB.Exec("DELETE FROM device_tokens WHERE token = ?", r.d.token)
		}
		if r.err != nil {
			log.Printf("push: user %d ga yuborilmadi: %v", r.d.userID, r.err)
			continue
		}
		reached[r.d.userID] = true
	}
	return reached
}

// POST /api/device-token — telefon push tokenini joriy foydalanuvchiga bog'laydi
func saveDeviceToken(w http.ResponseWriter, r *http.Request) {
	userID, _ := strconv.Atoi(r.Header.Get("UserID"))
	var req struct {
		Token    string `json:"token"`
		Platform string `json:"platform"`
	}
	json.NewDecoder(r.Body).Decode(&req)
	req.Token = strings.TrimSpace(req.Token)
	if req.Token == "" || userID == 0 {
		respondJSON(w, http.StatusBadRequest, map[string]interface{}{"success": false, "error": "Token yo'q"})
		return
	}
	mainDB, err := getMainDB()
	if err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]interface{}{"success": false, "error": "Server xatosi"})
		return
	}
	defer mainDB.Close()
	// Telefon boshqa hisobga o'tgan bo'lsa token yangi egasiga ko'chadi
	_, err = mainDB.Exec(`INSERT INTO device_tokens (token, user_id, platform, updated_at) VALUES (?, ?, ?, ?)
		ON CONFLICT(token) DO UPDATE SET user_id = excluded.user_id, platform = excluded.platform, updated_at = excluded.updated_at`,
		req.Token, userID, req.Platform, time.Now().Format(time.RFC3339))
	if err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]interface{}{"success": false, "error": "Server xatosi"})
		return
	}
	respondJSON(w, http.StatusOK, map[string]interface{}{"success": true})
}

// DELETE /api/device-token — hisobdan chiqilganda telefonga push bormasin
func deleteDeviceToken(w http.ResponseWriter, r *http.Request) {
	userID, _ := strconv.Atoi(r.Header.Get("UserID"))
	var req struct {
		Token string `json:"token"`
	}
	json.NewDecoder(r.Body).Decode(&req)
	mainDB, err := getMainDB()
	if err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]interface{}{"success": false, "error": "Server xatosi"})
		return
	}
	defer mainDB.Close()
	mainDB.Exec("DELETE FROM device_tokens WHERE token = ? AND user_id = ?", req.Token, userID)
	respondJSON(w, http.StatusOK, map[string]interface{}{"success": true})
}
