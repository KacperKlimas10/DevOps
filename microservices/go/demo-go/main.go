package main

import (
	"github.com/gin-gonic/gin"
)

func main() {

	r := gin.Default()

	r.GET("/api/demo-go", func(c *gin.Context) {
		c.String(200, "Hello from demo-go version after CI/CD finish :)")
	})

	r.Run(":8080")
}