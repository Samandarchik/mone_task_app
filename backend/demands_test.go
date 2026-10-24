package main

import (
	"testing"
)

// Mas'ullar: filial + kategoriya bo'yicha workerlar va ular shablonni
// biriktirgan sotrudniklar; boshqa filial/kategoriya va begona sotrudnik — yo'q.
func TestTaskResponsibles(t *testing.T) {
	db := setupUsersDB(t)
	migrateEmployees(db)

	add := func(name, role, filials, categories string) int {
		res, err := db.Exec(`INSERT INTO users (username, login, role, filial_ids, categories)
			VALUES (?, ?, ?, ?, ?)`, name, name, role, filials, categories)
		if err != nil {
			t.Fatalf("user qo'shilmadi: %v", err)
		}
		id, _ := res.LastInsertId()
		return int(id)
	}
	ali := add("Ali", RoleWorker, "1,2", `["Kassa","Oshxona"]`)
	add("Vali", RoleWorker, "2", `["Kassa"]`)     // boshqa filial
	add("Gani", RoleWorker, "1", `["Oshxona"]`)   // boshqa kategoriya
	add("Checker", RoleChecker, "1", `["Kassa"]`) // worker emas
	emp := add("Sotrudnik", RoleEmployee, "", "") // Ali'ning sotrudnigi
	other := add("Begona", RoleEmployee, "", "")  // boshqa shablonga biriktirilgan
	db.Exec("INSERT INTO task_delegations (owner_id, employee_id, template_id) VALUES (?, ?, 7)", ali, emp)
	db.Exec("INSERT INTO task_delegations (owner_id, employee_id, template_id) VALUES (?, ?, 8)", ali, other)

	got := map[int]bool{}
	for _, p := range taskResponsibles(db, 1, 7, "Kassa") {
		got[p.UserID] = true
	}
	if len(got) != 2 || !got[ali] || !got[emp] {
		t.Fatalf("kutilgan Ali + Sotrudnik, olindi: %v", got)
	}

	if r := taskResponsibles(db, 3, 7, "Kassa"); len(r) != 0 {
		t.Fatalf("filialda hech kim yo'q bo'lishi kerak, olindi: %v", r)
	}
}

// Kategoriya tanlanmagan worker — kategoriyasiz vazifa uchun ham mas'ul emas;
// kategoriya nomi aniq mos kelishi kerak ("Admin" ≠ "Admin 2").
func TestFilialWorkersWithoutCategories(t *testing.T) {
	db := setupUsersDB(t)

	add := func(name, categories string) int {
		res, err := db.Exec(`INSERT INTO users (username, login, role, filial_ids, categories)
			VALUES (?, ?, ?, '1', ?)`, name, name, RoleWorker, categories)
		if err != nil {
			t.Fatalf("user qo'shilmadi: %v", err)
		}
		id, _ := res.LastInsertId()
		return int(id)
	}
	add("Bo'sh", "")
	add("Massiv", "[]")
	add("Null", "null")
	admin := add("Admin", `["Admin"]`)
	admin2 := add("Admin2", `["Admin 2"]`)

	got := filialWorkers(db, 1, "")
	if len(got) != 2 || !got[admin] || !got[admin2] {
		t.Fatalf("kategoriyasiz vazifa: faqat kategoriyali xodimlar kutilgan, olindi: %v", got)
	}

	got = filialWorkers(db, 1, "Admin")
	if len(got) != 1 || !got[admin] {
		t.Fatalf("'Admin' — faqat Admin kutilgan, olindi: %v", got)
	}
}
