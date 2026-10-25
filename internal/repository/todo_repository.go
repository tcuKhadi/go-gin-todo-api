package repository

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/tcuKhadi/go-gin-todo-api/internal/models"
)

func CreateTodo(pool *pgxpool.Pool title string, completed bool) (*models.Todo, error) {
	var ctx context.Context
	var cancel context.CancelFunc
	ctx, cancel = context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	var query string = `
			INSERT INTO todos (title, completed)
			VALUES ($1, $2)
			RETURNING id, title, completed, created_at, updated_at
	`
	var todo models.Todo

	var err error = pool.QueryRow(ctx, query, title, completed).Scan(
		&todo.ID,
		&todo.Title,
		&todo.Completed,
		&todo.CreatedAt,
		&todo.UpdateAt,
	)
	if err != nil {
		return nil, err
	}
	return &todo, nil
}