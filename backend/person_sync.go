// person_sync.go — shaxs ma'lumotini HR (hr.monebakeryuz.uz) bilan
// sinxron ushlab turadi.
//
// Qoida: odamning KIMLIGI (F.I.Sh, telefon, rasm, Telegram ID) HR'da
// boshqariladi va bu yerda faqat NUSXA sifatida yotadi. Odamning bu ilovada
// NIMA QILA OLISHI (role, filial_ids, categories) — bu ilovaniki, HR unga
// hech qachon tegmaydi.
//
// Ikkita mexanizm bir-birini to'ldiradi:
//
//	webhook   — HR o'zgarish bo'lishi bilan xabar beradi (tez, ~2 soniya)
//	reconcile — har 15 daqiqada HR'dan o'zgarganlarni tortadi (ishonchli)
//
// Reconcile shunchaki qo'shimcha emas, majburiy: ilova deploy paytida
// o'chgan bo'lsa yoki tarmoq uzilsa, webhook yo'qoladi va hech kim buni
// sezmaydi. Reconcile bo'lgani uchun bunday yo'qotish eng ko'pi bilan 15
// daqiqa yashaydi.
//
// person_version — HR bergan monoton raqam. Eski versiyali xabar kelsa rad
// etiladi: webhook'lar tartibsiz yetib kelishi mumkin va tartibsiz yozuv
// eski ismni qaytarib qo'yardi.
package main

import (
	"crypto/subtle"
	"database/sql"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/gorilla/mux"
)

// ---------------------------------------------------------------------------
// Sozlamalar (env orqali, start_all.sh da beriladi)
// ---------------------------------------------------------------------------

var (
	// hrBaseURL — HR manzili.
	hrBaseURL = envOr("HR_BASE_URL", "https://hr.monebakeryuz.uz")

	// hrSyncKey — HR'ning pull API'siga murojaat qilish kaliti.
	hrSyncKey = strings.TrimSpace(os.Getenv("HR_SYNC_KEY"))

	// inboundSyncKey — HR shu ilovaga webhook yuborishda ishlatadigan kalit.
	// Har bir ilova uchun alohida bo'lishi kerak: bittasi sizib chiqsa
	// qolganlari himoyalangan qoladi.
	inboundSyncKey = strings.TrimSpace(os.Getenv("PERSON_SYNC_KEY"))
)

const (
	reconcileInterval = 15 * time.Minute
	reconcileFirstRun = 20 * time.Second // start'dan keyin biroz kutamiz
)

func envOr(key, def string) string {
	if v := strings.TrimSpace(os.Getenv(key)); v != "" {
		return v
	}
	return def
}

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------

// personThin — HR yuboradigan yupqa shakl. To'liq rezume (tajriba, ma'lumot,
// intervyular) bu yerda YO'Q va saqlanmaydi ham: u kerak bo'lganda
// /api/internal/person/{id} dan jonli olinadi.
type personThin struct {
	PersonID   int64  `json:"person_id"`
	FIO        string `json:"fio"`
	Telefon    string `json:"telefon"`
	RasmURL    string `json:"rasm_url"`
	TgUserID   int64  `json:"tg_user_id"`
	TgUsername string `json:"tg_username"`
	Lavozim    string `json:"lavozim"`
	Status     string `json:"status"`
	Version    int64  `json:"version"`
	Deleted    bool   `json:"deleted"`
}

type personsResponse struct {
	Persons    []personThin `json:"persons"`
	MaxVersion int64        `json:"max_version"`
	HasMore    bool         `json:"has_more"`
}

// ---------------------------------------------------------------------------
// Migratsiya
// ---------------------------------------------------------------------------

// initPersonSync — ustunlarni qo'shadi va reconcile tsiklini boshlaydi.
// main() da initDB() dan keyin chaqiriladi.
func initPersonSync() {
	db, err := getMainDB()
	if err != nil {
		log.Printf("person_sync: DB ochilmadi: %v", err)
		return
	}
	defer db.Close()

	// person_id — HR rezume ID'si, ilovalar orasidagi yagona bog'lovchi.
	// Telefon bo'yicha moslash ishlatilmaydi: telefon o'zgaradi va formatlari
	// har xil bo'ladi, shuning uchun bog'lanish uzilib ketardi.
	db.Exec("ALTER TABLE users ADD COLUMN person_id INTEGER NOT NULL DEFAULT 0")
	db.Exec("ALTER TABLE users ADD COLUMN person_version INTEGER NOT NULL DEFAULT 0")
	db.Exec("ALTER TABLE users ADD COLUMN photo_url TEXT NOT NULL DEFAULT ''")
	db.Exec("ALTER TABLE users ADD COLUMN telegram_id INTEGER NOT NULL DEFAULT 0")

	// Bir person bir nechta userga bog'lanib qolmasligi uchun. person_id = 0
	// (hali bog'lanmagan) qatorlar cheklovga tushmaydi.
	db.Exec(`CREATE UNIQUE INDEX IF NOT EXISTS idx_users_person_id
		ON users(person_id) WHERE person_id > 0`)

	db.Exec(`CREATE TABLE IF NOT EXISTS person_sync_state (
		key   TEXT PRIMARY KEY,
		value INTEGER NOT NULL DEFAULT 0
	)`)

	if inboundSyncKey == "" {
		log.Println("person_sync: PERSON_SYNC_KEY o'rnatilmagan — webhook yopiq")
	}
	if hrSyncKey == "" {
		log.Println("person_sync: HR_SYNC_KEY o'rnatilmagan — reconcile o'chiq")
		return
	}
	go reconcileLoop()
}

// ---------------------------------------------------------------------------
// Lokal yozuv
// ---------------------------------------------------------------------------

// applyPerson — bitta shaxs o'zgarishini lokal bazaga yozadi.
//
// FAQAT nusxa maydonlarga tegadi (username, phone_number, photo_url,
// telegram_id). role, filial_ids, categories, password — bularga hech qachon
// tegilmaydi, ular shu ilovaning o'z ma'lumoti.
//
// Qaytaradi: shu ilovada bunday odam topildimi.
func applyPerson(db *sql.DB, p personThin) (bool, error) {
	if p.PersonID <= 0 {
		return false, fmt.Errorf("person_id bo'sh")
	}

	var userID int64
	var curVersion int64
	err := db.QueryRow(
		"SELECT id, COALESCE(person_version,0) FROM users WHERE person_id = ?",
		p.PersonID,
	).Scan(&userID, &curVersion)
	if err == sql.ErrNoRows {
		// Bu odam bu ilovada yo'q — normal holat, har bir xodim har bir
		// ilovada bo'lishi shart emas. Xato emas.
		return false, nil
	}
	if err != nil {
		return false, err
	}

	// Eski yoki takroriy xabar. Webhook'lar tartibsiz kelishi va ikki marta
	// yetkazilishi mumkin — shu tekshiruv ikkalasini ham hal qiladi.
	if p.Version > 0 && p.Version <= curVersion {
		return true, nil
	}

	if p.Deleted {
		// HR'da rezume o'chirilgan. Foydalanuvchini o'chirmaymiz — uning
		// vazifalari va tarixi bu yerda qoladi. Faqat bog'lanishni uzamiz,
		// shunda keyingi sinxronizatsiyalar uni chalkashtirmaydi.
		_, err = db.Exec(
			"UPDATE users SET person_id = 0, person_version = ? WHERE id = ?",
			p.Version, userID)
		if err == nil {
			log.Printf("person_sync: person %d HR'da o'chirilgan, user %d dan uzildi",
				p.PersonID, userID)
		}
		return true, err
	}

	_, err = db.Exec(`UPDATE users SET
			username     = CASE WHEN ? <> '' THEN ? ELSE username END,
			phone_number = CASE WHEN ? <> '' THEN ? ELSE phone_number END,
			photo_url    = ?,
			telegram_id  = ?,
			person_version = ?
		WHERE id = ?`,
		p.FIO, p.FIO,
		p.Telefon, p.Telefon,
		p.RasmURL,
		p.TgUserID,
		p.Version,
		userID,
	)
	return true, err
}

// ---------------------------------------------------------------------------
// Webhook — HR o'zgarish bo'lishi bilan chaqiradi
// ---------------------------------------------------------------------------

// handlePersonWebhook — POST /internal/hooks/person-updated
//
// 404 qaytarish normal javob: "bu odam bu ilovada yo'q". HR buni xato deb
// hisoblamaydi va qayta urinmaydi.
func handlePersonWebhook(w http.ResponseWriter, r *http.Request) {
	if inboundSyncKey == "" {
		http.Error(w, "sinxronizatsiya o'chiq", http.StatusServiceUnavailable)
		return
	}
	got := r.Header.Get("X-Integration-Key")
	if subtle.ConstantTimeCompare([]byte(got), []byte(inboundSyncKey)) != 1 {
		http.Error(w, "ruxsat yo'q", http.StatusUnauthorized)
		return
	}

	body, err := io.ReadAll(io.LimitReader(r.Body, 1<<20))
	if err != nil {
		http.Error(w, "o'qib bo'lmadi", http.StatusBadRequest)
		return
	}
	var p personThin
	if err := json.Unmarshal(body, &p); err != nil {
		http.Error(w, "JSON xato", http.StatusBadRequest)
		return
	}

	db, err := getMainDB()
	if err != nil {
		http.Error(w, "DB xato", http.StatusInternalServerError)
		return
	}
	defer db.Close()

	found, err := applyPerson(db, p)
	if err != nil {
		log.Printf("person_sync: webhook person %d: %v", p.PersonID, err)
		http.Error(w, "yozib bo'lmadi", http.StatusInternalServerError)
		return
	}
	if !found {
		http.Error(w, "bu ilovada bunday odam yo'q", http.StatusNotFound)
		return
	}
	w.WriteHeader(http.StatusOK)
	w.Write([]byte(`{"ok":true}`))
}

// ---------------------------------------------------------------------------
// Reconcile — zaxira mexanizm
// ---------------------------------------------------------------------------

func loadReconcileCursor(db *sql.DB) int64 {
	var v int64
	db.QueryRow("SELECT value FROM person_sync_state WHERE key = 'cursor'").Scan(&v)
	return v
}

func saveReconcileCursor(db *sql.DB, v int64) {
	db.Exec("INSERT OR REPLACE INTO person_sync_state (key, value) VALUES ('cursor', ?)", v)
}

func reconcileLoop() {
	time.Sleep(reconcileFirstRun)
	for {
		if err := reconcileOnce(); err != nil {
			log.Printf("person_sync: reconcile xato: %v", err)
		}
		time.Sleep(reconcileInterval)
	}
}

// reconcileOnce — cursor'dan keyin o'zgarganlarni HR'dan tortib qo'llaydi.
// has_more bo'lsa sahifalab davom etadi.
func reconcileOnce() error {
	db, err := getMainDB()
	if err != nil {
		return err
	}
	defer db.Close()

	cursor := loadReconcileCursor(db)
	total, applied := 0, 0

	for page := 0; page < 50; page++ {
		resp, err := fetchPersonsUpdatedAfter(cursor)
		if err != nil {
			return err
		}
		if len(resp.Persons) == 0 {
			break
		}
		for _, p := range resp.Persons {
			total++
			found, err := applyPerson(db, p)
			if err != nil {
				log.Printf("person_sync: reconcile person %d: %v", p.PersonID, err)
				continue
			}
			if found {
				applied++
			}
		}
		if resp.MaxVersion > cursor {
			cursor = resp.MaxVersion
			saveReconcileCursor(db, cursor)
		}
		if !resp.HasMore {
			break
		}
	}

	if applied > 0 {
		log.Printf("person_sync: reconcile — %d ta o'zgarishdan %d tasi qo'llandi", total, applied)
	}
	return nil
}

var hrHTTP = &http.Client{Timeout: 20 * time.Second}

func hrGet(path string, out interface{}) error {
	req, err := http.NewRequest(http.MethodGet, hrBaseURL+path, nil)
	if err != nil {
		return err
	}
	req.Header.Set("X-Integration-Key", hrSyncKey)

	resp, err := hrHTTP.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("HR %s → HTTP %d", path, resp.StatusCode)
	}
	return json.NewDecoder(resp.Body).Decode(out)
}

func fetchPersonsUpdatedAfter(after int64) (*personsResponse, error) {
	var out personsResponse
	err := hrGet("/api/internal/persons?updated_after="+strconv.FormatInt(after, 10), &out)
	if err != nil {
		return nil, err
	}
	return &out, nil
}

// fetchPersonFull — to'liq rezume. Profil ekrani ochilganda chaqiriladi;
// natija SAQLANMAYDI, shuning uchun `profile_json` kabi nusxa ustunlar
// kerak emas.
func fetchPersonFull(personID int64) (map[string]interface{}, error) {
	var out map[string]interface{}
	err := hrGet("/api/internal/person/"+strconv.FormatInt(personID, 10), &out)
	if err != nil {
		return nil, err
	}
	return out, nil
}

// handleGetPersonProfile — GET /api/users/{id}/profile
// Foydalanuvchining to'liq HR rezumesini jonli qaytaradi. Mobil ilova HR'ga
// to'g'ridan-to'g'ri murojaat qilmaydi: kalit va HR manzili faqat serverda
// qoladi.
func handleGetPersonProfile(w http.ResponseWriter, r *http.Request) {
	idStr := strings.TrimSpace(mux.Vars(r)["id"])
	userID, err := strconv.ParseInt(idStr, 10, 64)
	if err != nil || userID <= 0 {
		http.Error(w, "noto'g'ri ID", http.StatusBadRequest)
		return
	}

	db, err := getMainDB()
	if err != nil {
		http.Error(w, "DB xato", http.StatusInternalServerError)
		return
	}
	defer db.Close()

	var personID int64
	if err := db.QueryRow("SELECT COALESCE(person_id,0) FROM users WHERE id = ?", userID).
		Scan(&personID); err != nil {
		http.Error(w, "foydalanuvchi topilmadi", http.StatusNotFound)
		return
	}
	if personID == 0 {
		http.Error(w, "bu foydalanuvchi HR rezumesiga bog'lanmagan", http.StatusNotFound)
		return
	}

	profile, err := fetchPersonFull(personID)
	if err != nil {
		// HR javob bermasa ham ilova ishlashda davom etadi: ism/telefon/rasm
		// lokal nusxada bor, faqat to'liq rezume ochilmaydi.
		log.Printf("person_sync: HR profil %d olinmadi: %v", personID, err)
		http.Error(w, "HR hozir javob bermayapti", http.StatusBadGateway)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(profile)
}
