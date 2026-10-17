package main

import (
	"database/sql"
	"path/filepath"
	"testing"

	_ "github.com/mattn/go-sqlite3"
)

// setupUsersDB — users jadvalining test nusxasi (sinxronizatsiya uchun
// kerakli ustunlar bilan).
func setupUsersDB(t *testing.T) *sql.DB {
	t.Helper()

	db, err := sql.Open("sqlite3", filepath.Join(t.TempDir(), "test.db"))
	if err != nil {
		t.Fatalf("test DB ochilmadi: %v", err)
	}
	t.Cleanup(func() { db.Close() })

	_, err = db.Exec(`CREATE TABLE users (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		username TEXT NOT NULL,
		login TEXT UNIQUE NOT NULL,
		password_hash TEXT NOT NULL DEFAULT '',
		role TEXT NOT NULL DEFAULT 'worker',
		filial_ids TEXT,
		categories TEXT,
		phone_number TEXT,
		person_id INTEGER NOT NULL DEFAULT 0,
		person_version INTEGER NOT NULL DEFAULT 0,
		photo_url TEXT NOT NULL DEFAULT '',
		telegram_id INTEGER NOT NULL DEFAULT 0
	)`)
	if err != nil {
		t.Fatalf("jadval yaratilmadi: %v", err)
	}
	return db
}

func addUser(t *testing.T, db *sql.DB, login string, personID int64) int64 {
	t.Helper()
	res, err := db.Exec(`INSERT INTO users
		(username, login, role, filial_ids, categories, phone_number, person_id)
		VALUES ('Eski Ism', ?, 'admin', '[1,2]', '[5]', '998900000000', ?)`,
		login, personID)
	if err != nil {
		t.Fatalf("user qo'shilmadi: %v", err)
	}
	id, _ := res.LastInsertId()
	return id
}

type userRow struct {
	username, phone, photo, role, filials string
	tgID, version                         int64
}

func readUser(t *testing.T, db *sql.DB, id int64) userRow {
	t.Helper()
	var u userRow
	err := db.QueryRow(`SELECT username, COALESCE(phone_number,''), photo_url, role,
		COALESCE(filial_ids,''), telegram_id, person_version FROM users WHERE id = ?`, id).
		Scan(&u.username, &u.phone, &u.photo, &u.role, &u.filials, &u.tgID, &u.version)
	if err != nil {
		t.Fatalf("user o'qilmadi: %v", err)
	}
	return u
}

// Asosiy holat: HR'dan kelgan o'zgarish nusxa maydonlarga yozilishi kerak.
func TestApplyPersonUpdatesThinFields(t *testing.T) {
	db := setupUsersDB(t)
	uid := addUser(t, db, "u1", 100)

	found, err := applyPerson(db, personThin{
		PersonID: 100,
		FIO:      "Aliyev Ali",
		Telefon:  "998901112233",
		RasmURL:  "https://hr.monebakeryuz.uz/uploads/a.jpg",
		TgUserID: 555,
		Version:  10,
	})
	if err != nil || !found {
		t.Fatalf("qo'llanmadi: found=%v err=%v", found, err)
	}

	u := readUser(t, db, uid)
	if u.username != "Aliyev Ali" {
		t.Errorf("ism yangilanmadi: %q", u.username)
	}
	if u.phone != "998901112233" {
		t.Errorf("telefon yangilanmadi: %q", u.phone)
	}
	if u.photo != "https://hr.monebakeryuz.uz/uploads/a.jpg" {
		t.Errorf("rasm yangilanmadi: %q", u.photo)
	}
	if u.tgID != 555 {
		t.Errorf("telegram_id yangilanmadi: %d", u.tgID)
	}
	if u.version != 10 {
		t.Errorf("versiya saqlanmadi: %d", u.version)
	}
}

// Eng muhim kafolat: HR bu ilovaning biznes maydonlariga (rol, filial,
// kategoriya) HECH QACHON tegmasligi kerak.
func TestApplyPersonNeverTouchesLocalFields(t *testing.T) {
	db := setupUsersDB(t)
	uid := addUser(t, db, "u1", 100)

	applyPerson(db, personThin{
		PersonID: 100, FIO: "Yangi Ism", Telefon: "998901112233", Version: 10,
	})

	u := readUser(t, db, uid)
	if u.role != "admin" {
		t.Errorf("HR rolni o'zgartirib yubordi: %q", u.role)
	}
	if u.filials != "[1,2]" {
		t.Errorf("HR filial_ids ni o'zgartirib yubordi: %q", u.filials)
	}
}

// Webhook'lar tartibsiz kelishi mumkin. Eski versiya kelsa rad etilmasa,
// eski ism yangisini bosib ketardi.
func TestApplyPersonRejectsOlderVersion(t *testing.T) {
	db := setupUsersDB(t)
	uid := addUser(t, db, "u1", 100)

	applyPerson(db, personThin{PersonID: 100, FIO: "Yangi", Version: 20})
	applyPerson(db, personThin{PersonID: 100, FIO: "Eski", Version: 10})

	u := readUser(t, db, uid)
	if u.username != "Yangi" {
		t.Fatalf("eski versiya yangisini bosib ketdi: %q", u.username)
	}
	if u.version != 20 {
		t.Fatalf("versiya orqaga ketdi: %d", u.version)
	}
}

// Bir xil webhook ikki marta kelishi mumkin (at-least-once). Ikkinchisi
// hech narsani buzmasligi kerak.
func TestApplyPersonIsIdempotent(t *testing.T) {
	db := setupUsersDB(t)
	uid := addUser(t, db, "u1", 100)

	p := personThin{PersonID: 100, FIO: "Aliyev Ali", Telefon: "998901112233", Version: 10}
	applyPerson(db, p)
	first := readUser(t, db, uid)
	applyPerson(db, p)
	second := readUser(t, db, uid)

	if first != second {
		t.Fatalf("takroriy webhook holatni o'zgartirdi:\n%+v\n%+v", first, second)
	}
}

// Bu odam bu ilovada yo'q — xato emas, shunchaki found=false.
func TestApplyPersonUnknownPersonIsNotError(t *testing.T) {
	db := setupUsersDB(t)
	addUser(t, db, "u1", 100)

	found, err := applyPerson(db, personThin{PersonID: 999, FIO: "Hech kim", Version: 10})
	if err != nil {
		t.Fatalf("noma'lum shaxs xato qaytardi: %v", err)
	}
	if found {
		t.Fatal("yo'q odam uchun found=true qaytdi")
	}
}

// HR'da rezume o'chirilsa, foydalanuvchi O'CHIRILMAYDI (uning vazifalari va
// tarixi shu yerda qoladi) — faqat bog'lanish uziladi.
func TestApplyPersonDeletedUnlinksButKeepsUser(t *testing.T) {
	db := setupUsersDB(t)
	uid := addUser(t, db, "u1", 100)
	applyPerson(db, personThin{PersonID: 100, FIO: "Aliyev Ali", Version: 10})

	found, err := applyPerson(db, personThin{PersonID: 100, Deleted: true, Version: 20})
	if err != nil || !found {
		t.Fatalf("o'chirish qo'llanmadi: found=%v err=%v", found, err)
	}

	var count int
	db.QueryRow("SELECT count(*) FROM users WHERE id = ?", uid).Scan(&count)
	if count != 1 {
		t.Fatal("foydalanuvchi o'chirib yuborildi — tarix yo'qoladi")
	}

	var personID int64
	db.QueryRow("SELECT person_id FROM users WHERE id = ?", uid).Scan(&personID)
	if personID != 0 {
		t.Fatalf("bog'lanish uzilmadi: person_id=%d", personID)
	}

	u := readUser(t, db, uid)
	if u.username != "Aliyev Ali" {
		t.Errorf("o'chirishda ism ham yo'qoldi: %q", u.username)
	}
}

// HR'dan bo'sh ism/telefon kelsa, mavjud qiymat o'chib ketmasligi kerak.
func TestApplyPersonEmptyFieldsDoNotWipe(t *testing.T) {
	db := setupUsersDB(t)
	uid := addUser(t, db, "u1", 100)
	applyPerson(db, personThin{PersonID: 100, FIO: "Aliyev Ali", Telefon: "998901112233", Version: 10})

	applyPerson(db, personThin{PersonID: 100, FIO: "", Telefon: "", Version: 20})

	u := readUser(t, db, uid)
	if u.username != "Aliyev Ali" {
		t.Errorf("bo'sh ism mavjudini o'chirdi: %q", u.username)
	}
	if u.phone != "998901112233" {
		t.Errorf("bo'sh telefon mavjudini o'chirdi: %q", u.phone)
	}
}

// person_id = 0 (bog'lanmagan) userlar sinxronizatsiyaga tushib qolmasligi
// kerak — aks holda bitta o'zgarish barcha bog'lanmaganlarga yozilardi.
func TestApplyPersonIgnoresZeroPersonID(t *testing.T) {
	db := setupUsersDB(t)
	uid := addUser(t, db, "u1", 0)

	found, err := applyPerson(db, personThin{PersonID: 0, FIO: "Hech kim", Version: 10})
	if err == nil && found {
		t.Fatal("person_id=0 bo'lgan user yangilanib ketdi")
	}

	u := readUser(t, db, uid)
	if u.username != "Eski Ism" {
		t.Fatalf("bog'lanmagan user o'zgardi: %q", u.username)
	}
}
