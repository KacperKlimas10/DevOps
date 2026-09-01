package main

import (
	"github.com/gin-gonic/gin"
)

func main() {

	r := gin.Default()

	r.GET("/api/demo-go", func(c *gin.Context) {
		c.String(200, "2 września 2026 - Projekt Kacper Klimas - Symulacja udanego wdrożenia :)")
	})

	r.Run(":8080")
}