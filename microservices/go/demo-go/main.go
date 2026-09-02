package main

import (
	"github.com/gin-gonic/gin"
)

func main() {

	r := gin.Default()

	r.GET("/api/demo-go", func(c *gin.Context) {
		c.String(200, "Scenariusz testowy TST-02")
	})
	r.Run(":8080")
}