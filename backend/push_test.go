package main

import (
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

type fakeFCM struct {
	mu       sync.Mutex
	messages []map[string]interface{}
}

func (f *fakeFCM) sent() []map[string]interface{} {
	f.mu.Lock()
	defer f.mu.Unlock()
	return append([]map[string]interface{}{}, f.messages...)
}

// setupFakeFCM — OAuth va FCM o'rniga lokal server; "dead" token 404 qaytaradi
func setupFakeFCM(t *testing.T) *fakeFCM {
	t.Helper()
	fake := &fakeFCM{}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/token" {
			json.NewEncoder(w).Encode(map[string]interface{}{"access_token": "tok", "expires_in": 3600})
			return
		}
		if r.Header.Get("Authorization") != "Bearer tok" {
			t.Errorf("auth sarlavhasi: %q", r.Header.Get("Authorization"))
		}
		raw, _ := io.ReadAll(r.Body)
		var body map[string]interface{}
		json.Unmarshal(raw, &body)
		msg := body["message"].(map[string]interface{})
		if msg["token"] == "dead" {
			w.WriteHeader(http.StatusNotFound)
			w.Write([]byte(`{"error":{"status":"NOT_FOUND","details":[{"errorCode":"UNREGISTERED"}]}}`))
			return
		}
		fake.mu.Lock()
		fake.messages = append(fake.messages, msg)
		fake.mu.Unlock()
		w.Write([]byte(`{"name":"ok"}`))
	}))
	t.Cleanup(srv.Close)

	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}
	keyPEM := pem.EncodeToMemory(&pem.Block{Type: "RSA PRIVATE KEY", Bytes: x509.MarshalPKCS1PrivateKey(key)})
	credPath := filepath.Join(t.TempDir(), "sa.json")
	raw, _ := json.Marshal(fcmCredentials{
		ProjectID: "demo", ClientEmail: "a@b", PrivateKey: string(keyPEM), TokenURI: srv.URL + "/token",
	})
	os.WriteFile(credPath, raw, 0o600)
	t.Setenv("FIREBASE_CREDENTIALS", credPath)

	oldBase := fcmBaseURL
	fcmBaseURL = srv.URL
	resetToken := func() { fcmAccessToken, fcmTokenExpiry = "", time.Time{} }
	resetToken()
	t.Cleanup(func() { fcmBaseURL = oldBase; resetToken() })
	return fake
}

func pushTestDB(t *testing.T) {
	t.Helper()
	wd, _ := os.Getwd()
	os.Chdir(t.TempDir())
	t.Cleanup(func() { os.Chdir(wd) })
	initDB()
}

func TestPushWithoutCredentialsIsSilent(t *testing.T) {
	pushTestDB(t)
	t.Setenv("FIREBASE_CREDENTIALS", filepath.Join(t.TempDir(), "yoq.json"))
	mainDB, _ := getMainDB()
	defer mainDB.Close()
	mainDB.Exec("INSERT INTO device_tokens (token, user_id, updated_at) VALUES ('a', 1, 'x')")

	if got := pushToUsers(mainDB, []int{1}, "t", "b", nil); len(got) != 0 {
		t.Fatalf("sozlanmagan push hech kimga yetmasligi kerak: %v", got)
	}
}

func TestPushReachesAllDevicesAndDropsStaleToken(t *testing.T) {
	pushTestDB(t)
	fake := setupFakeFCM(t)
	mainDB, _ := getMainDB()
	defer mainDB.Close()
	for _, row := range [][2]interface{}{{"phone", 1}, {"tablet", 1}, {"dead", 2}, {"other", 3}} {
		mainDB.Exec("INSERT INTO device_tokens (token, user_id, updated_at) VALUES (?, ?, 'x')", row[0], row[1])
	}

	reached := pushToUsers(mainDB, []int{1, 2}, "Сарлавҳа", "Матн", map[string]string{"type": "task_demand"})
	if !reached[1] || reached[2] || reached[3] {
		t.Fatalf("yetganlar: %v", reached)
	}
	sent := fake.sent()
	if len(sent) != 2 {
		t.Fatalf("2 ta qurilmaga borishi kerak: %+v", sent)
	}
	// Ovoz: ikkala platformada ham default tovush va baland ustuvorlik
	aps := sent[0]["apns"].(map[string]interface{})["payload"].(map[string]interface{})["aps"].(map[string]interface{})
	android := sent[0]["android"].(map[string]interface{})
	notif := android["notification"].(map[string]interface{})
	if aps["sound"] != "default" || notif["sound"] != "default" ||
		notif["channel_id"] != demandPushChannel || android["priority"] != "HIGH" {
		t.Fatalf("ovoz sozlamalari: %+v", sent[0])
	}

	var n int
	mainDB.QueryRow("SELECT COUNT(*) FROM device_tokens WHERE token = 'dead'").Scan(&n)
	if n != 0 {
		t.Fatal("yaroqsiz token o'chirilishi kerak edi")
	}
}

func TestDeviceTokenEndpoints(t *testing.T) {
	pushTestDB(t)
	call := func(h http.HandlerFunc, method, user, body string) int {
		r := httptest.NewRequest(method, "/api/device-token", strings.NewReader(body))
		r.Header.Set("UserID", user)
		w := httptest.NewRecorder()
		h(w, r)
		return w.Code
	}
	owner := func() (id int) {
		mainDB, _ := getMainDB()
		defer mainDB.Close()
		mainDB.QueryRow("SELECT user_id FROM device_tokens WHERE token = 'x'").Scan(&id)
		return
	}

	if c := call(saveDeviceToken, "POST", "5", `{"token":"  "}`); c != http.StatusBadRequest {
		t.Fatalf("bo'sh token: %d", c)
	}
	call(saveDeviceToken, "POST", "5", `{"token":"x","platform":"ios"}`)
	if owner() != 5 {
		t.Fatal("token saqlanmadi")
	}
	// Telefon boshqa hisobga kirdi — token yangi egasiga o'tadi
	call(saveDeviceToken, "POST", "6", `{"token":"x","platform":"ios"}`)
	if owner() != 6 {
		t.Fatal("token ko'chmadi")
	}
	// Begona foydalanuvchi o'chira olmaydi
	call(deleteDeviceToken, "DELETE", "5", `{"token":"x"}`)
	if owner() != 6 {
		t.Fatal("begona token o'chib ketdi")
	}
	call(deleteDeviceToken, "DELETE", "6", `{"token":"x"}`)
	if owner() != 0 {
		t.Fatal("token o'chmadi")
	}
}

func TestPushDemandSendsToResponsibles(t *testing.T) {
	pushTestDB(t)
	fake := setupFakeFCM(t)
	mainDB, _ := getMainDB()
	defer mainDB.Close()
	mainDB.Exec("INSERT INTO device_tokens (token, user_id, updated_at) VALUES ('a', 1, 'x'), ('b', 9, 'x')")

	d := pushDemand(mainDB, OverdueTask{
		TaskID: 7, FilialName: "Мархабо", Task: "Текшириш",
		Responsible: []Responsible{{UserID: 1, Username: "A"}},
		Demand:      &DemandInfo{DemandedBy: "F", LastAt: "10:00", Count: 1},
	})
	if !d.Pushed[1] || len(d.Pushed) != 1 || len(d.Online) != 0 {
		t.Fatalf("yetkazish: %+v", d)
	}
	sent := fake.sent()
	if len(sent) != 1 || sent[0]["token"] != "a" {
		t.Fatalf("faqat mas'ulga borishi kerak: %+v", sent)
	}
	n := sent[0]["notification"].(map[string]interface{})
	if n["body"] != "Мархабо · Текшириш" {
		t.Fatalf("matn: %+v", n)
	}
	if sent[0]["data"].(map[string]interface{})["taskId"] != "7" {
		t.Fatalf("data: %+v", sent[0]["data"])
	}
}
