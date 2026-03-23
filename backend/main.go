package main

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"mime/multipart"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/gorilla/mux"
	"github.com/gorilla/websocket"
	_ "github.com/mattn/go-sqlite3"
	"github.com/xuri/excelize/v2"
	"golang.org/x/crypto/bcrypt"
)

// ═══════════════════════════════════════════════════════════════════
// WebSocket Hub - real-time task updates
// ═══════════════════════════════════════════════════════════════════

var wsUpgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool { return true },
}

type WSClient struct {
	conn   *websocket.Conn
	userID int
	role   string
	send   chan []byte
}

type WSHub struct {
	mu      sync.RWMutex
	clients map[*WSClient]bool
}

var hub = &WSHub{
	clients: make(map[*WSClient]bool),
}

func (h *WSHub) register(c *WSClient) {
	h.mu.Lock()
	h.clients[c] = true
	h.mu.Unlock()
	log.Printf("🔌 WS client connected: userID=%d role=%s (total: %d)", c.userID, c.role, len(h.clients))
}

func (h *WSHub) unregister(c *WSClient) {
	h.mu.Lock()
	if _, ok := h.clients[c]; ok {
		delete(h.clients, c)
		close(c.send)
	}
	h.mu.Unlock()
	log.Printf("🔌 WS client disconnected: userID=%d role=%s (total: %d)", c.userID, c.role, len(h.clients))
}

// broadcast sends a JSON message to all connected clients
func (h *WSHub) broadcast(event string, data map[string]interface{}) {
	msg := map[string]interface{}{
		"event": event,
		"data":  data,
	}
	msgBytes, err := json.Marshal(msg)
	if err != nil {
		log.Printf("❌ WS broadcast marshal error: %v", err)
		return
	}

	h.mu.RLock()
	defer h.mu.RUnlock()

	for client := range h.clients {
		select {
		case client.send <- msgBytes:
		default:
			// client buffer full, skip
		}
	}
	log.Printf("📡 WS broadcast: event=%s to %d clients", event, len(h.clients))
}

func wsHandler(w http.ResponseWriter, r *http.Request) {
	// JWT auth via query parameter
	tokenStr := r.URL.Query().Get("token")
	if tokenStr == "" {
		http.Error(w, "token required", http.StatusUnauthorized)
		return
	}

	token, err := jwt.ParseWithClaims(tokenStr, &Claims{}, func(t *jwt.Token) (interface{}, error) {
		return jwtSecret, nil
	})
	if err != nil || !token.Valid {
		http.Error(w, "invalid token", http.StatusUnauthorized)
		return
	}

	claims := token.Claims.(*Claims)

	conn, err := wsUpgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("❌ WS upgrade error: %v", err)
		return
	}

	client := &WSClient{
		conn:   conn,
		userID: claims.UserID,
		role:   claims.Role,
		send:   make(chan []byte, 64),
	}

	hub.register(client)

	// Writer goroutine
	go func() {
		defer conn.Close()
		for msg := range client.send {
			if err := conn.WriteMessage(websocket.TextMessage, msg); err != nil {
				break
			}
		}
	}()

	// Reader goroutine (keeps connection alive with ping/pong)
	go func() {
		defer hub.unregister(client)
		defer conn.Close()
		conn.SetReadDeadline(time.Now().Add(60 * time.Second))
		conn.SetPongHandler(func(string) error {
			conn.SetReadDeadline(time.Now().Add(60 * time.Second))
			return nil
		})
		for {
			_, _, err := conn.ReadMessage()
			if err != nil {
				break
			}
		}
	}()

	// Ping ticker to keep connection alive
	go func() {
		ticker := time.NewTicker(30 * time.Second)
		defer ticker.Stop()
		for range ticker.C {
			if err := conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}()
}

var jwtSecret = []byte("your-secret-key-change-this")

// Server base URL - env dan oladi
var baseURL = func() string {
	if u := os.Getenv("BASE_URL"); u != "" {
		return strings.TrimRight(u, "/")
	}
	return ""
}()

func fullURL(path *string) *string {
	if path == nil || *path == "" {
		return nil
	}
	if baseURL == "" {
		return path
	}
	full := baseURL + *path
	return &full
}

// parseCheckerAudioURLs - DB dan checker_audio_url ni o'qib []string qaytaradi
// Eski format: "/audios/..." (bitta string)
// Yangi format: '["/audios/...", "/audios/..."]' (JSON array)
func parseCheckerAudioURLs(raw *string) []string {
	if raw == nil || *raw == "" {
		return nil
	}
	s := *raw
	if strings.HasPrefix(s, "[") {
		var urls []string
		if err := json.Unmarshal([]byte(s), &urls); err == nil {
			return urls
		}
	}
	// eski format - bitta URL
	return []string{s}
}

// fullAudioURLs - har bir URL ga baseURL qo'shadi
func fullAudioURLs(urls []string) []string {
	if len(urls) == 0 {
		return nil
	}
	result := make([]string, len(urls))
	for i, u := range urls {
		if baseURL != "" && !strings.HasPrefix(u, "http") {
			result[i] = baseURL + u
		} else {
			result[i] = u
		}
	}
	return result
}

// UTC+5 - Toshkent vaqt zonasi
var tashkentZone = time.FixedZone("UTC+5", 5*60*60)

func nowTashkent() time.Time {
	return time.Now().In(tashkentZone)
}

const (
	StatusNotDone  = 1
	StatusPending  = 2
	StatusApproved = 3
	StatusRejected = 4

	TypeDaily   = 1
	TypeWeekly  = 2
	TypeMonthly = 3

	RoleSuperAdmin = "super_admin"
	RoleChecker    = "checker"
	RoleWorker     = "worker"
)

type User struct {
	ID             int      `json:"userId"`
	Username       string   `json:"username"`
	Login          string   `json:"login"`
	Password       string   `json:"-"`
	Role           string   `json:"role"`
	FilialIDs      []int    `json:"filialIds,omitempty"`
	Categories     []string `json:"categories,omitempty"`
	NotificationID *string  `json:"notificationId,omitempty"`
	IsLogin        bool     `json:"isLogin"`
}

type Filial struct {
	ID   int    `json:"filialId"`
	Name string `json:"name"`
}

type Category struct {
	ID   int    `json:"categoryId"`
	Name string `json:"name"`
}

// Task - status nullable: null = hali worker ko'rmagan/bajarmagan
// admin/checker o'zgartirsa yangilanadi
type Task struct {
	ID               int      `json:"taskId"`
	FilialID         int      `json:"filialId"`
	WorkerIDs        []int    `json:"workerIds,omitempty"`
	Task             string   `json:"task"`
	Type             int      `json:"type"`
	Status           *int     `json:"status"` // null yoki 1,2,3,4
	VideoURL         *string  `json:"videoUrl"`
	CheckerAudioURLs []string `json:"checkerAudioUrls"`
	SubmittedAt      *string  `json:"submittedAt,omitempty"`
	SubmittedBy      *string  `json:"submittedBy,omitempty"`
	Date             string   `json:"date"`
	Days             []int    `json:"days,omitempty"`
	Category         string   `json:"category"`
	NotificationTime string   `json:"notificationTime,omitempty"`
	OrderIndex       int      `json:"orderIndex"`
}

type TaskTemplate struct {
	ID               int    `json:"templateId"`
	Task             string `json:"task"`
	Type             int    `json:"type"`
	FilialIDs        []int  `json:"filialIds"`
	Days             []int  `json:"days,omitempty"`
	Category         string `json:"category"`
	NotificationTime string `json:"notificationTime,omitempty"`
	OrderIndex       int    `json:"orderIndex"`
	CreatedAt        string `json:"createdAt"`
}

type Claims struct {
	UserID    int    `json:"userId"`
	Username  string `json:"username"`
	Role      string `json:"role"`
	FilialIDs []int  `json:"filialIds,omitempty"`
	jwt.RegisteredClaims
}

func main() {
	initDB()

	go startScheduler()
	go startCleanup()
	go startNotificationScheduler()

	r := mux.NewRouter()

	// Auth
	r.HandleFunc("/api/auth/register", register).Methods("POST")
	r.HandleFunc("/api/auth/login", login).Methods("POST")
	r.HandleFunc("/api/auth/logout", authMiddleware(logout)).Methods("POST")
	r.HandleFunc("/api/auth/force-logout/{userId}", authMiddleware(forceLogout)).Methods("POST")

	// Tasks
	r.HandleFunc("/api/tasks", authMiddleware(getTasks)).Methods("GET")
	r.HandleFunc("/api/tasks/all", authMiddleware(getAllTasks)).Methods("GET")
	r.HandleFunc("/api/tasks", authMiddleware(createTask)).Methods("POST")
	r.HandleFunc("/api/tasks/{id}", authMiddleware(getTask)).Methods("GET")
	r.HandleFunc("/api/tasks/{id}", authMiddleware(updateTask)).Methods("PUT")
	r.HandleFunc("/api/tasks/{id}", authMiddleware(deleteTask)).Methods("DELETE")
	r.HandleFunc("/api/tasks/{id}/submit", authMiddleware(submitTask)).Methods("POST")
	r.HandleFunc("/api/tasks/{id}/check", authMiddleware(checkTask)).Methods("POST")
	r.HandleFunc("/api/tasks/{id}/check/{date}", authMiddleware(checkTask)).Methods("POST")
	r.HandleFunc("/api/tasks/{id}/voice-comment/{date}", authMiddleware(submitCheckerAudio)).Methods("POST")
	r.HandleFunc("/api/tasks/{id}/voice-comment/{date}/{audioIndex}", authMiddleware(deleteCheckerAudio)).Methods("DELETE")
	r.HandleFunc("/api/tasks/reorder/{taskId}/{newPosition}", authMiddleware(reorderTask)).Methods("PUT")
	r.HandleFunc("/api/tasks/reorder", authMiddleware(reorderAllTasks)).Methods("PUT")

	// Templates
	r.HandleFunc("/api/templates/{id}", authMiddleware(getTemplate)).Methods("GET")

	// Filials
	r.HandleFunc("/api/filials", authMiddleware(getFilials)).Methods("GET")
	r.HandleFunc("/api/filials", authMiddleware(createFilial)).Methods("POST")
	r.HandleFunc("/api/filials/{id}", authMiddleware(updateFilial)).Methods("PUT")
	r.HandleFunc("/api/filials/{id}", authMiddleware(deleteFilial)).Methods("DELETE")

	// Categories
	r.HandleFunc("/api/categories", authMiddleware(getCategories)).Methods("GET")
	r.HandleFunc("/api/categories", authMiddleware(createCategory)).Methods("POST")
	r.HandleFunc("/api/categories/{id}", authMiddleware(updateCategory)).Methods("PUT")
	r.HandleFunc("/api/categories/{id}", authMiddleware(deleteCategory)).Methods("DELETE")

	// Reports
	r.HandleFunc("/api/reports/excel", (generateExcelReport)).Methods("GET")
	r.HandleFunc("/api/reports/json", authMiddleware(generateJSONReport)).Methods("GET")

	// Notifications
	r.HandleFunc("/api/notifications", authMiddleware(getNotifications)).Methods("GET")

	// Users
	r.HandleFunc("/api/users", authMiddleware(getUsers)).Methods("GET")
	r.HandleFunc("/api/users/{id}", authMiddleware(updateUser)).Methods("PUT")
	r.HandleFunc("/api/users/{id}", authMiddleware(deleteUser)).Methods("DELETE")

	// Debug
	r.HandleFunc("/api/debug/info", authMiddleware(getDebugInfo)).Methods("GET")

	// WebSocket
	r.HandleFunc("/ws/tasks", wsHandler)

	// Deep link: Apple Universal Links
	r.HandleFunc("/.well-known/apple-app-site-association", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`{
  "applinks": {
    "apps": [],
    "details": [{
      "appID": "KC2VPYBYF5.uz.uzaidev.taskapp",
      "paths": ["/task/*"]
    }]
  }
}`))
	}).Methods("GET")

	// Deep link: Android App Links
	r.HandleFunc("/.well-known/assetlinks.json", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`[{
  "relation": ["delegate_permission/common.handle_all_urls"],
  "target": {
    "namespace": "android_app",
    "package_name": "com.uzaidev.mone_task_app",
    "sha256_cert_fingerprints": ["SHA256_FINGERPRINT_HERE"]
  }
}]`))
	}).Methods("GET")

	// Deep link: /task/{date}/{taskId} — app o'rnatilmagan bo'lsa download sahifaga yo'naltiradi
	r.HandleFunc("/task/{date}/{taskId}", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		w.Write([]byte(`<!DOCTYPE html>
<html><head>
<meta charset="utf-8">
<title>Mone Task App</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>
body{font-family:-apple-system,sans-serif;display:flex;align-items:center;justify-content:center;min-height:100vh;margin:0;background:#f5f5f5}
.card{background:#fff;border-radius:16px;padding:40px;text-align:center;box-shadow:0 4px 12px rgba(0,0,0,.1);max-width:360px}
h1{font-size:24px;margin:0 0 8px}
p{color:#666;margin:0 0 24px}
.btn{display:inline-block;padding:14px 32px;border-radius:12px;text-decoration:none;font-weight:600;font-size:16px;margin:6px}
.ios{background:#007AFF;color:#fff}
.android{background:#34A853;color:#fff}
</style>
</head><body>
<div class="card">
<h1>Mone Task App</h1>
<p>Ilovani yuklab oling</p>
<a class="btn ios" href="/downloads/task.ipa">iOS yuklash</a><br>
<a class="btn android" href="/downloads/task.apk">Android yuklash</a>
</div>
</body></html>`))
	}).Methods("GET")

	// App downloads
	r.PathPrefix("/downloads/").Handler(http.StripPrefix("/downloads/", http.FileServer(http.Dir("./downloads"))))

	// Health
	r.HandleFunc("/health", healthCheck).Methods("GET")

	// Static files - video va audio
	r.PathPrefix("/videos/").Handler(http.StripPrefix("/videos/", http.FileServer(http.Dir("./videos"))))
	r.PathPrefix("/audios/").Handler(http.StripPrefix("/audios/", http.FileServer(http.Dir("./audios"))))

	log.Println("Server started on :8000")
	log.Fatal(http.ListenAndServe(":8000", r))
}

func initDB() {
	os.MkdirAll("./db", 0755)
	os.MkdirAll("./videos", 0755)
	os.MkdirAll("./audios", 0755)
	os.MkdirAll("./downloads", 0755)

	createMainDB()
	ensureTodayDB()
	migrateExistingDBs()

	log.Println("Database initialized successfully")
}

func createMainDB() {
	db, err := sql.Open("sqlite3", "./db/main.db")
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()

	createTables := `
	CREATE TABLE IF NOT EXISTS users (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		username TEXT NOT NULL,
		login TEXT UNIQUE NOT NULL,
		password_hash TEXT NOT NULL,
		role TEXT NOT NULL,
		filial_ids TEXT,
		categories TEXT,
		notification_id TEXT,
		is_login INTEGER DEFAULT 0,
		created_at DATETIME DEFAULT CURRENT_TIMESTAMP
	);

	CREATE TABLE IF NOT EXISTS filials (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		name TEXT NOT NULL
	);

	CREATE TABLE IF NOT EXISTS categories (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		name TEXT NOT NULL UNIQUE
	);

	CREATE TABLE IF NOT EXISTS task_templates (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		task TEXT NOT NULL,
		type INTEGER NOT NULL,
		filial_ids TEXT NOT NULL,
		days TEXT,
		category TEXT NOT NULL,
		notification_time TEXT,
		order_index INTEGER DEFAULT 0,
		created_at DATETIME DEFAULT CURRENT_TIMESTAMP
	);

	`

	_, err = db.Exec(createTables)
	if err != nil {
		log.Fatal(err)
	}

	db.Exec("ALTER TABLE task_templates ADD COLUMN order_index INTEGER DEFAULT 0")

	var needsUpdate int
	db.QueryRow("SELECT COUNT(*) FROM task_templates WHERE order_index = 0").Scan(&needsUpdate)

	if needsUpdate > 0 {
		log.Println("Fixing order_index for existing templates...")
		rows, _ := db.Query("SELECT id FROM task_templates ORDER BY created_at DESC")
		var ids []int
		for rows.Next() {
			var id int
			rows.Scan(&id)
			ids = append(ids, id)
		}
		rows.Close()

		for i, id := range ids {
			db.Exec("UPDATE task_templates SET order_index = ? WHERE id = ?", i+1, id)
		}
		log.Printf("Fixed order_index for %d templates\n", len(ids))
	}

	// Create super admin
	var count int
	db.QueryRow("SELECT COUNT(*) FROM users WHERE role = ?", RoleSuperAdmin).Scan(&count)
	if count == 0 {
		hash, _ := bcrypt.GenerateFromPassword([]byte("admin123"), bcrypt.DefaultCost)
		db.Exec("INSERT INTO users (username, login, password_hash, role) VALUES (?, ?, ?, ?)",
			"Super Admin", "admin", string(hash), RoleSuperAdmin)
		log.Println("Super admin created: login=admin, password=admin123")
	}

	// Create filials
	db.QueryRow("SELECT COUNT(*) FROM filials").Scan(&count)
	if count == 0 {
		filials := []string{
			"Toshkent markaz",
			"Samarqand",
			"Buxoro",
			"Farg'ona",
		}
		for _, name := range filials {
			db.Exec("INSERT INTO filials (name) VALUES (?)", name)
		}
	}

	// Create categories
	db.QueryRow("SELECT COUNT(*) FROM categories").Scan(&count)
	if count == 0 {
		categories := []string{
			"Shef Povar",
			"Admin",
			"Ofitsiant",
		}
		for _, name := range categories {
			db.Exec("INSERT INTO categories (name) VALUES (?)", name)
		}
	}
}

func getDBPath(date time.Time) string {
	return fmt.Sprintf("./db/tasks_%s.db", date.Format("2006-01-02"))
}

func ensureTodayDB() {
	ensureDBForDate(time.Now())
}

func ensureDBForDate(date time.Time) {
	dbPath := getDBPath(date)

	if _, err := os.Stat(dbPath); err == nil {
		return
	}

	db, err := sql.Open("sqlite3", dbPath)
	if err != nil {
		log.Printf("Error creating DB for %s: %v\n", date.Format("2006-01-02"), err)
		return
	}
	defer db.Close()

	// MUHIM: status DEFAULT NULL - task yaratilganda null bo'ladi
	// Faqat admin/checker o'zgartirsa yangilanadi
	createTable := `
	CREATE TABLE IF NOT EXISTS tasks (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		template_id INTEGER,
		filial_id INTEGER NOT NULL,
		worker_ids TEXT,
		task TEXT NOT NULL,
		type INTEGER NOT NULL,
		status INTEGER DEFAULT NULL,
		video_url TEXT,
		checker_audio_url TEXT,
		submitted_at DATETIME,
		submitted_by TEXT,
		days TEXT,
		category TEXT NOT NULL,
		notification_time TEXT,
		order_index INTEGER DEFAULT 0,
		created_at DATETIME DEFAULT CURRENT_TIMESTAMP
	);
	`

	_, err = db.Exec(createTable)
	if err != nil {
		log.Printf("Error creating tasks table: %v\n", err)
		return
	}

	db.Exec("ALTER TABLE tasks ADD COLUMN checker_audio_url TEXT")
}

// migrateExistingDBs - barcha mavjud task DB larni yangilash
func migrateExistingDBs() {
	dbDir := "./db"
	files, err := os.ReadDir(dbDir)
	if err != nil {
		return
	}
	for _, f := range files {
		if f.IsDir() || !strings.HasSuffix(f.Name(), ".db") || f.Name() == "main.db" {
			continue
		}
		dbPath := filepath.Join(dbDir, f.Name())
		db, err := sql.Open("sqlite3", dbPath)
		if err != nil {
			continue
		}
		db.Exec("ALTER TABLE tasks ADD COLUMN checker_audio_url TEXT")
		db.Exec(`CREATE TABLE IF NOT EXISTS voice_tasks (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			template_id INTEGER,
			filial_id INTEGER NOT NULL,
			worker_ids TEXT,
			task TEXT NOT NULL,
			status INTEGER DEFAULT NULL,
			audio_url TEXT,
			submitted_at DATETIME,
			submitted_by TEXT,
			category TEXT NOT NULL,
			notification_time TEXT,
			order_index INTEGER DEFAULT 0,
			created_at DATETIME DEFAULT CURRENT_TIMESTAMP
		)`)
		db.Close()
	}
	log.Println("Existing DBs migrated")
}

func getMainDB() (*sql.DB, error) {
	return sql.Open("sqlite3", "./db/main.db")
}

func getTaskDB(date time.Time) (*sql.DB, error) {
	ensureDBForDate(date)
	return sql.Open("sqlite3", getDBPath(date))
}

func authMiddleware(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		authHeader := r.Header.Get("Authorization")
		if authHeader == "" {
			respondJSON(w, http.StatusUnauthorized, map[string]interface{}{
				"success": false,
				"error":   "Token yo'q",
			})
			return
		}

		tokenString := strings.Replace(authHeader, "Bearer ", "", 1)
		claims := &Claims{}

		token, err := jwt.ParseWithClaims(tokenString, claims, func(token *jwt.Token) (interface{}, error) {
			return jwtSecret, nil
		})

		if err != nil || !token.Valid {
			respondJSON(w, http.StatusUnauthorized, map[string]interface{}{
				"success": false,
				"error":   "Noto'g'ri token",
			})
			return
		}

		r.Header.Set("UserID", strconv.Itoa(claims.UserID))
		r.Header.Set("Username", claims.Username)
		r.Header.Set("Role", claims.Role)
		if len(claims.FilialIDs) > 0 {
			filialIDsStr := strings.Trim(strings.Join(strings.Fields(fmt.Sprint(claims.FilialIDs)), ","), "[]")
			r.Header.Set("FilialIDs", filialIDsStr)
		}

		next(w, r)
	}
}

func register(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Username       string   `json:"username"`
		Login          string   `json:"login"`
		Password       string   `json:"password"`
		Role           string   `json:"role"`
		FilialIDs      []int    `json:"filialIds"`
		Categories     []string `json:"categories"`
		NotificationID *string  `json:"notificationId"`
	}

	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		respondJSON(w, http.StatusBadRequest, map[string]interface{}{
			"success": false,
			"error":   "Noto'g'ri ma'lumot",
		})
		return
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]interface{}{
			"success": false,
			"error":   "Server xatosi",
		})
		return
	}

	db, _ := getMainDB()
	defer db.Close()

	categoriesJSON, _ := json.Marshal(req.Categories)
	filialIDsStr := ""
	if len(req.FilialIDs) > 0 {
		filialIDsStr = strings.Trim(strings.Join(strings.Fields(fmt.Sprint(req.FilialIDs)), ","), "[]")
	}

	result, err := db.Exec("INSERT INTO users (username, login, password_hash, role, filial_ids, categories, notification_id) VALUES (?, ?, ?, ?, ?, ?, ?)",
		req.Username, req.Login, string(hash), req.Role, filialIDsStr, string(categoriesJSON), req.NotificationID)
	if err != nil {
		respondJSON(w, http.StatusBadRequest, map[string]interface{}{
			"success": false,
			"error":   "Login band",
		})
		return
	}

	id, _ := result.LastInsertId()
	respondJSON(w, http.StatusCreated, map[string]interface{}{
		"success": true,
		"userId":  id,
	})
}

func login(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Login          string  `json:"login"`
		Password       string  `json:"password"`
		NotificationID *string `json:"notificationId"`
	}

	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		respondJSON(w, http.StatusBadRequest, map[string]interface{}{
			"success": false,
			"error":   "Noto'g'ri ma'lumot",
		})
		return
	}

	db, _ := getMainDB()
	defer db.Close()

	var user User
	var passwordHash string
	var categoriesStr, filialIDsStr sql.NullString
	var notificationID sql.NullString
	var isLogin int
	err := db.QueryRow("SELECT id, username, login, password_hash, role, filial_ids, categories, notification_id, is_login FROM users WHERE login = ?",
		req.Login).Scan(&user.ID, &user.Username, &user.Login, &passwordHash, &user.Role, &filialIDsStr, &categoriesStr, &notificationID, &isLogin)

	if err != nil {
		log.Printf("Login error: %v\n", err)
		respondJSON(w, http.StatusUnauthorized, map[string]interface{}{
			"success": false,
			"error":   "Login yoki parol noto'g'ri",
		})
		return
	}

	if err := bcrypt.CompareHashAndPassword([]byte(passwordHash), []byte(req.Password)); err != nil {
		respondJSON(w, http.StatusUnauthorized, map[string]interface{}{
			"success": false,
			"error":   "Login yoki parol noto'g'ri",
		})
		return
	}

	if categoriesStr.Valid && categoriesStr.String != "" {
		json.Unmarshal([]byte(categoriesStr.String), &user.Categories)
	}

	if filialIDsStr.Valid && filialIDsStr.String != "" {
		user.FilialIDs = parseFilialIDs(filialIDsStr.String)
	}

	if req.NotificationID != nil {
		db.Exec("UPDATE users SET notification_id = ?, is_login = 1 WHERE id = ?", *req.NotificationID, user.ID)
		user.NotificationID = req.NotificationID
	} else {
		db.Exec("UPDATE users SET is_login = 1 WHERE id = ?", user.ID)
	}
	user.IsLogin = true

	claims := &Claims{
		UserID:    user.ID,
		Username:  user.Username,
		Role:      user.Role,
		FilialIDs: user.FilialIDs,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(999999 * time.Hour)),
		},
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	tokenString, _ := token.SignedString(jwtSecret)

	respondJSON(w, http.StatusOK, map[string]interface{}{
		"success": true,
		"token":   tokenString,
		"user":    user,
	})
}

func logout(w http.ResponseWriter, r *http.Request) {
	userID, _ := strconv.Atoi(r.Header.Get("UserID"))

	db, _ := getMainDB()
	defer db.Close()

	_, err := db.Exec("UPDATE users SET is_login = 0 WHERE id = ?", userID)
	if err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]interface{}{
			"success": false,
			"error":   "Server xatosi",
		})
		return
	}

	respondJSON(w, http.StatusOK, map[string]interface{}{
		"success": true,
		"message": "Tizimdan chiqdingiz",
	})
}

func forceLogout(w http.ResponseWriter, r *http.Request) {
	role := r.Header.Get("Role")
	if role != RoleSuperAdmin {
		respondJSON(w, http.StatusForbidden, map[string]interface{}{
			"success": false,
			"error":   "Faqat super admin ruxsati",
		})
		return
	}

	vars := mux.Vars(r)
	targetUserID := vars["userId"]

	db, _ := getMainDB()
	defer db.Close()

	_, err := db.Exec("UPDATE users SET is_login = 0 WHERE id = ?", targetUserID)
	if err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]interface{}{
			"success": false,
			"error":   "Server xatosi",
		})
		return
	}

	respondJSON(w, http.StatusOK, map[string]interface{}{
		"success": true,
		"message": "User tizimdan chiqarildi",
	})
}

func getTasks(w http.ResponseWriter, r *http.Request) {
	role := r.Header.Get("Role")
	userID, _ := strconv.Atoi(r.Header.Get("UserID"))

	dateStr := r.URL.Query().Get("date")
	var date time.Time
	if dateStr == "" {
		date = time.Now()
	} else {
		var err error
		date, err = time.Parse("2006-01-02", dateStr)
		if err != nil {
			date = time.Now()
		}
	}

	db, err := getTaskDB(date)
	if err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]interface{}{
			"success": false,
			"error":   "Database xatosi",
		})
		return
	}
	defer db.Close()

	var query string
	var args []interface{}

	if role == RoleWorker {
		mainDB, _ := getMainDB()
		defer mainDB.Close()

		var filialIDsStr, categoriesStr sql.NullString
		err := mainDB.QueryRow("SELECT filial_ids, categories FROM users WHERE id = ?", userID).Scan(&filialIDsStr, &categoriesStr)
		if err != nil {
			respondJSON(w, http.StatusInternalServerError, map[string]interface{}{
				"success": false,
				"error":   "User ma'lumotlari topilmadi",
			})
			return
		}

		var categories []string
		if categoriesStr.Valid && categoriesStr.String != "" {
			json.Unmarshal([]byte(categoriesStr.String), &categories)
		}

		var filialIDs []int
		if filialIDsStr.Valid && filialIDsStr.String != "" {
			filialIDs = parseFilialIDs(filialIDsStr.String)
		}

		if len(filialIDs) == 0 || len(categories) == 0 {
			respondJSON(w, http.StatusOK, map[string]interface{}{
				"success": true,
				"data":    []Task{},
			})
			return
		}

		filialPlaceholders := make([]string, len(filialIDs))
		categoryPlaceholders := make([]string, len(categories))

		for i, id := range filialIDs {
			filialPlaceholders[i] = "?"
			args = append(args, id)
		}

		for i, cat := range categories {
			categoryPlaceholders[i] = "?"
			args = append(args, cat)
		}

		query = fmt.Sprintf(`
			SELECT id, filial_id, worker_ids, task, type, status, video_url, checker_audio_url, submitted_at, submitted_by, days, category, notification_time, order_index 
			FROM tasks 
			WHERE filial_id IN (%s) AND (category = '' OR category IN (%s))
			ORDER BY order_index ASC
		`, strings.Join(filialPlaceholders, ","), strings.Join(categoryPlaceholders, ","))
	} else {
		query = "SELECT id, filial_id, worker_ids, task, type, status, video_url, checker_audio_url, submitted_at, submitted_by, days, category, notification_time, order_index FROM tasks ORDER BY order_index ASC"
	}

	rows, err := db.Query(query, args...)
	if err != nil {
		log.Printf("getTasks query error: %v", err)
		respondJSON(w, http.StatusInternalServerError, map[string]interface{}{
			"success": false,
			"error":   "Server xatosi: " + err.Error(),
		})
		return
	}
	defer rows.Close()

	tasks := []Task{}
	for rows.Next() {
		var t Task
		var daysStr, notifTime, workerIDsStr sql.NullString
		var status sql.NullInt64
		var category sql.NullString
		var checkerAudioRaw *string
		t.Date = date.Format("2006-01-02")
		rows.Scan(&t.ID, &t.FilialID, &workerIDsStr, &t.Task, &t.Type, &status, &t.VideoURL, &checkerAudioRaw, &t.SubmittedAt, &t.SubmittedBy, &daysStr, &category, &notifTime, &t.OrderIndex)

		if status.Valid {
			v := int(status.Int64)
			t.Status = &v
		} else {
			t.Status = nil
		}

		if category.Valid {
			t.Category = category.String
		} else {
			t.Category = ""
		}
		t.CheckerAudioURLs = fullAudioURLs(parseCheckerAudioURLs(checkerAudioRaw))
		t.VideoURL = fullURL(t.VideoURL)

		if daysStr.Valid && daysStr.String != "" {
			t.Days = parseDays(daysStr.String)
		}
		if notifTime.Valid {
			t.NotificationTime = notifTime.String
		}
		if workerIDsStr.Valid && workerIDsStr.String != "" {
			t.WorkerIDs = parseFilialIDs(workerIDsStr.String)
		}

		tasks = append(tasks, t)
	}

	respondJSON(w, http.StatusOK, map[string]interface{}{
		"success": true,
		"data":    tasks,
	})
}

func getAllTasks(w http.ResponseWriter, r *http.Request) {
	role := r.Header.Get("Role")
	if role != RoleSuperAdmin {
		respondJSON(w, http.StatusForbidden, map[string]interface{}{
			"success": false,
			"error":   "Faqat super admin ruxsati",
		})
		return
	}

	mainDB, err := getMainDB()
	if err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]interface{}{
			"success": false,
			"error":   "Database xatosi",
		})
		return
	}
	defer mainDB.Close()

	rows, err := mainDB.Query("SELECT id, task, type, filial_ids, days, category, notification_time, order_index, created_at FROM task_templates ORDER BY order_index ASC, id ASC")
	if err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]interface{}{
			"success": false,
			"error":   "Server xatosi",
		})
		return
	}
	defer rows.Close()

	templates := []TaskTemplate{}
	for rows.Next() {
		var t TaskTemplate
		var filialIDsStr, daysStr, createdAt string
		var notifTime sql.NullString
		rows.Scan(&t.ID, &t.Task, &t.Type, &filialIDsStr, &daysStr, &t.Category, &notifTime, &t.OrderIndex, &createdAt)

		t.FilialIDs = parseFilialIDs(filialIDsStr)

		if daysStr != "" {
			t.Days = parseDays(daysStr)
		}
		if notifTime.Valid {
			t.NotificationTime = notifTime.String
		}

		t.CreatedAt = createdAt
		templates = append(templates, t)
	}

	needsFix := false
	for i, t := range templates {
		if t.OrderIndex != i+1 {
			needsFix = true
			break
		}
	}

	if needsFix {
		log.Println("Fixing order_index gaps...")
		for i, t := range templates {
			correctIndex := i + 1
			if t.OrderIndex != correctIndex {
				mainDB.Exec("UPDATE task_templates SET order_index = ? WHERE id = ?", correctIndex, t.ID)
				templates[i].OrderIndex = correctIndex
			}
		}
	}

	respondJSON(w, http.StatusOK, map[string]interface{}{
		"success": true,
		"data":    templates,
		"total":   len(templates),
	})
}

func createTask(w http.ResponseWriter, r *http.Request) {
	role := r.Header.Get("Role")
	if role != RoleSuperAdmin {
		respondJSON(w, http.StatusForbidden, map[string]interface{}{
			"success": false,
			"error":   "Ruxsat yo'q",
		})
		return
	}

	var req struct {
		FilialIDs        []int  `json:"filialIds"`
		Task             string `json:"task"`
		Type             int    `json:"type"`
		Days             []int  `json:"days"`
		Category         string `json:"category"`
		NotificationTime string `json:"time"`
	}

	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		respondJSON(w, http.StatusBadRequest, map[string]interface{}{
			"success": false,
			"error":   "Noto'g'ri ma'lumot",
		})
		return
	}

	if req.Type == TypeWeekly {
		for _, day := range req.Days {
			if day < 1 || day > 7 {
				respondJSON(w, http.StatusBadRequest, map[string]interface{}{
					"success": false,
					"error":   "Hafta kunlari 1-7 oralig'ida bo'lishi kerak",
				})
				return
			}
		}
	} else if req.Type == TypeMonthly {
		for _, day := range req.Days {
			if day < 1 || day > 31 {
				respondJSON(w, http.StatusBadRequest, map[string]interface{}{
					"success": false,
					"error":   "Oy kunlari 1-31 oralig'ida bo'lishi kerak",
				})
				return
			}
		}
	}

	mainDB, _ := getMainDB()
	defer mainDB.Close()

	filialIDsStr := strings.Trim(strings.Join(strings.Fields(fmt.Sprint(req.FilialIDs)), ","), "[]")
	daysStr := ""
	if len(req.Days) > 0 {
		daysStr = strings.Trim(strings.Join(strings.Fields(fmt.Sprint(req.Days)), ","), "[]")
	}

	_, err := mainDB.Exec("UPDATE task_templates SET order_index = order_index + 1 WHERE order_index > 0")
	if err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]interface{}{
			"success": false,
			"error":   "Tartibni yangilashda xato",
		})
		return
	}

	result, err := mainDB.Exec("INSERT INTO task_templates (task, type, filial_ids, days, category, notification_time, order_index) VALUES (?, ?, ?, ?, ?, ?, ?)",
		req.Task, req.Type, filialIDsStr, daysStr, req.Category, req.NotificationTime, 1)

	if err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]interface{}{
			"success": false,
			"error":   "Template yaratishda xato",
		})
		return
	}

	templateID, _ := result.LastInsertId()

	created := 0
	if req.Type == TypeDaily {
		created = createTasksForDate(int(templateID), req.Task, req.Type, req.FilialIDs, req.Days, req.Category, req.NotificationTime, time.Now())
	} else if req.Type == TypeWeekly {
		today := int(time.Now().Weekday())
		if today == 0 {
			today = 7
		}
		for _, day := range req.Days {
			if day == today {
				created = createTasksForDate(int(templateID), req.Task, req.Type, req.FilialIDs, req.Days, req.Category, req.NotificationTime, time.Now())
				break
			}
		}
	} else if req.Type == TypeMonthly {
		today := time.Now().Day()
		for _, day := range req.Days {
			if day == today {
				created = createTasksForDate(int(templateID), req.Task, req.Type, req.FilialIDs, req.Days, req.Category, req.NotificationTime, time.Now())
				break
			}
		}
	}

	respondJSON(w, http.StatusCreated, map[string]interface{}{
		"success": true,
		"taskId":  templateID,
		"created": created,
	})
}

func getTemplate(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	id := vars["id"]

	mainDB, _ := getMainDB()
	defer mainDB.Close()

	var template TaskTemplate
	var filialIDsStr, daysStr, createdAt string
	var notifTime sql.NullString

	err := mainDB.QueryRow("SELECT id, task, type, filial_ids, days, category, notification_time, order_index, created_at FROM task_templates WHERE id = ?", id).
		Scan(&template.ID, &template.Task, &template.Type, &filialIDsStr, &daysStr, &template.Category, &notifTime, &template.OrderIndex, &createdAt)

	if err != nil {
		respondJSON(w, http.StatusNotFound, map[string]interface{}{
			"success": false,
			"error":   "Template topilmadi",
		})
		return
	}

	template.FilialIDs = parseFilialIDs(filialIDsStr)
	if daysStr != "" {
		template.Days = parseDays(daysStr)
	}
	if notifTime.Valid {
		template.NotificationTime = notifTime.String
	}
	template.CreatedAt = createdAt

	respondJSON(w, http.StatusOK, map[string]interface{}{
		"success": true,
		"data":    template,
	})
}

func getTask(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	id := vars["id"]

	dateStr := r.URL.Query().Get("date")
	var date time.Time
	if dateStr == "" {
		date = time.Now()
	} else {
		date, _ = time.Parse("2006-01-02", dateStr)
	}

	db, _ := getTaskDB(date)
	defer db.Close()

	var task Task
	var daysStr, notifTime, workerIDsStr sql.NullString
	var status sql.NullInt64
	var checkerAudioRaw *string
	task.Date = date.Format("2006-01-02")

	err := db.QueryRow("SELECT id, filial_id, worker_ids, task, type, status, video_url, checker_audio_url, submitted_at, submitted_by, days, category, notification_time, order_index FROM tasks WHERE id = ?", id).
		Scan(&task.ID, &task.FilialID, &workerIDsStr, &task.Task, &task.Type, &status, &task.VideoURL, &checkerAudioRaw, &task.SubmittedAt, &task.SubmittedBy, &daysStr, &task.Category, &notifTime, &task.OrderIndex)

	if err != nil {
		respondJSON(w, http.StatusNotFound, map[string]interface{}{
			"success": false,
			"error":   "Vazifa topilmadi",
		})
		return
	}

	if status.Valid {
		v := int(status.Int64)
		task.Status = &v
	} else {
		task.Status = nil
	}
	task.CheckerAudioURLs = fullAudioURLs(parseCheckerAudioURLs(checkerAudioRaw))

	if daysStr.Valid && daysStr.String != "" {
		task.Days = parseDays(daysStr.String)
	}
	if notifTime.Valid {
		task.NotificationTime = notifTime.String
	}
	if workerIDsStr.Valid && workerIDsStr.String != "" {
		task.WorkerIDs = parseFilialIDs(workerIDsStr.String)
	}

	respondJSON(w, http.StatusOK, map[string]interface{}{
		"success": true,
		"data":    task,
	})
}

func updateTask(w http.ResponseWriter, r *http.Request) {
	role := r.Header.Get("Role")
	if role != RoleSuperAdmin {
		respondJSON(w, http.StatusForbidden, map[string]interface{}{
			"success": false,
			"error":   "Ruxsat yo'q",
		})
		return
	}

	vars := mux.Vars(r)
	id := vars["id"]

	var req struct {
		Task             string  `json:"task"`
		Type             int     `json:"type"`
		Status           *int    `json:"status,omitempty"`
		FilialIDs        []int   `json:"filialIds,omitempty"`
		WorkerIDs        []int   `json:"workerIds,omitempty"`
		Days             []int   `json:"days,omitempty"`
		Category         string  `json:"category"`
		NotificationTime *string `json:"time,omitempty"`
	}

	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		respondJSON(w, http.StatusBadRequest, map[string]interface{}{
			"success": false,
			"error":   "Noto'g'ri ma'lumot",
		})
		return
	}

	mainDB, _ := getMainDB()
	defer mainDB.Close()

	mainUpdateFields := []string{"task = ?", "type = ?", "category = ?"}
	mainArgs := []interface{}{req.Task, req.Type, req.Category}

	if len(req.FilialIDs) > 0 {
		filialIDsStr := strings.Trim(strings.Join(strings.Fields(fmt.Sprint(req.FilialIDs)), ","), "[]")
		mainUpdateFields = append(mainUpdateFields, "filial_ids = ?")
		mainArgs = append(mainArgs, filialIDsStr)
	}

	if len(req.Days) > 0 {
		daysStr := strings.Trim(strings.Join(strings.Fields(fmt.Sprint(req.Days)), ","), "[]")
		mainUpdateFields = append(mainUpdateFields, "days = ?")
		mainArgs = append(mainArgs, daysStr)
	}

	if req.NotificationTime != nil {
		mainUpdateFields = append(mainUpdateFields, "notification_time = ?")
		mainArgs = append(mainArgs, *req.NotificationTime)
	}

	mainArgs = append(mainArgs, id)
	mainQuery := fmt.Sprintf("UPDATE task_templates SET %s WHERE id = ?", strings.Join(mainUpdateFields, ", "))

	_, err := mainDB.Exec(mainQuery, mainArgs...)
	if err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]interface{}{
			"success": false,
			"error":   "Template yangilashda xato",
		})
		return
	}

	respondJSON(w, http.StatusOK, map[string]interface{}{
		"success": true,
		"message": "Template yangilandi",
	})
}

func deleteTask(w http.ResponseWriter, r *http.Request) {
	role := r.Header.Get("Role")
	if role != RoleSuperAdmin {
		respondJSON(w, http.StatusForbidden, map[string]interface{}{
			"success": false,
			"error":   "Ruxsat yo'q",
		})
		return
	}

	vars := mux.Vars(r)
	id := vars["id"]

	mainDB, _ := getMainDB()
	defer mainDB.Close()

	var taskName string
	err := mainDB.QueryRow("SELECT task FROM task_templates WHERE id = ?", id).Scan(&taskName)
	if err != nil {
		respondJSON(w, http.StatusNotFound, map[string]interface{}{
			"success": false,
			"error":   "Template topilmadi",
		})
		return
	}

	_, err = mainDB.Exec("DELETE FROM task_templates WHERE id = ?", id)
	if err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]interface{}{
			"success": false,
			"error":   "Template o'chirishda xato",
		})
		return
	}

	respondJSON(w, http.StatusOK, map[string]interface{}{
		"success": true,
		"message": "Template o'chirildi",
	})
}

func reorderTask(w http.ResponseWriter, r *http.Request) {
	role := r.Header.Get("Role")
	if role != RoleSuperAdmin {
		respondJSON(w, http.StatusForbidden, map[string]interface{}{
			"success": false,
			"error":   "Faqat super admin ruxsati",
		})
		return
	}

	vars := mux.Vars(r)

	oldPosition, err := strconv.Atoi(vars["taskId"])
	if err != nil || oldPosition < 1 {
		respondJSON(w, http.StatusBadRequest, map[string]interface{}{
			"success": false,
			"error":   "Noto'g'ri eski pozitsiya",
		})
		return
	}

	newPosition, err := strconv.Atoi(vars["newPosition"])
	if err != nil || newPosition < 1 {
		respondJSON(w, http.StatusBadRequest, map[string]interface{}{
			"success": false,
			"error":   "Noto'g'ri yangi pozitsiya",
		})
		return
	}

	mainDB, _ := getMainDB()
	defer mainDB.Close()

	tx, err := mainDB.Begin()
	if err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]interface{}{
			"success": false,
			"error":   "Database xatosi",
		})
		return
	}
	defer tx.Rollback()

	var templateID int
	var taskName string
	err = tx.QueryRow("SELECT id, task FROM task_templates WHERE order_index = ?", oldPosition).Scan(&templateID, &taskName)
	if err != nil {
		respondJSON(w, http.StatusNotFound, map[string]interface{}{
			"success": false,
			"error":   fmt.Sprintf("Bu pozitsiyada template topilmadi: %d", oldPosition),
		})
		return
	}

	if oldPosition == newPosition {
		tx.Commit()
		respondJSON(w, http.StatusOK, map[string]interface{}{
			"success": true,
			"message": "O'zgarish yo'q",
		})
		return
	}

	if newPosition < oldPosition {
		_, err = tx.Exec(`UPDATE task_templates SET order_index = order_index + 1 WHERE order_index >= ? AND order_index < ?`, newPosition, oldPosition)
	} else {
		_, err = tx.Exec(`UPDATE task_templates SET order_index = order_index - 1 WHERE order_index > ? AND order_index <= ?`, oldPosition, newPosition)
	}

	if err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]interface{}{
			"success": false,
			"error":   "Tartibni yangilashda xato",
		})
		return
	}

	_, err = tx.Exec("UPDATE task_templates SET order_index = ? WHERE id = ?", newPosition, templateID)
	if err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]interface{}{
			"success": false,
			"error":   "Template pozitsiyasini yangilashda xato",
		})
		return
	}

	tx.Commit()

	respondJSON(w, http.StatusOK, map[string]interface{}{
		"success":     true,
		"message":     fmt.Sprintf("Template %d-pozitsiyadan %d-pozitsiyaga ko'chirildi", oldPosition, newPosition),
		"templateId":  templateID,
		"taskName":    taskName,
		"oldPosition": oldPosition,
		"newPosition": newPosition,
	})
}

func reorderAllTasks(w http.ResponseWriter, r *http.Request) {
	role := r.Header.Get("Role")
	if role != RoleSuperAdmin {
		respondJSON(w, http.StatusForbidden, map[string]interface{}{
			"success": false,
			"error":   "Faqat super admin ruxsati",
		})
		return
	}

	var req struct {
		Order []int `json:"order"`
	}

	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		respondJSON(w, http.StatusBadRequest, map[string]interface{}{
			"success": false,
			"error":   "Noto'g'ri ma'lumot",
		})
		return
	}

	if len(req.Order) == 0 {
		respondJSON(w, http.StatusBadRequest, map[string]interface{}{
			"success": false,
			"error":   "Tartib bo'sh",
		})
		return
	}

	mainDB, _ := getMainDB()
	defer mainDB.Close()

	tx, err := mainDB.Begin()
	if err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]interface{}{
			"success": false,
			"error":   "Database xatosi",
		})
		return
	}
	defer tx.Rollback()

	for newIndex, templateID := range req.Order {
		_, err = tx.Exec("UPDATE task_templates SET order_index = ? WHERE id = ?", newIndex+1, templateID)
		if err != nil {
			respondJSON(w, http.StatusInternalServerError, map[string]interface{}{
				"success": false,
				"error":   fmt.Sprintf("Template %d yangilashda xato", templateID),
			})
			return
		}
	}

	tx.Commit()

	respondJSON(w, http.StatusOK, map[string]interface{}{
		"success": true,
		"message": fmt.Sprintf("%d ta template tartibi yangilandi", len(req.Order)),
		"count":   len(req.Order),
	})
}

// ==================== SUBMIT TASK ====================
// Worker video yuboradi -> status NULL ga o'tadi (admin/checker ko'rib chiqadi)
// submitTask - worker video yuborishi mumkin, qaysi statusda bo'lmasin

func submitTask(w http.ResponseWriter, r *http.Request) {
	role := r.Header.Get("Role")
	if role != RoleWorker && role != RoleChecker && role != RoleSuperAdmin {
		respondJSON(w, http.StatusForbidden, map[string]interface{}{
			"success": false,
			"error":   "Ruxsat yo'q",
		})
		return
	}

	vars := mux.Vars(r)
	taskID := vars["id"]
	username := r.Header.Get("Username")

	log.Printf("\n========== SUBMIT TASK ==========")
	log.Printf("📥 Task ID: %s, User: %s", taskID, username)

	// 200MB max upload
	err := r.ParseMultipartForm(200 << 20)
	if err != nil {
		log.Printf("❌ ParseMultipartForm error: %v", err)
		respondJSON(w, http.StatusBadRequest, map[string]interface{}{
			"success": false,
			"error":   "Form parse xatosi: " + err.Error(),
		})
		return
	}

	submittedAt := nowTashkent().Format(time.RFC3339)
	today := nowTashkent().Format("2006-01-02")

	// ── VIDEO (ko'p segment) ───────────────────────────────────────────────
	segmentCountStr := r.FormValue("segment_count")
	if segmentCountStr != "" {
		segmentCount, _ := strconv.Atoi(segmentCountStr)
		if segmentCount <= 0 {
			respondJSON(w, http.StatusBadRequest, map[string]interface{}{
				"success": false,
				"error":   "Segment count noto'g'ri",
			})
			return
		}

		dirPath := filepath.Join("./videos", today)
		os.MkdirAll(dirPath, 0755)

		log.Printf("📥 Task %s: %d ta segment qabul qilinyapti...", taskID, segmentCount)

		savedPaths, saveErr := saveSegmentsOnly(taskID, segmentCount, r, dirPath)
		if saveErr != nil {
			respondJSON(w, http.StatusInternalServerError, map[string]interface{}{
				"success": false,
				"error":   fmt.Sprintf("Segmentlarni saqlashda xato: %v", saveErr),
			})
			return
		}

		// Darhol 200 qaytarish
		respondJSON(w, http.StatusOK, map[string]interface{}{
			"success":     true,
			"message":     "Video qabul qilindi, qayta ishlanmoqda...",
			"submittedAt": submittedAt,
		})

		go mergeSegmentsBackground(taskID, username, submittedAt, savedPaths, dirPath)
		return
	}

	// ── VIDEO (bitta) ──────────────────────────────────────────────────────
	videoFile, videoHandler, videoErr := r.FormFile("video")
	if videoErr == nil {
		defer videoFile.Close()

		dirPath := filepath.Join("./videos", today)
		os.MkdirAll(dirPath, 0755)

		log.Printf("📥 Task %s: bitta video qabul qilinyapti...", taskID)

		videoURL, err := handleSingleVideo(taskID, videoFile, videoHandler, dirPath, today)
		if err != nil {
			respondJSON(w, http.StatusInternalServerError, map[string]interface{}{
				"success": false,
				"error":   "Video saqlash xatosi: " + err.Error(),
			})
			return
		}

		db, _ := getTaskDB(time.Now())
		defer db.Close()

		// Video yuborilganda status NULL ga o'tadi - admin/checker ko'rib chiqishi kerak
		db.Exec("UPDATE tasks SET status = NULL, video_url = ?, submitted_at = ?, submitted_by = ? WHERE id = ?",
			videoURL, submittedAt, username, taskID)
		log.Printf("✅ Video saqlandi: %s", videoURL)

		respondJSON(w, http.StatusOK, map[string]interface{}{
			"success":     true,
			"videoUrl":    videoURL,
			"submittedBy": username,
			"submittedAt": submittedAt,
		})

		// WS broadcast: video submitted
		hub.broadcast("task_updated", map[string]interface{}{
			"taskId": taskID,
			"action": "video_submitted",
			"date":   nowTashkent().Format("2006-01-02"),
		})
		return
	}

	respondJSON(w, http.StatusBadRequest, map[string]interface{}{
		"success": false,
		"error":   "Video topilmadi. 'video' yoki 'segment_count' + 'video_N' fieldlaridan birini yuboring",
	})
}

func saveAudioFile(taskID string, file io.Reader, handler *multipart.FileHeader, today string) (string, error) {
	dirPath := filepath.Join("./audios", today)
	if err := os.MkdirAll(dirPath, 0755); err != nil {
		return "", fmt.Errorf("papka yaratish xatosi: %v", err)
	}

	ext := filepath.Ext(handler.Filename)
	if ext == "" {
		ext = ".m4a"
	}

	timestamp := time.Now().UnixNano() / int64(time.Millisecond)
	filename := fmt.Sprintf("audio%s_%d%s", taskID, timestamp, ext)
	filePath := filepath.Join(dirPath, filename)

	outFile, err := os.Create(filePath)
	if err != nil {
		return "", fmt.Errorf("fayl yaratish xatosi: %v", err)
	}

	_, err = io.Copy(outFile, file)
	outFile.Close()

	if err != nil {
		return "", fmt.Errorf("fayl saqlash xatosi: %v", err)
	}

	return fmt.Sprintf("/audios/%s/%s", today, filename), nil
}

func saveSegmentsOnly(taskID string, segmentCount int, r *http.Request, dirPath string) ([]string, error) {
	timestamp := time.Now().UnixNano() / int64(time.Millisecond)
	segmentPaths := make([]string, segmentCount)

	for i := 0; i < segmentCount; i++ {
		fieldName := fmt.Sprintf("video_%d", i)
		file, handler, err := r.FormFile(fieldName)
		if err != nil {
			return nil, fmt.Errorf("segment %d topilmadi: %v", i, err)
		}
		defer file.Close()

		originalExt := filepath.Ext(handler.Filename)
		if originalExt == "" {
			originalExt = ".mp4"
		}

		segmentFilename := fmt.Sprintf("segment_%s_%d_%d%s", taskID, timestamp, i, originalExt)
		segmentPath := filepath.Join(dirPath, segmentFilename)

		segmentFile, err := os.Create(segmentPath)
		if err != nil {
			return nil, fmt.Errorf("segment %d yaratish xatosi: %v", i, err)
		}

		_, err = io.Copy(segmentFile, file)
		segmentFile.Close()

		if err != nil {
			return nil, fmt.Errorf("segment %d saqlash xatosi: %v", i, err)
		}

		segmentPaths[i] = segmentPath
		log.Printf("  ✓ Segment %d/%d saqlandi: %s", i+1, segmentCount, segmentFilename)
	}

	return segmentPaths, nil
}

func mergeSegmentsBackground(taskID, username, submittedAt string, segmentPaths []string, dirPath string) {
	log.Printf("🔄 Task %s: Background merge boshlandi...", taskID)

	_, err := exec.LookPath("ffmpeg")
	if err != nil {
		log.Printf("⚠️ FFmpeg topilmadi - birinchi segment ishlatiladi")
		updateTaskVideo(taskID, submittedAt, username, filepath.Base(segmentPaths[0]))
		return
	}

	timestamp := time.Now().UnixNano() / int64(time.Millisecond)
	listFilePath := filepath.Join(dirPath, fmt.Sprintf("concat_%s_%d.txt", taskID, timestamp))
	listFile, err := os.Create(listFilePath)
	if err != nil {
		log.Printf("❌ Concat list xatosi: %v", err)
		updateTaskVideo(taskID, submittedAt, username, filepath.Base(segmentPaths[0]))
		return
	}

	for _, segmentPath := range segmentPaths {
		filename := filepath.Base(segmentPath)
		listFile.WriteString(fmt.Sprintf("file '%s'\n", filename))
	}
	listFile.Close()

	outputFilename := fmt.Sprintf("video%s_%d.mp4", taskID, timestamp)
	outputPath := filepath.Join(dirPath, outputFilename)

	err = mergeVideos(listFilePath, outputPath)
	if err != nil {
		log.Printf("❌ FFmpeg xatosi: %v", err)
		updateTaskVideo(taskID, submittedAt, username, filepath.Base(segmentPaths[0]))
		os.Remove(listFilePath)
		return
	}

	os.Remove(listFilePath)
	for _, segmentPath := range segmentPaths {
		os.Remove(segmentPath)
	}

	log.Printf("✅ Task %s: Video birlashtirildi: %s", taskID, outputFilename)
	updateTaskVideo(taskID, submittedAt, username, outputFilename)
}

// updateTaskVideo - background merge tugagandan keyin DB ni yangilaydi
// status NULL ga o'tadi - admin/checker ko'rib chiqishi uchun
func updateTaskVideo(taskID, submittedAt, username, filename string) {
	today := nowTashkent().Format("2006-01-02")
	videoURL := fmt.Sprintf("/videos/%s/%s", today, filename)

	db, err := getTaskDB(time.Now())
	if err != nil {
		log.Printf("❌ DB ochishda xato: %v", err)
		return
	}
	defer db.Close()

	// Video merge tugaganda ham status NULL ga o'tadi
	_, err = db.Exec("UPDATE tasks SET status = NULL, video_url = ?, submitted_at = ?, submitted_by = ? WHERE id = ?",
		videoURL, submittedAt, username, taskID)

	if err != nil {
		log.Printf("❌ DB yangilashda xato: %v", err)
		return
	}

	log.Printf("✅ Task %s DB yangilandi (status=NULL): %s", taskID, videoURL)

	// WS broadcast: video merged
	hub.broadcast("task_updated", map[string]interface{}{
		"taskId": taskID,
		"action": "video_merged",
		"date":   today,
	})
}

// findFFmpeg - tizimda ffmpeg yo'lini topadi
func findFFmpeg() (string, error) {
	ffmpegPath, err := exec.LookPath("ffmpeg")
	if err == nil {
		return ffmpegPath, nil
	}
	for _, path := range []string{
		"/usr/bin/ffmpeg",
		"/usr/local/bin/ffmpeg",
		"/opt/homebrew/bin/ffmpeg",
	} {
		if _, err := os.Stat(path); err == nil {
			return path, nil
		}
	}
	return "", fmt.Errorf("ffmpeg topilmadi")
}

// cropVideoTo500 - inputPath videoni 500x500 crop qilib outputPath ga saqlaydi.
// Sifat o'zgarmaydi (-c:v copy ishlatilmaydi chunki crop filter kerak),
// lekin -crf 18 bilan yuqori sifat saqlanadi.
func cropVideoTo500(inputPath, outputPath string) error {
	ffmpegPath, err := findFFmpeg()
	if err != nil {
		return err
	}

	// crop=min(iw\,ih):min(iw\,ih) - markazdan kvadrat kesib oladi
	// scale=500:500 - 500x500 ga o'lchaydi
	// -c:v libx264 -crf 18 - yuqori sifat (18 = deyarli lossless)
	// -preset fast - tezlik/sifat balansi
	// -c:a copy - audio o'zgarmaydi
	cmd := exec.Command(ffmpegPath,
		"-i", inputPath,
		"-vf", "crop=min(iw\\,ih):min(iw\\,ih),scale=500:500",
		"-c:v", "libx264",
		"-crf", "18",
		"-preset", "fast",
		"-c:a", "copy",
		"-movflags", "+faststart",
		"-y",
		outputPath,
	)

	output, err := cmd.CombinedOutput()
	if err != nil {
		log.Printf("FFmpeg crop error: %s\n", string(output))
		return fmt.Errorf("crop xatosi: %v", err)
	}
	return nil
}

func handleSingleVideo(taskID string, file io.Reader, handler *multipart.FileHeader, dirPath, today string) (string, error) {
	timestamp := time.Now().UnixNano() / int64(time.Millisecond)

	// Avval original faylni temp nomida saqlaymiz
	originalExt := filepath.Ext(handler.Filename)
	if originalExt == "" {
		originalExt = ".mp4"
	}

	tempFilename := fmt.Sprintf("tmp_%s_%d%s", taskID, timestamp, originalExt)
	tempPath := filepath.Join(dirPath, tempFilename)

	tempFile, err := os.Create(tempPath)
	if err != nil {
		return "", fmt.Errorf("fayl yaratish xatosi: %v", err)
	}
	_, err = io.Copy(tempFile, file)
	tempFile.Close()
	if err != nil {
		os.Remove(tempPath)
		return "", fmt.Errorf("fayl saqlash xatosi: %v", err)
	}

	// Crop qilingan fayl nomi (har doim .mp4)
	croppedFilename := fmt.Sprintf("video%s_%d.mp4", taskID, timestamp)
	croppedPath := filepath.Join(dirPath, croppedFilename)

	// FFmpeg bilan 500x500 crop
	if cropErr := cropVideoTo500(tempPath, croppedPath); cropErr != nil {
		// FFmpeg ishlamasa original faylni qaytaramiz
		log.Printf("⚠️ Crop xatosi, original ishlatiladi: %v", cropErr)
		os.Rename(tempPath, croppedPath)
	} else {
		// Crop muvaffaqiyatli - temp faylni o'chiramiz
		os.Remove(tempPath)
		log.Printf("✅ Video 500x500 crop qilindi: %s", croppedFilename)
	}

	return fmt.Sprintf("/videos/%s/%s", today, croppedFilename), nil
}

func mergeVideos(listFilePath, outputPath string) error {
	ffmpegPath, err := findFFmpeg()
	if err != nil {
		return err
	}

	workDir := filepath.Dir(listFilePath)
	listFileName := filepath.Base(listFilePath)

	// Avval segmentlarni birlashtirамиз (temp fayl)
	tempOutput := filepath.Base(outputPath) + ".tmp.mp4"

	mergeCmd := exec.Command(ffmpegPath,
		"-f", "concat",
		"-safe", "0",
		"-i", listFileName,
		"-c", "copy",
		"-y",
		tempOutput,
	)
	mergeCmd.Dir = workDir

	mergeOut, err := mergeCmd.CombinedOutput()
	if err != nil {
		log.Printf("FFmpeg concat error: %s\n", string(mergeOut))
		return fmt.Errorf("merge xatosi: %v", err)
	}

	// Merge bo'lgan faylni 500x500 crop qilamiz
	tempFullPath := filepath.Join(workDir, tempOutput)
	cropCmd := exec.Command(ffmpegPath,
		"-i", tempOutput,
		"-vf", "crop=min(iw\\,ih):min(iw\\,ih),scale=500:500",
		"-c:v", "libx264",
		"-crf", "18",
		"-preset", "fast",
		"-c:a", "copy",
		"-movflags", "+faststart",
		"-y",
		filepath.Base(outputPath),
	)
	cropCmd.Dir = workDir

	cropOut, err := cropCmd.CombinedOutput()
	os.Remove(tempFullPath) // temp faylni har doim o'chiramiz
	if err != nil {
		log.Printf("FFmpeg crop error: %s\n", string(cropOut))
		// Crop ishlamasa merge qilingan faylni crop qilmasdan saqlaymiz
		os.Rename(tempFullPath, outputPath)
		return nil
	}

	log.Printf("✅ Merge + 500x500 crop muvaffaqiyatli")
	return nil
}

// checkTask - admin/checker task statusini o'zgartiradi
// Bu yerda status o'rnatiladi: 1=bajarilmagan, 2=kutilmoqda, 3=tasdiqlandi, 4=rad etildi
func checkTask(w http.ResponseWriter, r *http.Request) {
	role := r.Header.Get("Role")
	if role != RoleChecker && role != RoleSuperAdmin {
		respondJSON(w, http.StatusForbidden, map[string]interface{}{
			"success": false,
			"error":   "Ruxsat yo'q",
		})
		return
	}

	vars := mux.Vars(r)
	taskID := vars["id"]
	dateStr := vars["date"]

	var req struct {
		Status int `json:"status"`
	}

	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		respondJSON(w, http.StatusBadRequest, map[string]interface{}{
			"success": false,
			"error":   "Noto'g'ri ma'lumot",
		})
		return
	}

	var date time.Time
	if dateStr == "" {
		date = time.Now()
	} else {
		var err error
		date, err = time.Parse("2006-01-02", dateStr)
		if err != nil {
			respondJSON(w, http.StatusBadRequest, map[string]interface{}{
				"success": false,
				"error":   "Noto'g'ri sana formati (kerakli: 2006-01-02)",
			})
			return
		}
	}

	db, err := getTaskDB(date)
	if err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]interface{}{
			"success": false,
			"error":   "Database xatosi",
		})
		return
	}
	defer db.Close()

	_, err = db.Exec("UPDATE tasks SET status = ? WHERE id = ?", req.Status, taskID)
	if err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]interface{}{
			"success": false,
			"error":   "Server xatosi",
		})
		return
	}

	respondJSON(w, http.StatusOK, map[string]interface{}{
		"success": true,
		"message": fmt.Sprintf("%s sanasidagi task statusi yangilandi", date.Format("2006-01-02")),
	})

	// WS broadcast: task status changed
	hub.broadcast("task_updated", map[string]interface{}{
		"taskId": taskID,
		"action": "status_changed",
		"status": req.Status,
		"date":   date.Format("2006-01-02"),
	})
}

// submitCheckerAudio - barcha rollar ovozli izoh qoldira oladi (max 2 ta audio)
// Yangi audio qo'shilganda eski birinchisi o'chiriladi (FIFO, max 2)
func submitCheckerAudio(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	taskID := vars["id"]
	dateStr := vars["date"]
	username := r.Header.Get("Username")

	var date time.Time
	if dateStr == "" {
		date = time.Now()
	} else {
		var err error
		date, err = time.Parse("2006-01-02", dateStr)
		if err != nil {
			respondJSON(w, http.StatusBadRequest, map[string]interface{}{
				"success": false,
				"error":   "Noto'g'ri sana formati (kerakli: 2006-01-02)",
			})
			return
		}
	}

	if err := r.ParseMultipartForm(50 << 20); err != nil {
		respondJSON(w, http.StatusBadRequest, map[string]interface{}{
			"success": false,
			"error":   "Form parse xatosi",
		})
		return
	}

	audioFile, audioHandler, err := r.FormFile("audio")
	if err != nil {
		respondJSON(w, http.StatusBadRequest, map[string]interface{}{
			"success": false,
			"error":   "Audio topilmadi. 'audio' field yuboring",
		})
		return
	}
	defer audioFile.Close()

	today := date.Format("2006-01-02")
	audioURL, err := saveAudioFile("voice"+taskID, audioFile, audioHandler, today)
	if err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]interface{}{
			"success": false,
			"error":   "Audio saqlashda xato: " + err.Error(),
		})
		return
	}

	db, _ := getTaskDB(date)
	defer db.Close()

	// Mavjud audio URLlarni o'qish
	var existingRaw *string
	db.QueryRow("SELECT checker_audio_url FROM tasks WHERE id = ?", taskID).Scan(&existingRaw)
	existing := parseCheckerAudioURLs(existingRaw)

	// Yangi audio qo'shish
	existing = append(existing, audioURL)

	// Max 2 ta saqlash - eng eskisini o'chirish
	if len(existing) > 2 {
		// Birinchi (eng eski) audio faylini diskdan o'chirish
		oldPath := "." + existing[0] // "/audios/..." -> "./audios/..."
		os.Remove(oldPath)
		log.Printf("Eski audio o'chirildi: %s", oldPath)
		existing = existing[len(existing)-2:] // faqat oxirgi 2 tasini saqlash
	}

	// JSON array sifatida saqlash
	audioJSON, _ := json.Marshal(existing)
	_, err = db.Exec("UPDATE tasks SET checker_audio_url = ? WHERE id = ?", string(audioJSON), taskID)
	if err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]interface{}{
			"success": false,
			"error":   "DB yangilashda xato",
		})
		return
	}

	respondJSON(w, http.StatusOK, map[string]interface{}{
		"success":          true,
		"checkerAudioUrls": fullAudioURLs(existing),
		"commentBy":        username,
	})

	// WS broadcast: audio comment added
	hub.broadcast("task_updated", map[string]interface{}{
		"taskId": taskID,
		"action": "audio_comment",
		"date":   date.Format("2006-01-02"),
	})
}

// deleteCheckerAudio - ma'lum audio indexni o'chirish (0-based)
func deleteCheckerAudio(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	taskID := vars["id"]
	dateStr := vars["date"]
	audioIndexStr := vars["audioIndex"]

	audioIndex, err := strconv.Atoi(audioIndexStr)
	if err != nil {
		respondJSON(w, http.StatusBadRequest, map[string]interface{}{
			"success": false,
			"error":   "Noto'g'ri audio index",
		})
		return
	}

	var date time.Time
	if dateStr == "" {
		date = time.Now()
	} else {
		date, err = time.Parse("2006-01-02", dateStr)
		if err != nil {
			respondJSON(w, http.StatusBadRequest, map[string]interface{}{
				"success": false,
				"error":   "Noto'g'ri sana formati",
			})
			return
		}
	}

	db, _ := getTaskDB(date)
	defer db.Close()

	// Mavjud audio URLlarni o'qish
	var existingRaw *string
	db.QueryRow("SELECT checker_audio_url FROM tasks WHERE id = ?", taskID).Scan(&existingRaw)
	existing := parseCheckerAudioURLs(existingRaw)

	if audioIndex < 0 || audioIndex >= len(existing) {
		respondJSON(w, http.StatusBadRequest, map[string]interface{}{
			"success": false,
			"error":   "Audio index topilmadi",
		})
		return
	}

	// Faylni diskdan o'chirish
	oldPath := "." + existing[audioIndex]
	os.Remove(oldPath)
	log.Printf("Audio o'chirildi: %s", oldPath)

	// Arraydan olib tashlash
	existing = append(existing[:audioIndex], existing[audioIndex+1:]...)

	// DB yangilash
	var audioJSON string
	if len(existing) == 0 {
		audioJSON = ""
	} else {
		b, _ := json.Marshal(existing)
		audioJSON = string(b)
	}

	db.Exec("UPDATE tasks SET checker_audio_url = ? WHERE id = ?", audioJSON, taskID)

	respondJSON(w, http.StatusOK, map[string]interface{}{
		"success":          true,
		"checkerAudioUrls": fullAudioURLs(existing),
	})

	// WS broadcast
	hub.broadcast("task_updated", map[string]interface{}{
		"taskId": taskID,
		"action": "audio_deleted",
		"date":   date.Format("2006-01-02"),
	})
}

func getNotifications(w http.ResponseWriter, r *http.Request) {
	role := r.Header.Get("Role")
	if role != RoleWorker {
		respondJSON(w, http.StatusForbidden, map[string]interface{}{
			"success": false,
			"error":   "Ruxsat yo'q",
		})
		return
	}

	userID, _ := strconv.Atoi(r.Header.Get("UserID"))

	mainDB, _ := getMainDB()
	defer mainDB.Close()

	var filialIDsStr, categoriesStr sql.NullString
	err := mainDB.QueryRow("SELECT filial_ids, categories FROM users WHERE id = ?", userID).Scan(&filialIDsStr, &categoriesStr)
	if err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]interface{}{
			"success": false,
			"error":   "User ma'lumotlari topilmadi",
		})
		return
	}

	var categories []string
	if categoriesStr.Valid && categoriesStr.String != "" {
		json.Unmarshal([]byte(categoriesStr.String), &categories)
	}

	var filialIDs []int
	if filialIDsStr.Valid && filialIDsStr.String != "" {
		filialIDs = parseFilialIDs(filialIDsStr.String)
	}

	if len(filialIDs) == 0 || len(categories) == 0 {
		respondJSON(w, http.StatusOK, map[string]interface{}{
			"success": true,
			"data":    []Task{},
			"total":   0,
		})
		return
	}

	db, err := getTaskDB(time.Now())
	if err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]interface{}{
			"success": false,
			"error":   "Database xatosi",
		})
		return
	}
	defer db.Close()

	filialPlaceholders := make([]string, len(filialIDs))
	categoryPlaceholders := make([]string, len(categories))
	// NULL statusdagi tasklar ham ko'rsatiladi (yangi yuborilgan)
	args := []interface{}{}

	for i, id := range filialIDs {
		filialPlaceholders[i] = "?"
		args = append(args, id)
	}

	for i, cat := range categories {
		categoryPlaceholders[i] = "?"
		args = append(args, cat)
	}

	// status IS NULL yoki status = 1 (bajarilmagan) bo'lganlar
	query := fmt.Sprintf(`
		SELECT id, filial_id, worker_ids, task, type, status, video_url, checker_audio_url, submitted_at, submitted_by, days, category, notification_time, order_index 
		FROM tasks 
		WHERE (status IS NULL OR status = ?) AND filial_id IN (%s) AND (category = '' OR category IN (%s))
		ORDER BY order_index ASC
	`, strings.Join(filialPlaceholders, ","), strings.Join(categoryPlaceholders, ","))

	args = append([]interface{}{StatusNotDone}, args...)

	rows, err := db.Query(query, args...)
	if err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]interface{}{
			"success": false,
			"error":   "Server xatosi",
		})
		return
	}
	defer rows.Close()

	tasks := []Task{}
	for rows.Next() {
		var t Task
		var daysStr, notifTime, workerIDsStr sql.NullString
		var status sql.NullInt64
		var checkerAudioRaw *string
		t.Date = time.Now().Format("2006-01-02")
		rows.Scan(&t.ID, &t.FilialID, &workerIDsStr, &t.Task, &t.Type, &status, &t.VideoURL, &checkerAudioRaw, &t.SubmittedAt, &t.SubmittedBy, &daysStr, &t.Category, &notifTime, &t.OrderIndex)

		if status.Valid {
			v := int(status.Int64)
			t.Status = &v
		} else {
			t.Status = nil
		}
		t.CheckerAudioURLs = fullAudioURLs(parseCheckerAudioURLs(checkerAudioRaw))

		if daysStr.Valid && daysStr.String != "" {
			t.Days = parseDays(daysStr.String)
		}
		if notifTime.Valid {
			t.NotificationTime = notifTime.String
		}
		if workerIDsStr.Valid && workerIDsStr.String != "" {
			t.WorkerIDs = parseFilialIDs(workerIDsStr.String)
		}

		tasks = append(tasks, t)
	}

	respondJSON(w, http.StatusOK, map[string]interface{}{
		"success": true,
		"data":    tasks,
		"total":   len(tasks),
	})
}

func getFilials(w http.ResponseWriter, r *http.Request) {
	db, _ := getMainDB()
	defer db.Close()

	rows, err := db.Query("SELECT id, name FROM filials")
	if err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]interface{}{
			"success": false,
			"error":   "Server xatosi",
		})
		return
	}
	defer rows.Close()

	filials := []Filial{}
	for rows.Next() {
		var f Filial
		rows.Scan(&f.ID, &f.Name)
		filials = append(filials, f)
	}

	respondJSON(w, http.StatusOK, map[string]interface{}{
		"success": true,
		"data":    filials,
	})
}

func createFilial(w http.ResponseWriter, r *http.Request) {
	role := r.Header.Get("Role")
	if role != RoleSuperAdmin {
		respondJSON(w, http.StatusForbidden, map[string]interface{}{
			"success": false,
			"error":   "Ruxsat yo'q",
		})
		return
	}

	var req struct {
		Name string `json:"name"`
	}

	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		respondJSON(w, http.StatusBadRequest, map[string]interface{}{
			"success": false,
			"error":   "Noto'g'ri ma'lumot",
		})
		return
	}

	db, _ := getMainDB()
	defer db.Close()

	result, err := db.Exec("INSERT INTO filials (name) VALUES (?)", req.Name)
	if err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]interface{}{
			"success": false,
			"error":   "Server xatosi",
		})
		return
	}

	id, _ := result.LastInsertId()
	respondJSON(w, http.StatusCreated, map[string]interface{}{
		"success":  true,
		"filialId": id,
	})
}

func updateFilial(w http.ResponseWriter, r *http.Request) {
	role := r.Header.Get("Role")
	if role != RoleSuperAdmin {
		respondJSON(w, http.StatusForbidden, map[string]interface{}{
			"success": false,
			"error":   "Ruxsat yo'q",
		})
		return
	}

	vars := mux.Vars(r)
	id := vars["id"]

	var req struct {
		Name string `json:"name"`
	}

	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		respondJSON(w, http.StatusBadRequest, map[string]interface{}{
			"success": false,
			"error":   "Noto'g'ri ma'lumot",
		})
		return
	}

	db, _ := getMainDB()
	defer db.Close()

	_, err := db.Exec("UPDATE filials SET name = ? WHERE id = ?", req.Name, id)
	if err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]interface{}{
			"success": false,
			"error":   "Server xatosi",
		})
		return
	}

	respondJSON(w, http.StatusOK, map[string]interface{}{
		"success": true,
	})
}

func deleteFilial(w http.ResponseWriter, r *http.Request) {
	role := r.Header.Get("Role")
	if role != RoleSuperAdmin {
		respondJSON(w, http.StatusForbidden, map[string]interface{}{
			"success": false,
			"error":   "Ruxsat yo'q",
		})
		return
	}

	vars := mux.Vars(r)
	id := vars["id"]
	filialID, err := strconv.Atoi(id)
	if err != nil {
		respondJSON(w, http.StatusBadRequest, map[string]interface{}{
			"success": false,
			"error":   "Noto'g'ri filial ID",
		})
		return
	}

	db, _ := getMainDB()
	defer db.Close()

	rows, _ := db.Query("SELECT id, filial_ids FROM users WHERE filial_ids LIKE ?", "%"+id+"%")
	type userRow struct {
		id        int
		filialIDs string
	}
	var users []userRow
	for rows.Next() {
		var u userRow
		rows.Scan(&u.id, &u.filialIDs)
		users = append(users, u)
	}
	rows.Close()

	for _, u := range users {
		existingIDs := parseFilialIDs(u.filialIDs)
		newIDs := []int{}
		for _, fid := range existingIDs {
			if fid != filialID {
				newIDs = append(newIDs, fid)
			}
		}
		newIDsStr := strings.Trim(strings.Join(strings.Fields(fmt.Sprint(newIDs)), ","), "[]")
		db.Exec("UPDATE users SET filial_ids = ? WHERE id = ?", newIDsStr, u.id)
	}

	tRows, _ := db.Query("SELECT id, filial_ids FROM task_templates WHERE filial_ids LIKE ?", "%"+id+"%")
	type tmplRow struct {
		id        int
		filialIDs string
	}
	var tmpls []tmplRow
	for tRows.Next() {
		var t tmplRow
		tRows.Scan(&t.id, &t.filialIDs)
		tmpls = append(tmpls, t)
	}
	tRows.Close()

	for _, t := range tmpls {
		existingIDs := parseFilialIDs(t.filialIDs)
		newIDs := []int{}
		for _, fid := range existingIDs {
			if fid != filialID {
				newIDs = append(newIDs, fid)
			}
		}
		if len(newIDs) == 0 {
			db.Exec("DELETE FROM task_templates WHERE id = ?", t.id)
		} else {
			newIDsStr := strings.Trim(strings.Join(strings.Fields(fmt.Sprint(newIDs)), ","), "[]")
			db.Exec("UPDATE task_templates SET filial_ids = ? WHERE id = ?", newIDsStr, t.id)
		}
	}

	_, err = db.Exec("DELETE FROM filials WHERE id = ?", id)
	if err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]interface{}{
			"success": false,
			"error":   "Server xatosi",
		})
		return
	}

	respondJSON(w, http.StatusOK, map[string]interface{}{
		"success": true,
		"message": "Filial va unga bog'liq ma'lumotlar o'chirildi",
	})
}

func getCategories(w http.ResponseWriter, r *http.Request) {
	db, _ := getMainDB()
	defer db.Close()

	rows, err := db.Query("SELECT id, name FROM categories ORDER BY name ASC")
	if err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]interface{}{
			"success": false,
			"error":   "Server xatosi",
		})
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
	role := r.Header.Get("Role")
	if role != RoleSuperAdmin {
		respondJSON(w, http.StatusForbidden, map[string]interface{}{
			"success": false,
			"error":   "Ruxsat yo'q",
		})
		return
	}

	var req struct {
		Name string `json:"name"`
	}

	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		respondJSON(w, http.StatusBadRequest, map[string]interface{}{
			"success": false,
			"error":   "Noto'g'ri ma'lumot",
		})
		return
	}

	db, _ := getMainDB()
	defer db.Close()

	result, err := db.Exec("INSERT INTO categories (name) VALUES (?)", req.Name)
	if err != nil {
		respondJSON(w, http.StatusBadRequest, map[string]interface{}{
			"success": false,
			"error":   "Bu category allaqachon mavjud",
		})
		return
	}

	id, _ := result.LastInsertId()
	respondJSON(w, http.StatusCreated, map[string]interface{}{
		"success":    true,
		"categoryId": id,
	})
}

func updateCategory(w http.ResponseWriter, r *http.Request) {
	role := r.Header.Get("Role")
	if role != RoleSuperAdmin {
		respondJSON(w, http.StatusForbidden, map[string]interface{}{
			"success": false,
			"error":   "Ruxsat yo'q",
		})
		return
	}

	vars := mux.Vars(r)
	id := vars["id"]

	var req struct {
		Name string `json:"name"`
	}

	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		respondJSON(w, http.StatusBadRequest, map[string]interface{}{
			"success": false,
			"error":   "Noto'g'ri ma'lumot",
		})
		return
	}

	db, _ := getMainDB()
	defer db.Close()

	_, err := db.Exec("UPDATE categories SET name = ? WHERE id = ?", req.Name, id)
	if err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]interface{}{
			"success": false,
			"error":   "Server xatosi",
		})
		return
	}

	respondJSON(w, http.StatusOK, map[string]interface{}{
		"success": true,
	})
}

func deleteCategory(w http.ResponseWriter, r *http.Request) {
	role := r.Header.Get("Role")
	if role != RoleSuperAdmin {
		respondJSON(w, http.StatusForbidden, map[string]interface{}{
			"success": false,
			"error":   "Ruxsat yo'q",
		})
		return
	}

	vars := mux.Vars(r)
	id := vars["id"]

	db, _ := getMainDB()
	defer db.Close()

	var categoryName string
	err := db.QueryRow("SELECT name FROM categories WHERE id = ?", id).Scan(&categoryName)
	if err != nil {
		respondJSON(w, http.StatusNotFound, map[string]interface{}{
			"success": false,
			"error":   "Category topilmadi",
		})
		return
	}

	var userCount int
	db.QueryRow("SELECT COUNT(*) FROM users WHERE categories LIKE ?", "%"+categoryName+"%").Scan(&userCount)
	if userCount > 0 {
		respondJSON(w, http.StatusBadRequest, map[string]interface{}{
			"success": false,
			"error":   "Bu category'ni o'chirib bo'lmaydi, unga biriktirilgan userlar mavjud",
		})
		return
	}

	_, err = db.Exec("DELETE FROM categories WHERE id = ?", id)
	if err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]interface{}{
			"success": false,
			"error":   "Server xatosi",
		})
		return
	}

	respondJSON(w, http.StatusOK, map[string]interface{}{
		"success": true,
		"message": "Category o'chirildi",
	})
}

func generateJSONReport(w http.ResponseWriter, r *http.Request) {
	role := r.Header.Get("Role")
	if role != RoleSuperAdmin && role != RoleChecker {
		respondJSON(w, http.StatusForbidden, map[string]interface{}{
			"success": false,
			"error":   "Ruxsat yo'q",
		})
		return
	}

	filialIDStr := r.URL.Query().Get("filial_id")
	startDateStr := r.URL.Query().Get("start_date")
	endDateStr := r.URL.Query().Get("end_date")

	if filialIDStr == "" || startDateStr == "" || endDateStr == "" {
		respondJSON(w, http.StatusBadRequest, map[string]interface{}{
			"success": false,
			"error":   "filial_id, start_date va end_date kerak",
		})
		return
	}

	filialID, err := strconv.Atoi(filialIDStr)
	if err != nil {
		respondJSON(w, http.StatusBadRequest, map[string]interface{}{
			"success": false,
			"error":   "Noto'g'ri filial_id",
		})
		return
	}

	startDate, err := time.Parse("2006-01-02", startDateStr)
	if err != nil {
		respondJSON(w, http.StatusBadRequest, map[string]interface{}{
			"success": false,
			"error":   "Noto'g'ri start_date format",
		})
		return
	}

	endDate, err := time.Parse("2006-01-02", endDateStr)
	if err != nil {
		respondJSON(w, http.StatusBadRequest, map[string]interface{}{
			"success": false,
			"error":   "Noto'g'ri end_date format",
		})
		return
	}

	mainDB, _ := getMainDB()
	defer mainDB.Close()

	var filialName string
	err = mainDB.QueryRow("SELECT name FROM filials WHERE id = ?", filialID).Scan(&filialName)
	if err != nil {
		respondJSON(w, http.StatusNotFound, map[string]interface{}{
			"success": false,
			"error":   "Filial topilmadi",
		})
		return
	}

	jsonData := generateReportData(filialID, startDate, endDate)

	respondJSON(w, http.StatusOK, map[string]interface{}{
		"success":    true,
		"filialName": filialName,
		"startDate":  startDateStr,
		"endDate":    endDateStr,
		"data":       jsonData,
	})
}

func generateReportData(filialID int, startDate, endDate time.Time) []map[string]interface{} {
	type TaskEntry struct {
		TaskName    string  `json:"taskName"`
		Status      *int    `json:"status"` // nullable
		SubmittedAt *string `json:"submittedAt"`
		SubmittedBy *string `json:"submittedBy"`
		VideoURL    *string `json:"videoUrl"`

		StatusText    string `json:"statusText"`
		SubmittedTime string `json:"submittedTime"`
	}

	var result []map[string]interface{}

	currentDate := startDate
	for !currentDate.After(endDate) {
		dateStr := currentDate.Format("2006-01-02")

		taskDB, err := getTaskDB(currentDate)
		if err != nil {
			log.Printf("DB ochishda xato (%s): %v\n", dateStr, err)
			currentDate = currentDate.AddDate(0, 0, 1)
			continue
		}

		rows, err := taskDB.Query(`
			SELECT task, status, submitted_at, submitted_by, video_url
			FROM tasks
			WHERE filial_id = ?
			ORDER BY order_index ASC, id ASC
		`, filialID)

		if err != nil {
			taskDB.Close()
			currentDate = currentDate.AddDate(0, 0, 1)
			continue
		}

		var tasks []TaskEntry
		for rows.Next() {
			var t TaskEntry
			var status sql.NullInt64
			var submittedAt, submittedBy, videoURL sql.NullString

			err := rows.Scan(&t.TaskName, &status, &submittedAt, &submittedBy, &videoURL)
			if err != nil {
				continue
			}

			if status.Valid {
				v := int(status.Int64)
				t.Status = &v
			} else {
				t.Status = nil
			}

			if submittedAt.Valid {
				t.SubmittedAt = &submittedAt.String
				parsedTime, err := time.Parse(time.RFC3339, submittedAt.String)
				if err == nil {
					t.SubmittedTime = parsedTime.In(tashkentZone).Format("15:04")
				}
			}
			if submittedBy.Valid {
				t.SubmittedBy = &submittedBy.String
			}
			if videoURL.Valid {
				t.VideoURL = &videoURL.String
			}

			if t.Status == nil {
				t.StatusText = "Tekshirilmoqda"
			} else {
				switch *t.Status {
				case StatusNotDone:
					t.StatusText = "Bajarilmagan"
				case StatusPending:
					t.StatusText = "Kutilmoqda"
				case StatusRejected:
					t.StatusText = "Rad etildi"
				case StatusApproved:
					t.StatusText = "Tasdiqlandi"
				default:
					t.StatusText = "Noma'lum"
				}
			}

			tasks = append(tasks, t)
		}
		rows.Close()
		taskDB.Close()

		result = append(result, map[string]interface{}{
			"date":  currentDate.Format("02.01.2006"),
			"tasks": tasks,
		})

		currentDate = currentDate.AddDate(0, 0, 1)
	}

	return result
}

func generateExcelReport(w http.ResponseWriter, r *http.Request) {
	filialIDStr := r.URL.Query().Get("filial_id")
	startDateStr := r.URL.Query().Get("start_date")
	endDateStr := r.URL.Query().Get("end_date")

	if filialIDStr == "" || startDateStr == "" {
		respondJSON(w, http.StatusBadRequest, map[string]interface{}{
			"success": false,
			"error":   "filial_id va start_date kerak",
		})
		return
	}

	filialID, err := strconv.Atoi(filialIDStr)
	if err != nil {
		respondJSON(w, http.StatusBadRequest, map[string]interface{}{
			"success": false,
			"error":   "Noto'g'ri filial_id",
		})
		return
	}

	startDate, err := time.Parse("2006-01-02", startDateStr)
	if err != nil {
		respondJSON(w, http.StatusBadRequest, map[string]interface{}{
			"success": false,
			"error":   "Noto'g'ri start_date format",
		})
		return
	}

	var endDate time.Time
	if endDateStr == "" {
		endDate = startDate.AddDate(0, 0, 6)
	} else {
		endDate, err = time.Parse("2006-01-02", endDateStr)
		if err != nil {
			respondJSON(w, http.StatusBadRequest, map[string]interface{}{
				"success": false,
				"error":   "Noto'g'ri end_date format",
			})
			return
		}
		if int(endDate.Sub(startDate).Hours()/24) < 6 {
			endDate = startDate.AddDate(0, 0, 6)
		}
	}

	mainDB, _ := getMainDB()
	defer mainDB.Close()

	var filialName string
	err = mainDB.QueryRow("SELECT name FROM filials WHERE id = ?", filialID).Scan(&filialName)
	if err != nil {
		respondJSON(w, http.StatusNotFound, map[string]interface{}{
			"success": false,
			"error":   "Filial topilmadi",
		})
		return
	}

	excelFile, err := createExcelReport(filialID, filialName, startDate, endDate)
	if err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]interface{}{
			"success": false,
			"error":   "Excel yaratishda xato: " + err.Error(),
		})
		return
	}
	defer excelFile.Close()

	buffer, err := excelFile.WriteToBuffer()
	if err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]interface{}{
			"success": false,
			"error":   "Excel yozishda xato: " + err.Error(),
		})
		return
	}

	filename := fmt.Sprintf("%s_%s_%s.xlsx", filialName, startDateStr, endDateStr)
	w.Header().Set("Content-Type", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
	w.Header().Set("Content-Disposition", fmt.Sprintf("attachment; filename=\"%s\"", filename))
	w.Header().Set("Content-Length", strconv.Itoa(buffer.Len()))
	w.Write(buffer.Bytes())
}

func createExcelReport(filialID int, filialName string, startDate, endDate time.Time) (*excelize.File, error) {
	f := excelize.NewFile()

	sheetName := "Hisobot"
	index, _ := f.NewSheet(sheetName)
	f.SetActiveSheet(index)
	f.DeleteSheet("Sheet1")

	orientation := "landscape"
	f.SetPageLayout(sheetName, &excelize.PageLayoutOptions{
		Orientation: &orientation,
	})

	titleStyle, _ := f.NewStyle(&excelize.Style{
		Font:      &excelize.Font{Bold: true, Size: 14},
		Alignment: &excelize.Alignment{Horizontal: "center", Vertical: "center"},
	})

	headerStyle, _ := f.NewStyle(&excelize.Style{
		Font: &excelize.Font{Bold: true, Size: 12},
		Fill: excelize.Fill{Type: "pattern", Color: []string{"D3D3D3"}, Pattern: 1},
		Alignment: &excelize.Alignment{
			Horizontal: "center",
			Vertical:   "center",
			WrapText:   true,
		},
		Border: []excelize.Border{
			{Type: "left", Color: "000000", Style: 1},
			{Type: "right", Color: "000000", Style: 1},
			{Type: "top", Color: "000000", Style: 1},
			{Type: "bottom", Color: "000000", Style: 1},
		},
	})

	cellStyle, _ := f.NewStyle(&excelize.Style{
		Font: &excelize.Font{Bold: true, Size: 12},
		Alignment: &excelize.Alignment{
			Horizontal: "center",
			Vertical:   "center",
			WrapText:   true,
		},
	})

	taskCellStyle, _ := f.NewStyle(&excelize.Style{
		Font: &excelize.Font{Bold: true, Size: 14},
		Alignment: &excelize.Alignment{
			Horizontal: "left",
			Vertical:   "center",
			WrapText:   true,
		},
	})

	numberCellStyle, _ := f.NewStyle(&excelize.Style{
		Font: &excelize.Font{Bold: true, Size: 12},
		Alignment: &excelize.Alignment{
			Horizontal: "center",
			Vertical:   "center",
		},
	})

	statusApprovedStyle, _ := f.NewStyle(&excelize.Style{
		Font: &excelize.Font{Bold: true, Size: 12},
		Fill: excelize.Fill{Type: "pattern", Color: []string{"C6EFCE"}, Pattern: 1},
		Alignment: &excelize.Alignment{
			Horizontal: "center",
			Vertical:   "center",
			WrapText:   true,
		},
	})

	statusRejectedStyle, _ := f.NewStyle(&excelize.Style{
		Font: &excelize.Font{Bold: true, Size: 12},
		Fill: excelize.Fill{Type: "pattern", Color: []string{"FFC7CE"}, Pattern: 1},
		Alignment: &excelize.Alignment{
			Horizontal: "center",
			Vertical:   "center",
			WrapText:   true,
		},
	})

	statusPendingStyle, _ := f.NewStyle(&excelize.Style{
		Font: &excelize.Font{Bold: true, Size: 12},
		Fill: excelize.Fill{Type: "pattern", Color: []string{"FFFF00"}, Pattern: 1},
		Alignment: &excelize.Alignment{
			Horizontal: "center",
			Vertical:   "center",
			WrapText:   true,
		},
	})

	// Tekshirilmoqda (NULL status) - ko'k rang
	statusReviewStyle, _ := f.NewStyle(&excelize.Style{
		Font: &excelize.Font{Bold: true, Size: 12},
		Fill: excelize.Fill{Type: "pattern", Color: []string{"BDD7EE"}, Pattern: 1},
		Alignment: &excelize.Alignment{
			Horizontal: "center",
			Vertical:   "center",
			WrapText:   true,
		},
	})

	var dates []time.Time
	currentDate := startDate
	for !currentDate.After(endDate) {
		dates = append(dates, currentDate)
		currentDate = currentDate.AddDate(0, 0, 1)
	}

	f.SetColWidth(sheetName, "A", "A", 5)
	f.SetColWidth(sheetName, "B", "B", 80)
	for i := 0; i < len(dates); i++ {
		col := colName(i + 3)
		f.SetColWidth(sheetName, col, col, 20.7)
	}

	dateRange := fmt.Sprintf("%s - %s", startDate.Format("02.01.2006"), endDate.Format("02.01.2006"))
	title := fmt.Sprintf("%s   %s", dateRange, filialName)
	lastCol := colName(len(dates) + 2)
	f.MergeCell(sheetName, "A1", lastCol+"1")
	f.SetCellValue(sheetName, "A1", title)
	f.SetCellStyle(sheetName, "A1", lastCol+"1", titleStyle)
	f.SetRowHeight(sheetName, 1, 25)

	f.SetCellValue(sheetName, "A2", "№")
	f.SetCellStyle(sheetName, "A2", "A2", headerStyle)
	f.SetCellValue(sheetName, "B2", "ҚИЛИНАДИГАН ИШЛАР")
	f.SetCellStyle(sheetName, "B2", "B2", headerStyle)
	for i, date := range dates {
		col := colName(i + 3)
		f.SetCellValue(sheetName, col+"2", date.Format("02.01"))
		f.SetCellStyle(sheetName, col+"2", col+"2", headerStyle)
	}
	f.SetRowHeight(sheetName, 2, 30)

	var taskNames []string
	for _, checkDate := range dates {
		checkDB, err := getTaskDB(checkDate)
		if err != nil {
			continue
		}
		rows, err := checkDB.Query(`
			SELECT DISTINCT task FROM tasks
			WHERE filial_id = ?
			ORDER BY order_index ASC, id ASC
		`, filialID)
		if err != nil {
			checkDB.Close()
			continue
		}
		for rows.Next() {
			var taskName string
			rows.Scan(&taskName)
			taskNames = append(taskNames, taskName)
		}
		rows.Close()
		checkDB.Close()
		if len(taskNames) > 0 {
			break
		}
	}

	mainDB, _ := getMainDB()
	defer mainDB.Close()

	currentRow := 3
	for taskIndex, taskName := range taskNames {
		var notificationTime sql.NullString
		var taskType int
		mainDB.QueryRow(`
			SELECT notification_time, type FROM task_templates WHERE task = ? LIMIT 1
		`, taskName).Scan(&notificationTime, &taskType)

		timeInfo := ""
		if notificationTime.Valid && notificationTime.String != "" {
			timeInfo = notificationTime.String
			switch taskType {
			case TypeDaily:
				timeInfo += " - har kuni"
			case TypeWeekly:
				timeInfo += " - haftada"
			case TypeMonthly:
				timeInfo += " - oyda"
			}
		}

		f.SetCellValue(sheetName, fmt.Sprintf("A%d", currentRow), taskIndex+1)
		f.SetCellStyle(sheetName, fmt.Sprintf("A%d", currentRow), fmt.Sprintf("A%d", currentRow), numberCellStyle)

		taskText := taskName
		if timeInfo != "" {
			taskText = fmt.Sprintf("%s\n%s", taskName, timeInfo)
		}
		f.SetCellValue(sheetName, fmt.Sprintf("B%d", currentRow), taskText)
		f.SetCellStyle(sheetName, fmt.Sprintf("B%d", currentRow), fmt.Sprintf("B%d", currentRow), taskCellStyle)

		for dateIndex, date := range dates {
			col := colName(dateIndex + 3)
			cellRef := fmt.Sprintf("%s%d", col, currentRow)

			dayDB, err := getTaskDB(date)
			if err != nil {
				f.SetCellValue(sheetName, cellRef, "")
				f.SetCellStyle(sheetName, cellRef, cellRef, cellStyle)
				continue
			}

			var status sql.NullInt64
			var submittedAt, submittedBy, videoURL sql.NullString
			err = dayDB.QueryRow(`
				SELECT status, submitted_at, submitted_by, video_url
				FROM tasks WHERE filial_id = ? AND task = ? LIMIT 1
			`, filialID, taskName).Scan(&status, &submittedAt, &submittedBy, &videoURL)
			dayDB.Close()

			if err != nil {
				f.SetCellValue(sheetName, cellRef, "")
				f.SetCellStyle(sheetName, cellRef, cellRef, cellStyle)
				continue
			}

			mediaIcon := ""
			if videoURL.Valid && videoURL.String != "" {
				mediaIcon = "🎥"
			}

			var cellContent string
			var cellStyleToUse int

			// NULL status = video yuborilgan, tekshirilmoqda
			if !status.Valid {
				cellStyleToUse = statusReviewStyle
				if submittedAt.Valid && submittedBy.Valid {
					parsedTime, _ := time.Parse(time.RFC3339, submittedAt.String)
					cellContent = fmt.Sprintf("🔵 %s %s\n%s", parsedTime.In(tashkentZone).Format("15:04"), mediaIcon, submittedBy.String)
				} else {
					cellContent = "🔵 Tekshirilmoqda"
				}
			} else {
				switch int(status.Int64) {
				case StatusApproved:
					cellStyleToUse = statusApprovedStyle
					if submittedAt.Valid && submittedBy.Valid {
						parsedTime, _ := time.Parse(time.RFC3339, submittedAt.String)
						cellContent = fmt.Sprintf("✅ %s %s\n%s", parsedTime.In(tashkentZone).Format("15:04"), mediaIcon, submittedBy.String)
					} else {
						cellContent = "✅ Tasdiqlandi"
					}
				case StatusRejected:
					cellStyleToUse = statusRejectedStyle
					if submittedAt.Valid && submittedBy.Valid {
						parsedTime, _ := time.Parse(time.RFC3339, submittedAt.String)
						cellContent = fmt.Sprintf("❌ %s %s\n%s", parsedTime.In(tashkentZone).Format("15:04"), mediaIcon, submittedBy.String)
					} else {
						cellContent = "❌ Rad etildi"
					}
				case StatusPending:
					cellStyleToUse = statusPendingStyle
					if submittedAt.Valid && submittedBy.Valid {
						parsedTime, _ := time.Parse(time.RFC3339, submittedAt.String)
						cellContent = fmt.Sprintf("⏳ %s %s\n%s", parsedTime.In(tashkentZone).Format("15:04"), mediaIcon, submittedBy.String)
					} else {
						cellContent = "⏳ Kutilmoqda"
					}
				default: // StatusNotDone = 1
					cellStyleToUse = cellStyle
					cellContent = ""
				}
			}

			f.SetCellValue(sheetName, cellRef, cellContent)
			f.SetCellStyle(sheetName, cellRef, cellRef, cellStyleToUse)
		}

		f.SetRowHeight(sheetName, currentRow, 60)
		currentRow++
	}

	lastRow := currentRow + 2
	lastDataCol := colName(3)
	f.MergeCell(sheetName, fmt.Sprintf("A%d", lastRow), fmt.Sprintf("%s%d", lastDataCol, lastRow))
	f.SetCellValue(sheetName, fmt.Sprintf("A%d", lastRow), fmt.Sprintf("Дата изменения %s", nowTashkent().Format("02.01.2006")))

	adminCol := colName(4)
	f.SetCellValue(sheetName, fmt.Sprintf("%s%d", adminCol, lastRow), "Администрация")
	f.SetCellStyle(sheetName, fmt.Sprintf("%s%d", adminCol, lastRow), fmt.Sprintf("%s%d", adminCol, lastRow), numberCellStyle)

	return f, nil
}

func colName(n int) string {
	name := ""
	for n > 0 {
		n--
		name = string(rune('A'+n%26)) + name
		n /= 26
	}
	return name
}

func getUsers(w http.ResponseWriter, r *http.Request) {
	role := r.URL.Query().Get("role")
	filialID := r.URL.Query().Get("filialId")

	db, _ := getMainDB()
	defer db.Close()

	query := "SELECT id, username, login, role, filial_ids, categories, notification_id, is_login FROM users WHERE 1=1"
	args := []interface{}{}

	if role != "" {
		query += " AND role = ?"
		args = append(args, role)
	}
	if filialID != "" {
		query += " AND filial_ids LIKE ?"
		args = append(args, "%"+filialID+"%")
	}

	rows, err := db.Query(query, args...)
	if err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]interface{}{
			"success": false,
			"error":   "Server xatosi",
		})
		return
	}
	defer rows.Close()

	users := []User{}
	for rows.Next() {
		var u User
		var categoriesStr, filialIDsStr sql.NullString
		var notifID sql.NullString
		var isLogin int
		rows.Scan(&u.ID, &u.Username, &u.Login, &u.Role, &filialIDsStr, &categoriesStr, &notifID, &isLogin)

		if categoriesStr.Valid && categoriesStr.String != "" {
			json.Unmarshal([]byte(categoriesStr.String), &u.Categories)
		}
		if filialIDsStr.Valid && filialIDsStr.String != "" {
			u.FilialIDs = parseFilialIDs(filialIDsStr.String)
		}
		if notifID.Valid {
			u.NotificationID = &notifID.String
		}
		u.IsLogin = isLogin == 1

		users = append(users, u)
	}

	respondJSON(w, http.StatusOK, map[string]interface{}{
		"success": true,
		"data":    users,
	})
}

func updateUser(w http.ResponseWriter, r *http.Request) {
	role := r.Header.Get("Role")
	if role != RoleSuperAdmin {
		respondJSON(w, http.StatusForbidden, map[string]interface{}{
			"success": false,
			"error":   "Ruxsat yo'q",
		})
		return
	}

	vars := mux.Vars(r)
	id := vars["id"]

	var req struct {
		Username   string   `json:"username"`
		Role       string   `json:"role"`
		FilialIDs  []int    `json:"filialIds"`
		Categories []string `json:"categories"`
	}

	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		respondJSON(w, http.StatusBadRequest, map[string]interface{}{
			"success": false,
			"error":   "Noto'g'ri ma'lumot",
		})
		return
	}

	db, _ := getMainDB()
	defer db.Close()

	categoriesJSON, _ := json.Marshal(req.Categories)
	filialIDsStr := ""
	if len(req.FilialIDs) > 0 {
		filialIDsStr = strings.Trim(strings.Join(strings.Fields(fmt.Sprint(req.FilialIDs)), ","), "[]")
	}

	_, err := db.Exec("UPDATE users SET username = ?, role = ?, filial_ids = ?, categories = ? WHERE id = ?",
		req.Username, req.Role, filialIDsStr, string(categoriesJSON), id)
	if err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]interface{}{
			"success": false,
			"error":   "Server xatosi",
		})
		return
	}

	respondJSON(w, http.StatusOK, map[string]interface{}{
		"success": true,
	})
}

func deleteUser(w http.ResponseWriter, r *http.Request) {
	role := r.Header.Get("Role")
	if role != RoleSuperAdmin {
		respondJSON(w, http.StatusForbidden, map[string]interface{}{
			"success": false,
			"error":   "Ruxsat yo'q",
		})
		return
	}

	vars := mux.Vars(r)
	id := vars["id"]

	db, _ := getMainDB()
	defer db.Close()

	_, err := db.Exec("DELETE FROM users WHERE id = ?", id)
	if err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]interface{}{
			"success": false,
			"error":   "Server xatosi",
		})
		return
	}

	respondJSON(w, http.StatusOK, map[string]interface{}{
		"success": true,
	})
}

func startScheduler() {
	ticker := time.NewTicker(1 * time.Minute)
	defer ticker.Stop()

	var lastRun string

	for range ticker.C {
		now := time.Now()
		currentDay := now.Format("2006-01-02")

		if now.Hour() == 0 && now.Minute() == 0 && lastRun != currentDay {
			lastRun = currentDay
			log.Println("=== Starting daily tasks creation ===")

			ensureTodayDB()
			createDailyTasks()
			createWeeklyTasks()
			createMonthlyTasks()

			log.Println("=== Task creation completed ===")
		}
	}
}

func startCleanup() {
	ticker := time.NewTicker(1 * time.Hour)
	defer ticker.Stop()

	var lastCleanup string

	for range ticker.C {
		now := time.Now()
		currentDay := now.Format("2006-01-02")

		if now.Hour() == 1 && lastCleanup != currentDay {
			lastCleanup = currentDay
			log.Println("=== Starting cleanup ===")
			cleanupOldData()
			log.Println("=== Cleanup completed ===")
		}
	}
}

func startNotificationScheduler() {
	ticker := time.NewTicker(1 * time.Minute)
	defer ticker.Stop()

	for range ticker.C {
		checkAndSendNotifications()
	}
}

func checkAndSendNotifications() {
	now := time.Now()
	currentTime := now.Format("15:04")

	db, err := getTaskDB(now)
	if err != nil {
		return
	}
	defer db.Close()

	mainDB, _ := getMainDB()
	defer mainDB.Close()

	rows, err := db.Query(`
		SELECT t.id, t.task, t.worker_ids, t.category, t.notification_time, t.filial_id
		FROM tasks t 
		WHERE t.notification_time = ? AND (t.status IS NULL OR t.status = ?)`,
		currentTime, StatusNotDone)

	if err != nil {
		return
	}
	defer rows.Close()

	for rows.Next() {
		var taskID, filialID int
		var taskName, category, notifTime, workerIDsStr string
		rows.Scan(&taskID, &taskName, &workerIDsStr, &category, &notifTime, &filialID)

		workerIDs := parseFilialIDs(workerIDsStr)

		for _, workerID := range workerIDs {
			var notificationID sql.NullString
			err := mainDB.QueryRow("SELECT notification_id FROM users WHERE id = ? AND is_login = 1", workerID).Scan(&notificationID)

			if err == nil && notificationID.Valid && notificationID.String != "" {
				sendPushNotification(notificationID.String, taskName, category)
			}
		}
	}
}

func sendPushNotification(notificationID, taskName, category string) {
	log.Printf("Sending notification to %s: Task '%s' (Category: %s)\n", notificationID, taskName, category)
}

func createDailyTasks() {
	mainDB, _ := getMainDB()
	defer mainDB.Close()

	rows, err := mainDB.Query("SELECT id, task, filial_ids, category, notification_time FROM task_templates WHERE type = ?", TypeDaily)
	if err != nil {
		return
	}
	defer rows.Close()

	for rows.Next() {
		var templateID int
		var task, filialIDs, category string
		var notifTime sql.NullString
		rows.Scan(&templateID, &task, &filialIDs, &category, &notifTime)

		ids := parseFilialIDs(filialIDs)
		notifTimeStr := ""
		if notifTime.Valid {
			notifTimeStr = notifTime.String
		}
		createTasksForDate(templateID, task, TypeDaily, ids, nil, category, notifTimeStr, time.Now())
	}
}

func createWeeklyTasks() {
	mainDB, _ := getMainDB()
	defer mainDB.Close()

	rows, err := mainDB.Query("SELECT id, task, filial_ids, days, category, notification_time FROM task_templates WHERE type = ?", TypeWeekly)
	if err != nil {
		return
	}
	defer rows.Close()

	today := int(time.Now().Weekday())
	if today == 0 {
		today = 7
	}

	for rows.Next() {
		var templateID int
		var task, filialIDs, daysStr, category string
		var notifTime sql.NullString
		rows.Scan(&templateID, &task, &filialIDs, &daysStr, &category, &notifTime)

		days := parseDays(daysStr)
		shouldCreate := false
		for _, day := range days {
			if day == today {
				shouldCreate = true
				break
			}
		}

		if shouldCreate {
			ids := parseFilialIDs(filialIDs)
			notifTimeStr := ""
			if notifTime.Valid {
				notifTimeStr = notifTime.String
			}
			createTasksForDate(templateID, task, TypeWeekly, ids, days, category, notifTimeStr, time.Now())
		}
	}
}

func createMonthlyTasks() {
	mainDB, _ := getMainDB()
	defer mainDB.Close()

	rows, err := mainDB.Query("SELECT id, task, filial_ids, days, category, notification_time FROM task_templates WHERE type = ?", TypeMonthly)
	if err != nil {
		return
	}
	defer rows.Close()

	today := time.Now().Day()

	for rows.Next() {
		var templateID int
		var task, filialIDs, daysStr, category string
		var notifTime sql.NullString
		rows.Scan(&templateID, &task, &filialIDs, &daysStr, &category, &notifTime)

		days := parseDays(daysStr)
		shouldCreate := false
		for _, day := range days {
			if day == today {
				shouldCreate = true
				break
			}
		}

		if shouldCreate {
			ids := parseFilialIDs(filialIDs)
			notifTimeStr := ""
			if notifTime.Valid {
				notifTimeStr = notifTime.String
			}
			createTasksForDate(templateID, task, TypeMonthly, ids, days, category, notifTimeStr, time.Now())
		}
	}
}

func parseFilialIDs(filialIDs string) []int {
	ids := strings.Split(filialIDs, ",")
	result := []int{}
	for _, id := range ids {
		val, _ := strconv.Atoi(strings.TrimSpace(id))
		if val > 0 {
			result = append(result, val)
		}
	}
	return result
}

func parseDays(daysStr string) []int {
	if daysStr == "" {
		return []int{}
	}

	days := strings.Split(daysStr, ",")
	result := []int{}
	for _, day := range days {
		val, _ := strconv.Atoi(strings.TrimSpace(day))
		if val > 0 {
			result = append(result, val)
		}
	}
	return result
}

func createTasksForDate(templateID int, task string, taskType int, filialIDs []int, days []int, category, notificationTime string, date time.Time) int {
	taskDB, err := getTaskDB(date)
	if err != nil {
		log.Printf("Error opening task DB: %v\n", err)
		return 0
	}
	defer taskDB.Close()

	mainDB, _ := getMainDB()
	defer mainDB.Close()

	created := 0
	daysStr := ""
	if len(days) > 0 {
		daysStr = strings.Trim(strings.Join(strings.Fields(fmt.Sprint(days)), ","), "[]")
	}

	for _, filialID := range filialIDs {
		var rows *sql.Rows

		if category == "" {
			rows, err = mainDB.Query(`
				SELECT id FROM users 
				WHERE role = ? AND filial_ids LIKE ?`,
				RoleWorker, "%"+strconv.Itoa(filialID)+"%")
		} else {
			rows, err = mainDB.Query(`
				SELECT id FROM users 
				WHERE role = ? AND filial_ids LIKE ? AND categories LIKE ?`,
				RoleWorker, "%"+strconv.Itoa(filialID)+"%", "%"+category+"%")
		}

		if err != nil {
			continue
		}

		workerIDs := []int{}
		for rows.Next() {
			var workerID int
			rows.Scan(&workerID)
			workerIDs = append(workerIDs, workerID)
		}
		rows.Close()

		if len(workerIDs) == 0 {
			continue
		}

		var existingID int
		err = taskDB.QueryRow("SELECT id FROM tasks WHERE template_id = ? AND filial_id = ? AND category = ?",
			templateID, filialID, category).Scan(&existingID)

		if err == nil {
			continue
		}

		var maxOrder int
		taskDB.QueryRow("SELECT COALESCE(MAX(order_index), 0) FROM tasks WHERE filial_id = ? AND category = ?",
			filialID, category).Scan(&maxOrder)

		workerIDsStr := strings.Trim(strings.Join(strings.Fields(fmt.Sprint(workerIDs)), ","), "[]")

		// Task yaratilganda status NULL - hali hech kim ko'rmagan
		result, err := taskDB.Exec(`
   				INSERT INTO tasks (template_id, filial_id, worker_ids, task, type, status, days, category, notification_time, order_index) 
   				VALUES (?, ?, ?, ?, ?, NULL, ?, ?, ?, ?)`,
			templateID, filialID, workerIDsStr, task, taskType, daysStr, category, notificationTime, maxOrder+1)
		if err != nil {
			log.Printf("Error creating task: %v\n", err)
			continue
		}

		taskID, _ := result.LastInsertId()
		log.Printf("✓ Created task ID %d (status=NULL) for template %d, filial %d\n", taskID, templateID, filialID)
		created++
	}

	return created
}

func cleanupOldData() {
	cutoffDate := time.Now().AddDate(0, 0, -7)

	dbFiles, err := filepath.Glob("./db/tasks_*.db")
	if err == nil {
		for _, dbFile := range dbFiles {
			filename := filepath.Base(dbFile)
			dateStr := strings.TrimPrefix(filename, "tasks_")
			dateStr = strings.TrimSuffix(dateStr, ".db")

			fileDate, err := time.Parse("2006-01-02", dateStr)
			if err != nil {
				continue
			}

			if fileDate.Before(cutoffDate) {
				os.Remove(dbFile)
			}
		}
	}

	videoDirs, err := os.ReadDir("./videos")
	if err == nil {
		for _, entry := range videoDirs {
			if !entry.IsDir() {
				continue
			}
			dirDate, err := time.Parse("2006-01-02", entry.Name())
			if err != nil {
				continue
			}
			if dirDate.Before(cutoffDate) {
				os.RemoveAll(filepath.Join("./videos", entry.Name()))
			}
		}
	}

	audioDirs, err := os.ReadDir("./audios")
	if err == nil {
		for _, entry := range audioDirs {
			if !entry.IsDir() {
				continue
			}
			dirDate, err := time.Parse("2006-01-02", entry.Name())
			if err != nil {
				continue
			}
			if dirDate.Before(cutoffDate) {
				os.RemoveAll(filepath.Join("./audios", entry.Name()))
			}
		}
	}
}

func getDebugInfo(w http.ResponseWriter, r *http.Request) {
	mainDB, _ := getMainDB()
	defer mainDB.Close()

	var workerCount, checkerCount, adminCount int
	mainDB.QueryRow("SELECT COUNT(*) FROM users WHERE role = ?", RoleWorker).Scan(&workerCount)
	mainDB.QueryRow("SELECT COUNT(*) FROM users WHERE role = ?", RoleChecker).Scan(&checkerCount)
	mainDB.QueryRow("SELECT COUNT(*) FROM users WHERE role = ?", RoleSuperAdmin).Scan(&adminCount)

	var templateCount int
	mainDB.QueryRow("SELECT COUNT(*) FROM task_templates").Scan(&templateCount)

	rows, _ := mainDB.Query("SELECT id, username, login, filial_ids, categories FROM users WHERE role = ?", RoleWorker)
	defer rows.Close()

	workers := []map[string]interface{}{}
	for rows.Next() {
		var id int
		var username, login, filialIDsStr string
		var categoriesStr sql.NullString
		rows.Scan(&id, &username, &login, &filialIDsStr, &categoriesStr)

		var categories []string
		if categoriesStr.Valid && categoriesStr.String != "" {
			json.Unmarshal([]byte(categoriesStr.String), &categories)
		}

		filialIDs := parseFilialIDs(filialIDsStr)
		workers = append(workers, map[string]interface{}{
			"id":         id,
			"username":   username,
			"login":      login,
			"filialIds":  filialIDs,
			"categories": categories,
		})
	}

	todayDB, _ := getTaskDB(time.Now())
	defer todayDB.Close()

	var taskTotal, taskNull, taskNotDone, taskPending, taskApproved int
	todayDB.QueryRow("SELECT COUNT(*) FROM tasks").Scan(&taskTotal)
	todayDB.QueryRow("SELECT COUNT(*) FROM tasks WHERE status IS NULL").Scan(&taskNull)
	todayDB.QueryRow("SELECT COUNT(*) FROM tasks WHERE status = ?", StatusNotDone).Scan(&taskNotDone)
	todayDB.QueryRow("SELECT COUNT(*) FROM tasks WHERE status = ?", StatusPending).Scan(&taskPending)
	todayDB.QueryRow("SELECT COUNT(*) FROM tasks WHERE status = ?", StatusApproved).Scan(&taskApproved)

	dbFiles, _ := filepath.Glob("./db/tasks_*.db")
	dbDates := []string{}
	for _, f := range dbFiles {
		name := filepath.Base(f)
		date := strings.TrimPrefix(name, "tasks_")
		date = strings.TrimSuffix(date, ".db")
		dbDates = append(dbDates, date)
	}

	respondJSON(w, http.StatusOK, map[string]interface{}{
		"success": true,
		"data": map[string]interface{}{
			"users": map[string]interface{}{
				"workers":    workerCount,
				"checkers":   checkerCount,
				"admins":     adminCount,
				"workerList": workers,
			},
			"templates": templateCount,
			"todayTasks": map[string]interface{}{
				"total":      taskTotal,
				"nullStatus": taskNull,
				"notDone":    taskNotDone,
				"pending":    taskPending,
				"approved":   taskApproved,
			},
			"databases": map[string]interface{}{
				"count": len(dbDates),
				"dates": dbDates,
			},
			"currentDate": time.Now().Format("2006-01-02"),
		},
	})
}

const (
	IOSVersion     = "1.0.0"
	AndroidVersion = "1.0.0"
	AppStoreURL    = "https://apps.apple.com/app/id6752371524"
	PlayStoreURL   = "https://play.google.com/store/apps/details?id=com.example.app"
)

func healthCheck(w http.ResponseWriter, r *http.Request) {
	respondJSON(w, http.StatusOK, map[string]interface{}{
		"success": true,
		"data": map[string]interface{}{
			"iphoneVersion":  IOSVersion,
			"androidVersion": AndroidVersion,
			"appstoreUrl":    AppStoreURL,
			"playstoreUrl":   PlayStoreURL,
		},
	})
}

func respondJSON(w http.ResponseWriter, status int, data interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(data)
}
