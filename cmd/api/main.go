package main

import (
	"log"
	"os"

	"github.com/gin-gonic/gin"
	"github.com/tcuKhadi/go-gin-todo-api/internal/config"
	"github.com/tcuKhadi/go-gin-todo-api/internal/database"
	"github.com/tcuKhadi/go-gin-todo-api/internal/events"
	"github.com/tcuKhadi/go-gin-todo-api/internal/handlers"
	"github.com/tcuKhadi/go-gin-todo-api/internal/middleware"
)

func main() {
	cfg, err := config.Load()
	if err != nil {
		log.Fatal("Failed to load configuration: ", err)
	}

	pool, err := database.Connect(cfg.DatabaseUrl)
	if err != nil {
		log.Fatal("Failed to connect to database: ", err)
	}
	defer pool.Close()

	// Kafka Producer Initialization
	kafkaBrokers := os.Getenv("KAFKA_BROKERS")
	if kafkaBrokers == "" {
		kafkaBrokers = "localhost:9092"
	}
	kafkaTopic := os.Getenv("KAFKA_TOPIC")
	if kafkaTopic == "" {
		kafkaTopic = "todo-events"
	}

	producer := events.NewProducer(kafkaBrokers, kafkaTopic)
	defer func() {
		if err := producer.Close(); err != nil {
			log.Printf("Failed to close Kafka producer: %v", err)
		}
	}()

	router := gin.Default()
	router.SetTrustedProxies(nil)

	router.GET("/", func(c *gin.Context) {
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
		protected.POST("", handlers.CreateToDoHandler(pool, producer))
		protected.GET("", handlers.GetAllTodoshandler(pool))
		protected.GET("/:id", handlers.GetToDoByIDHandler(pool))
		protected.PUT("/:id", handlers.UpdateToDoHandler(pool))
		protected.DELETE("/:id", handlers.DeleteToDohandler(pool))
	}

	router.GET("/protected-test", middleware.AuthMiddleware(cfg), handlers.TestProtectedHandler())

	router.Run(":" + cfg.Port)
}
