package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
)

// filialNames — GET /api/filials javobidagi filial nomlari (tartib bilan).
func filialNames(t *testing.T) []string {
	t.Helper()
	req := httptest.NewRequest(http.MethodGet, "/api/filials", nil)
	req.Header.Set("Role", RoleSuperAdmin)
	rec := httptest.NewRecorder()
	getFilials(rec, req)

	var resp struct {
		Data []Filial `json:"data"`
	}
	if err := json.NewDecoder(rec.Body).Decode(&resp); err != nil {
		t.Fatalf("javob o'qilmadi: %v", err)
	}
	names := make([]string, len(resp.Data))
	for i, f := range resp.Data {
		names[i] = f.Name
	}
	return names
}

func TestReorderFilials(t *testing.T) {
	wd, _ := os.Getwd()
	os.Chdir(t.TempDir())
	t.Cleanup(func() { os.Chdir(wd) })
	initDB()

	// Boshlang'ich tartib — qo'shilish tartibi
	if got := strings.Join(filialNames(t), ","); got != "Gelion,Sibirski,Fresco,Marxabo,Marojni" {
		t.Fatalf("boshlang'ich tartib: %s", got)
	}

	body := `{"filialIds": [2, 1, 3, 5, 4]}`
	req := httptest.NewRequest(http.MethodPut, "/api/filials/reorder", strings.NewReader(body))
	req.Header.Set("Role", RoleSuperAdmin)
	rec := httptest.NewRecorder()
	reorderFilials(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("reorder status: %d", rec.Code)
	}
	if got := strings.Join(filialNames(t), ","); got != "Sibirski,Gelion,Fresco,Marojni,Marxabo" {
		t.Fatalf("yangi tartib: %s", got)
	}

	// Yangi filial oxiriga tushadi
	req = httptest.NewRequest(http.MethodPost, "/api/filials", strings.NewReader(`{"name": "Yangi"}`))
	req.Header.Set("Role", RoleSuperAdmin)
	createFilial(httptest.NewRecorder(), req)
	names := filialNames(t)
	if names[len(names)-1] != "Yangi" {
		t.Fatalf("yangi filial oxirida emas: %v", names)
	}

	// Faqat super_admin o'zgartira oladi
	req = httptest.NewRequest(http.MethodPut, "/api/filials/reorder", strings.NewReader(body))
	req.Header.Set("Role", "admin")
	rec = httptest.NewRecorder()
	reorderFilials(rec, req)
	if rec.Code != http.StatusForbidden {
		t.Fatalf("admin uchun status: %d", rec.Code)
	}
}
