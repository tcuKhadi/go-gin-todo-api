// Entry point
package main

import (
	"log"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/tcuKhadi/go-gin-todo-api/internal/config"
	"github.com/tcuKhadi/go-gin-todo-api/internal/database"
	"github.com/tcuKhadi/go-gin-todo-api/internal/handlers"
)

// Runs the server
func main() {
	var cfg *config.Config
	var err error
	cfg, err = config.Load()

	if err != nil {
		log.Fatal("Failed to load configuration", err)
	}

	var pool *pgxpool.Pool
	pool, err = database.Connect(cfg.DatabaseUrl)

	if err != nil {
		log.Fatal("Failed to connect to database:", err)
	}

	defer pool.Close()

	var router *gin.Engine = gin.Default()
	router.SetTrustedProxies(nil)
	router.GET("/", func(c *gin.Context) {
		// map[string]interface
		// map[string]any{}
		c.JSON(200, gin.H{
			"message": "Todo API is running well!",
			"status":  "success",
			"database": "connected",
		})
	})

	router.POST("/todos", handlers.CreateToDoHandler(pool))
	router.GET("/todos", handlers.GetAllTodoshandler(pool))
	router.GET("/todos/:id", handlers.GetToDoByIDHandler(pool))
	router.PUT("/todos/:id", handlers.UpdateToDoHandler(pool))
	router.DELETE("/todos/:id", handlers.DeleteToDohandler(pool))


	router.Run(":" + cfg.Port)
}
