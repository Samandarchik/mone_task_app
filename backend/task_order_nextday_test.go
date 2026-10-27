package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"
)

// Ishchi bugun tartiblagan vazifalar ertaga (yangi kunlik vazifalar
// yaratilganda) ham aynan shu tartibda chiqadi.
func TestWorkerOrderKeptNextDay(t *testing.T) {
	wd, _ := os.Getwd()
	os.Chdir(t.TempDir())
	t.Cleanup(func() { os.Chdir(wd) })
	initDB()

	mainDB, _ := getMainDB()
	res, _ := mainDB.Exec("INSERT INTO users (username, login, password_hash, role, filial_ids, categories) VALUES ('W', 'w', 'x', ?, '1', '[\"X\"]')", RoleWorker)
	workerID, _ := res.LastInsertId()
	mainDB.Close()

	createTemplate(t, `{"task":"A","type":1,"filialIds":[1],"category":"X"}`)
	createTemplate(t, `{"task":"B","type":1,"filialIds":[1],"category":"X"}`)
	createTemplate(t, `{"task":"C","type":1,"filialIds":[1],"category":"X"}`)

	// Ishchi bugun o'zi tartibladi
	saveFilialOrderReq(t, int(workerID), RoleWorker, 1, "2,3,1")

	order := func(date time.Time) string {
		t.Helper()
		req := httptest.NewRequest(http.MethodGet, "/api/tasks?date="+date.Format("2006-01-02"), nil)
		req.Header.Set("Role", RoleWorker)
		req.Header.Set("UserID", fmt.Sprint(workerID))
		rec := httptest.NewRecorder()
		getTasks(rec, req)
		var resp struct {
			Data []Task `json:"data"`
		}
		json.NewDecoder(rec.Body).Decode(&resp)
		ids := []string{}
		for _, task := range resp.Data {
			ids = append(ids, fmt.Sprint(task.TemplateID))
		}
		return strings.Join(ids, ",")
	}
	if got := order(time.Now()); got != "2,3,1" {
		t.Fatalf("bugun: %s, kutilgan 2,3,1", got)
	}

	// Ertangi kun: vazifalar shablonlardan yangidan yaratiladi
	tomorrow := time.Now().AddDate(0, 0, 1)
	for _, id := range []int{1, 2, 3} {
		createTasksForDate(id, string(rune('A'+id-1)), TypeDaily, []int{1}, nil, "X", "", tomorrow)
	}
	if got := order(tomorrow); got != "2,3,1" {
		t.Fatalf("ertaga: %s, kutilgan 2,3,1 (ishchi tartibi saqlanishi kerak)", got)
	}
}
