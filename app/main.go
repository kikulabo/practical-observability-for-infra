package main

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"html/template"
	"log"
	"net/http"
	"os"
	"strconv"
	"time"

	_ "github.com/go-sql-driver/mysql"
)

type Todo struct {
	ID        int64     `json:"id"`
	Title     string    `json:"title"`
	Done      bool      `json:"done"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

var db *sql.DB

var tmpl = template.Must(template.New("index").Parse(`
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>ToDoApp</title>
  <style>
    body { font-family: sans-serif; max-width: 600px; margin: 40px auto; padding: 0 16px; }
    li { margin: 8px 0; }
    .done { text-decoration: line-through; color: #999; }
  </style>
</head>
<body>
  <h1>ToDo リスト</h1>

  <form method="POST" action="/todos">
    <input name="title" placeholder="新しいタスク" required style="width:300px">
    <button type="submit">追加</button>
  </form>

  <ul>
    {{range .}}
    <li>
      <form method="POST" action="/todos/{{.ID}}/toggle" style="display:inline">
        <button type="submit">{{if .Done}}✅{{else}}⬜{{end}}</button>
      </form>
      <span class="{{if .Done}}done{{end}}">{{.Title}}</span>
      <form method="POST" action="/todos/{{.ID}}/delete" style="display:inline">
        <button type="submit">🗑</button>
      </form>
    </li>
    {{end}}
  </ul>
</body>
</html>
`))

func main() {
	dsn := os.Getenv("MYSQL_DSN")
	if dsn == "" {
		log.Fatal("MYSQL_DSN is not set")
	}

	var err error
	db, err = sql.Open("mysql", dsn+"?parseTime=true")
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()

	db.SetMaxOpenConns(25)
	db.SetMaxIdleConns(10)
	db.SetConnMaxLifetime(5 * time.Minute)

	mux := http.NewServeMux()
	mux.HandleFunc("/", handleIndex)
	mux.HandleFunc("/todos", handleTodos)
	mux.HandleFunc("/todos/", handleTodoDetail)
	mux.HandleFunc("/health", handleHealth)

	log.Println("Starting server on :8080")
	log.Fatal(http.ListenAndServe(":8080", mux))
}

// GET / - トップページ（HTML）
func handleIndex(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/" {
		http.NotFound(w, r)
		return
	}
	rows, err := db.Query("SELECT id, title, done, created_at, updated_at FROM todos ORDER BY created_at DESC")
	if err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
	defer rows.Close()

	var todos []Todo
	for rows.Next() {
		var t Todo
		if err := rows.Scan(&t.ID, &t.Title, &t.Done, &t.CreatedAt, &t.UpdatedAt); err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
		todos = append(todos, t)
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	tmpl.Execute(w, todos)
}

// GET /todos - ToDo 一覧（JSON）, POST /todos - ToDo 作成
func handleTodos(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		rows, err := db.Query("SELECT id, title, done, created_at, updated_at FROM todos ORDER BY created_at DESC")
		if err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
		defer rows.Close()

		var todos []Todo
		for rows.Next() {
			var t Todo
			if err := rows.Scan(&t.ID, &t.Title, &t.Done, &t.CreatedAt, &t.UpdatedAt); err != nil {
				http.Error(w, err.Error(), 500)
				return
			}
			todos = append(todos, t)
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(todos)

	case http.MethodPost:
		title := r.FormValue("title")
		if title == "" {
			http.Error(w, "title is required", 400)
			return
		}
		_, err := db.Exec("INSERT INTO todos (title) VALUES (?)", title)
		if err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
		http.Redirect(w, r, "/", http.StatusSeeOther)

	default:
		http.Error(w, "Method not allowed", 405)
	}
}

// POST /todos/{id}/toggle - 完了・未完了の切り替え
// POST /todos/{id}/delete - 削除
// PATCH /todos/{id}       - 完了・未完了の切り替え（API）
// DELETE /todos/{id}      - 削除（API）
func handleTodoDetail(w http.ResponseWriter, r *http.Request) {
	path := r.URL.Path[len("/todos/"):]

	// フォームからの操作（/todos/{id}/toggle, /todos/{id}/delete）
	if r.Method == http.MethodPost {
		parts := splitLast(path, "/")
		if len(parts) == 2 {
			id, err := strconv.ParseInt(parts[0], 10, 64)
			if err != nil {
				http.Error(w, "invalid todo id", 400)
				return
			}
			switch parts[1] {
			case "toggle":
				db.Exec("UPDATE todos SET done = NOT done WHERE id = ?", id)
			case "delete":
				db.Exec("DELETE FROM todos WHERE id = ?", id)
			}
			http.Redirect(w, r, "/", http.StatusSeeOther)
			return
		}
	}

	// API 操作（PATCH / DELETE）
	id, err := strconv.ParseInt(path, 10, 64)
	if err != nil {
		http.Error(w, "invalid todo id", 400)
		return
	}
	switch r.Method {
	case http.MethodPatch:
		db.Exec("UPDATE todos SET done = NOT done WHERE id = ?", id)
		w.WriteHeader(http.StatusOK)
		fmt.Fprint(w, "toggled")
	case http.MethodDelete:
		db.Exec("DELETE FROM todos WHERE id = ?", id)
		w.WriteHeader(http.StatusOK)
		fmt.Fprint(w, "deleted")
	default:
		http.Error(w, "Method not allowed", 405)
	}
}

// パスを末尾のセパレータで2分割するヘルパー
func splitLast(s, sep string) []string {
	for i := len(s) - 1; i >= 0; i-- {
		if string(s[i]) == sep {
			return []string{s[:i], s[i+1:]}
		}
	}
	return []string{s}
}

// GET /health - ヘルスチェック
func handleHealth(w http.ResponseWriter, r *http.Request) {
	if err := db.Ping(); err != nil {
		http.Error(w, "db connection failed", 503)
		return
	}
	w.WriteHeader(http.StatusOK)
	fmt.Fprint(w, "OK")
}
