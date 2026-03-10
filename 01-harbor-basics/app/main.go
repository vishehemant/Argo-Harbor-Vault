package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"time"
)

type HealthResponse struct {
	Status    string `json:"status"`
	Timestamp string `json:"timestamp"`
	Version   string `json:"version"`
	Hostname  string `json:"hostname"`
}

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	version := os.Getenv("APP_VERSION")
	if version == "" {
		version = "1.0.0"
	}

	hostname, _ := os.Hostname()

	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintf(w, "Hello from Harbor + Argo CD + Vault demo app! (v%s)\n", version)
	})

	http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		resp := HealthResponse{
			Status:    "healthy",
			Timestamp: time.Now().UTC().Format(time.RFC3339),
			Version:   version,
			Hostname:  hostname,
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(resp)
	})

	http.HandleFunc("/secret-test", func(w http.ResponseWriter, r *http.Request) {
		dbHost := os.Getenv("DB_HOST")
		if dbHost == "" {
			dbHost = "(not set — inject via Vault!)"
		}
		fmt.Fprintf(w, "DB_HOST = %s\n", dbHost)
		fmt.Fprintln(w, "If this shows a real value, Vault injection is working!")
	})

	log.Printf("Starting server on port %s (version %s)", port, version)
	log.Fatal(http.ListenAndServe(":"+port, nil))
}
