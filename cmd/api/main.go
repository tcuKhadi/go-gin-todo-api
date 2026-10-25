// Entry point
package main

import (
	"log"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/tcuKhadi/go-gin-todo-api/internal/config"
	"github.com/tcuKhadi/go-gin-todo-api/internal/database"
	"github.com/tcuKhadi/go-gin-todo-api/internal/handlers"
	"github.com/tcuKhadi/go-gin-todo-api/internal/middleware"
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
			"message":  "Todo API is running well!",
			"status":   "success",
			"database": "connected",
		})
	})

	router.POST("/auth/register", handlers.CreateUserHandler(pool))
	router.POST("/auth/login", handlers.LoginHandler(pool, cfg))

	protected := router.Group("/todos")
	protected.Use(middleware.AuthMiddleware(cfg))
	{
		protected.POST("", handlers.CreateToDoHandler(pool))
		protected.GET("", handlers.GetAllTodoshandler(pool))
		protected.GET("/:id", handlers.GetToDoByIDHandler(pool))
		protected.PUT("/:id", handlers.UpdateToDoHandler(pool))
		protected.DELETE("/:id", handlers.DeleteToDohandler(pool))
	}

	// Middleware Test Route
	router.GET("/protected-test", middleware.AuthMiddleware(cfg), handlers.TestProtectedHandler())

	router.Run(":" + cfg.Port)
}
