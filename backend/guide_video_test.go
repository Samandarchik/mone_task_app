package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"testing"

	"github.com/gorilla/mux"
)

func guideVideoReq(t *testing.T, method string, templateID string, role string, userID string, video []byte) *httptest.ResponseRecorder {
	t.Helper()
	var body bytes.Buffer
	contentType := ""
	if video != nil {
		mw := multipart.NewWriter(&body)
		fw, _ := mw.CreateFormFile("video", "guide.mp4")
		fw.Write(video)
		mw.Close()
		contentType = mw.FormDataContentType()
	}
	req := httptest.NewRequest(method, "/api/templates/"+templateID+"/guide-video", &body)
	if contentType != "" {
		req.Header.Set("Content-Type", contentType)
	}
	req.Header.Set("Role", role)
	req.Header.Set("UserID", userID)
	req = mux.SetURLVars(req, map[string]string{"id": templateID})
	rec := httptest.NewRecorder()
	if method == http.MethodPost {
		uploadGuideVideo(rec, req)
	} else {
		deleteGuideVideo(rec, req)
	}
	return rec
}

func guideURLs(t *testing.T) map[int]string {
	t.Helper()
	req := httptest.NewRequest(http.MethodGet, "/api/tasks", nil)
	req.Header.Set("Role", RoleSuperAdmin)
	req.Header.Set("UserID", "1")
	rec := httptest.NewRecorder()
	getTasks(rec, req)
	var resp struct {
		Data []Task `json:"data"`
	}
	json.NewDecoder(rec.Body).Decode(&resp)
	out := map[int]string{}
	for _, task := range resp.Data {
		out[task.TemplateID] = task.GuideVideoURL
	}
	return out
}

// Namuna video bir xil matnli vazifaning barcha filiallardagi shablonlariga
// qo'yiladi, ishchining vazifasida ko'rinadi va o'chirilganda fayli ham ketadi.
func TestGuideVideoSharedAcrossFilials(t *testing.T) {
	wd, _ := os.Getwd()
	os.Chdir(t.TempDir())
	t.Cleanup(func() { os.Chdir(wd) })
	initDB()
	mainDB, _ := getMainDB()
	res, _ := mainDB.Exec("INSERT INTO users (username, login, password_hash, role, filial_ids, categories) VALUES ('W', 'w', 'x', ?, '1', '[\"X\"]')", RoleWorker)
	workerID, _ := res.LastInsertId()
	res, _ = mainDB.Exec("INSERT INTO users (username, login, password_hash, role, filial_ids, categories) VALUES ('W2', 'w2', 'x', ?, '2', '[\"X\"]')", RoleWorker)
	otherID, _ := res.LastInsertId()
	mainDB.Close()
	worker, other := fmt.Sprint(workerID), fmt.Sprint(otherID)

	createTemplate(t, `{"task":"Pol yuvish","type":1,"filialIds":[1,2],"category":""}`)
	createTemplate(t, `{"task":"Boshqa","type":1,"filialIds":[1],"category":""}`)

	// Korrektor va boshqa filial ishchisi yuklay olmaydi
	if rec := guideVideoReq(t, http.MethodPost, "1", RoleChecker, worker, []byte("v")); rec.Code != http.StatusForbidden {
		t.Fatalf("checker yuklay olmasligi kerak, status: %d", rec.Code)
	}
	if rec := guideVideoReq(t, http.MethodPost, "1", RoleWorker, other, []byte("v")); rec.Code != http.StatusForbidden {
		t.Fatalf("boshqa filial ishchisi yuklay olmasligi kerak, status: %d", rec.Code)
	}

	// O'z filialidagi ishchi bir marta yuklaydi
	rec := guideVideoReq(t, http.MethodPost, "1", RoleWorker, worker, []byte("fake video"))
	if rec.Code != http.StatusOK {
		t.Fatalf("yuklash status: %d (%s)", rec.Code, rec.Body.String())
	}
	if rec := guideVideoReq(t, http.MethodPost, "1", RoleWorker, worker, []byte("v2")); rec.Code != http.StatusForbidden {
		t.Fatalf("ikkinchi marta yuklay olmasligi kerak, status: %d", rec.Code)
	}
	if rec := guideVideoReq(t, http.MethodDelete, "1", RoleWorker, worker, nil); rec.Code != http.StatusForbidden {
		t.Fatalf("worker o'chira olmasligi kerak, status: %d", rec.Code)
	}
	got := guideURLs(t)
	url := got[1]
	if url == "" || got[2] != url || got[3] != "" {
		t.Fatalf("namuna videolar: %v (1 va 2 da bir xil, 3 da bo'sh bo'lishi kerak)", got)
	}
	file := filepath.Join(guideVideoDir, filepath.Base(url))
	if _, err := os.Stat(file); err != nil {
		t.Fatalf("fayl saqlanmadi: %v", err)
	}

	if rec := guideVideoReq(t, http.MethodDelete, "2", RoleSuperAdmin, "1", nil); rec.Code != http.StatusOK {
		t.Fatalf("o'chirish status: %d", rec.Code)
	}
	if got := guideURLs(t); got[1] != "" || got[2] != "" {
		t.Fatalf("o'chirilgandan keyin: %v", got)
	}
	if _, err := os.Stat(file); !os.IsNotExist(err) {
		t.Fatalf("eski fayl o'chirilmadi")
	}
}

// Pauza bilan olingan namuna (bir nechta bo'lak) oddiy video kabi bitta
// 500x500 mp4 ga birlashtiriladi.
func TestGuideVideoSegmentsMergedToSquare(t *testing.T) {
	ffmpeg, err := exec.LookPath("ffmpeg")
	if err != nil {
		t.Skip("ffmpeg yo'q")
	}
	wd, _ := os.Getwd()
	os.Chdir(t.TempDir())
	t.Cleanup(func() { os.Chdir(wd) })
	initDB()
	createTemplate(t, `{"task":"Pol yuvish","type":1,"filialIds":[1],"category":""}`)

	var body bytes.Buffer
	mw := multipart.NewWriter(&body)
	mw.WriteField("segment_count", "2")
	for i := 0; i < 2; i++ {
		src := fmt.Sprintf("seg%d.mp4", i)
		// Telefondagidek tik video
		out, err := exec.Command(ffmpeg, "-f", "lavfi", "-i", "testsrc=size=720x1280:rate=30:duration=1",
			"-c:v", "libx264", "-pix_fmt", "yuv420p", "-y", src).CombinedOutput()
		if err != nil {
			t.Fatalf("test video: %v %s", err, out)
		}
		data, _ := os.ReadFile(src)
		fw, _ := mw.CreateFormFile(fmt.Sprintf("video_%d", i), fmt.Sprintf("segment_%d.mp4", i))
		fw.Write(data)
	}
	mw.Close()
	req := httptest.NewRequest(http.MethodPost, "/api/templates/1/guide-video", &body)
	req.Header.Set("Content-Type", mw.FormDataContentType())
	req.Header.Set("Role", RoleSuperAdmin)
	req.Header.Set("UserID", "1")
	req = mux.SetURLVars(req, map[string]string{"id": "1"})
	rec := httptest.NewRecorder()
	uploadGuideVideo(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("status: %d (%s)", rec.Code, rec.Body.String())
	}
	var resp struct {
		URL string `json:"guideVideoUrl"`
	}
	json.NewDecoder(rec.Body).Decode(&resp)
	file := filepath.Join(guideVideoDir, filepath.Base(resp.URL))
	probe, err := exec.Command(filepath.Join(filepath.Dir(ffmpeg), "ffprobe"), "-v", "error", "-select_streams", "v:0",
		"-show_entries", "stream=width,height:format=duration", "-of", "csv=p=0", file).Output()
	if err != nil {
		t.Fatalf("ffprobe: %v", err)
	}
	got := strings.Fields(strings.ReplaceAll(string(probe), ",", " "))
	if len(got) < 3 || got[0] != "500" || got[1] != "500" {
		t.Fatalf("o'lcham: %q, kutilgan 500x500", probe)
	}
	if d, _ := strconv.ParseFloat(got[2], 64); d < 1.8 {
		t.Fatalf("davomiylik %v s - bo'laklar birlashmagan", d)
	}
	if entries, _ := os.ReadDir(guideVideoDir); len(entries) != 1 {
		t.Fatalf("vaqtinchalik fayllar qolgan: %v", entries)
	}
}
