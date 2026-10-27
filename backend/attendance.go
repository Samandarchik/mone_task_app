package main

// Davomat — Workly (workly-go) serveridan bugun kim ishga kelganini olib,
// task app foydalanuvchilariga telefon (oxirgi 9 raqam) bo'yicha moslaydi.
// Workly tomoni: GET /api/v1/integration/attendance (X-Integration-Key).

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"sort"
	"strings"
	"time"
)

var worklyURL = func() string {
	if u := os.Getenv("WORKLY_URL"); u != "" {
		return strings.TrimRight(u, "/")
	}
	// Workly shu serverda (:8091) — ichki manzil, nginx orqali emas.
	return "http://127.0.0.1:8091"
}()

// Workly'dagi TASKAPP_INTEGRATION_KEY default'i bilan AYNAN bir xil.
var worklyKey = func() string {
	if k := os.Getenv("WORKLY_INTEGRATION_KEY"); k != "" {
		return k
	}
	return "wk2026-taskapp-attendance-f9f9587809f344fe5859d53835789596"
}()

type worklyAttendance struct {
	EmployeeNo    string `json:"employee_no"`
	Name          string `json:"name"`
	InTS          int64  `json:"in_ts"`
	OutTS         int64  `json:"out_ts"`
	Open          bool   `json:"open"`
	WorkedSeconds int64  `json:"worked_seconds"`
}

type AttendanceItem struct {
	UserID        int    `json:"userId"`
	Username      string `json:"username"`
	Role          string `json:"role"`
	Phone         string `json:"phone"`
	FilialIDs     []int  `json:"filialIds"`
	HasPhone      bool   `json:"hasPhone"`
	Came          bool   `json:"came"`
	InTS          int64  `json:"inTs"`
	OutTS         int64  `json:"outTs"`
	Open          bool   `json:"open"`
	WorkedSeconds int64  `json:"workedSeconds"`
}

func phone9(s string) string {
	d := make([]byte, 0, len(s))
	for i := 0; i < len(s); i++ {
		if s[i] >= '0' && s[i] <= '9' {
			d = append(d, s[i])
		}
	}
	if len(d) > 9 {
		d = d[len(d)-9:]
	}
	return string(d)
}

func fetchWorklyAttendance(date string) ([]worklyAttendance, error) {
	url := worklyURL + "/api/v1/integration/attendance"
	if date != "" {
		url += "?from=" + date + "&to=" + date
	}
	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("X-Integration-Key", worklyKey)
	client := &http.Client{Timeout: 15 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("workly status %d", resp.StatusCode)
	}
	var body struct {
		Items []worklyAttendance `json:"items"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&body); err != nil {
		return nil, err
	}
	return body.Items, nil
}

// GET /api/attendance?date=YYYY-MM-DD — super_admin va checker.
func getAttendance(w http.ResponseWriter, r *http.Request) {
	if role := r.Header.Get("Role"); role != RoleSuperAdmin && role != RoleChecker {
		respondJSON(w, http.StatusForbidden, map[string]interface{}{
			"success": false,
			"error":   "Ruxsat yo'q",
		})
		return
	}
	date := r.URL.Query().Get("date")
	if date != "" {
		if _, err := time.Parse("2006-01-02", date); err != nil {
			date = ""
		}
	}

	records, err := fetchWorklyAttendance(date)
	if err != nil {
		respondJSON(w, http.StatusBadGateway, map[string]interface{}{
			"success": false,
			"error":   "Workly serveridan ma'lumot olinmadi: " + err.Error(),
		})
		return
	}
	byPhone := map[string]worklyAttendance{}
	for _, a := range records {
		k := phone9(a.EmployeeNo)
		if prev, ok := byPhone[k]; ok && prev.InTS != 0 && prev.InTS <= a.InTS {
			continue
		}
		byPhone[k] = a
	}

	db, _ := getMainDB()
	defer db.Close()
	rows, err := db.Query("SELECT id, username, role, filial_ids, phone_number FROM users")
	if err != nil {
		respondJSON(w, http.StatusInternalServerError, map[string]interface{}{
			"success": false,
			"error":   "Server xatosi",
		})
		return
	}
	defer rows.Close()

	items := []AttendanceItem{}
	for rows.Next() {
		var it AttendanceItem
		var filialIDs, phone sql.NullString
		rows.Scan(&it.UserID, &it.Username, &it.Role, &filialIDs, &phone)
		if filialIDs.Valid && filialIDs.String != "" {
			it.FilialIDs = parseFilialIDs(filialIDs.String)
		}
		it.Phone = phone.String
		p9 := phone9(phone.String)
		it.HasPhone = len(p9) == 9
		if it.HasPhone {
			if a, ok := byPhone[p9]; ok {
				it.Came = true
				it.InTS = a.InTS
				it.OutTS = a.OutTS
				it.Open = a.Open
				it.WorkedSeconds = a.WorkedSeconds
			}
		}
		items = append(items, it)
	}

	// Kelganlar oldin (kelish vaqti bo'yicha), keyin kelmaganlar (ism bo'yicha).
	sort.SliceStable(items, func(i, j int) bool {
		a, b := items[i], items[j]
		if a.Came != b.Came {
			return a.Came
		}
		if a.Came && a.InTS != b.InTS {
			return a.InTS < b.InTS
		}
		return strings.ToLower(a.Username) < strings.ToLower(b.Username)
	})

	respondJSON(w, http.StatusOK, map[string]interface{}{
		"success": true,
		"data":    items,
	})
}
