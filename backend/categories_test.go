package main

import "testing"

// Nom o'zgarsa userlardagi JSON ham yangilanadi; "Admin" "Admin 2" ga tegmaydi.
func TestRenameUserCategory(t *testing.T) {
	db := setupUsersDB(t)
	db.Exec(`INSERT INTO users (username, login, role, categories) VALUES
		('a', 'a', 'worker', '["Admin","Bar"]'),
		('b', 'b', 'worker', '["Admin 2"]')`)

	if n := countUsersWithCategory(db, "Admin"); n != 1 {
		t.Fatalf("1 ta user kutilgan, olindi %d", n)
	}

	tx, _ := db.Begin()
	n, err := replaceUserCategory(tx, "Admin", "Bosh admin")
	if err != nil || n != 1 {
		t.Fatalf("1 ta o'zgarish kutilgan, olindi %d (%v)", n, err)
	}
	tx.Commit()

	var a, b string
	db.QueryRow("SELECT categories FROM users WHERE login = 'a'").Scan(&a)
	db.QueryRow("SELECT categories FROM users WHERE login = 'b'").Scan(&b)
	if a != `["Bosh admin","Bar"]` || b != `["Admin 2"]` {
		t.Fatalf("noto'g'ri natija: a=%s b=%s", a, b)
	}
}

// O'chirilganda nom userlardan olib tashlanadi; "Admin 2" ga tegmaydi.
func TestRemoveUserCategory(t *testing.T) {
	db := setupUsersDB(t)
	db.Exec(`INSERT INTO users (username, login, role, categories) VALUES
		('a', 'a', 'worker', '["Admin","Bar"]'),
		('b', 'b', 'worker', '["Admin 2"]')`)

	tx, _ := db.Begin()
	if n, err := replaceUserCategory(tx, "Admin", ""); err != nil || n != 1 {
		t.Fatalf("1 ta o'zgarish kutilgan, olindi %d (%v)", n, err)
	}
	tx.Commit()

	var a, b string
	db.QueryRow("SELECT categories FROM users WHERE login = 'a'").Scan(&a)
	db.QueryRow("SELECT categories FROM users WHERE login = 'b'").Scan(&b)
	if a != `["Bar"]` || b != `["Admin 2"]` {
		t.Fatalf("noto'g'ri natija: a=%s b=%s", a, b)
	}
}
