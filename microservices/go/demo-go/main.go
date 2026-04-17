package main

import (
	"fmt"
	"log"
	"net/http"
)

func helloFromGo(w http.ResponseWriter, r *http.Request) {
	fmt.Fprintf(w, "Hello from demo-go :)")
}

func main() {
	http.HandleFunc("/api/demo-go", helloFromGo)
	log.Fatal(http.ListenAndServe(":8080", nil))
}