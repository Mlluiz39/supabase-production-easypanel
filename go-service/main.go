// Supabase Production — Admin Status Panel
// Lightweight Go service that shows the health status of all Supabase services.
// Exposes:
//   GET /         — HTML dashboard
//   GET /api/status — JSON status
//   GET /api/health — Aggregated healthcheck

package main

import (
	"encoding/json"
	"fmt"
	"html/template"
	"net/http"
	"os"
	"os/exec"
	"sort"
	"strings"
	"sync"
	"time"
)

// ─── Types ─────────────────────────────────────────────────

type Service struct {
	Name     string `json:"name"`
	Status   string `json:"status"`   // healthy | degraded | down | unknown
	Uptime   string `json:"uptime"`
	LoggedIn bool   `json:"logged_in"`
	Error    string `json:"error,omitempty"`
}

type SystemInfo struct {
	Uptime      string `json:"uptime"`
	DiskUsed    string `json:"disk_used"`
	DiskTotal   string `json:"disk_total"`
	DiskPercent string `json:"disk_percent"`
	MemUsed     string `json:"mem_used"`
	MemTotal    string `json:"mem_total"`
	MemPercent  string `json:"mem_percent"`
}

type StatusResponse struct {
	Healthy     bool      `json:"healthy"`
	Status      string    `json:"status"` // ok | degraded | critical
	Services    []Service `json:"services"`
	System      SystemInfo `json:"system"`
	LastBackup  string    `json:"last_backup"`
	CheckedAt   string    `json:"checked_at"`
}

// ─── Configuration ─────────────────────────────────────────

var (
	port         = env("ADMIN_PORT", "8080")
	refreshSec   = env("ADMIN_REFRESH_SEC", "30")
	containerNames = []string{
		"supabase-db",
		"supabase-supavisor",
		"supabase-auth",
		"supabase-rest",
		"supabase-realtime",
		"supabase-storage",
		"supabase-imgproxy",
		"supabase-meta",
		"supabase-functions",
		"supabase-kong",
		"supabase-studio",
		"supabase-vector",
	}
)

func env(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

// ─── Helpers ───────────────────────────────────────────────

func runCommand(name string, args ...string) (string, error) {
	cmd := exec.Command(name, args...)
	out, err := cmd.Output()
	return strings.TrimSpace(string(out)), err
}

// ─── Service Health Check ──────────────────────────────────

func checkService(name string) Service {
	s := Service{Name: name}

	// Get container status via Docker inspect
	state, err := runCommand("docker", "inspect",
		"--format={{.State.Status}}|{{.State.Health.Status}}|{{.State.StartedAt}}",
		name,
	)
	if err != nil {
		s.Status = "down"
		s.Error = "container not found"
		return s
	}

	parts := strings.Split(state, "|")
	runState := parts[0]
	health := ""
	if len(parts) > 1 {
		health = parts[1]
	}
	startedAt := ""
	if len(parts) > 2 {
		startedAt = parts[2]
	}

	switch {
	case runState != "running":
		s.Status = "down"
		s.Error = fmt.Sprintf("state: %s", runState)
	case health == "healthy":
		s.Status = "healthy"
	case health == "unhealthy":
		s.Status = "degraded"
		s.Error = "unhealthy"
	case health == "starting":
		s.Status = "degraded"
		s.Error = "starting"
	default:
		s.Status = "unknown"
	}

	// Calculate uptime
	if startedAt != "" && startedAt != "0001-01-01T00:00:00Z" {
		t, err := time.Parse(time.RFC3339Nano, startedAt)
		if err == nil {
			diff := time.Since(t).Round(time.Second)
			if diff < time.Minute {
				s.Uptime = fmt.Sprintf("%ds", int(diff.Seconds()))
			} else if diff < time.Hour {
				s.Uptime = fmt.Sprintf("%dm", int(diff.Minutes()))
			} else if diff < 24*time.Hour {
				s.Uptime = fmt.Sprintf("%dh%dm", int(diff.Hours()), int(diff.Minutes())%60)
			} else {
				s.Uptime = fmt.Sprintf("%dd", int(diff.Hours())/24)
			}
		}
	}

	return s
}

// ─── System Info ───────────────────────────────────────────

func getSystemInfo() SystemInfo {
	info := SystemInfo{Uptime: "N/A", DiskUsed: "N/A", DiskTotal: "N/A", DiskPercent: "N/A"}

	// Uptime
	uptime, err := runCommand("cat", "/proc/uptime")
	if err == nil {
		parts := strings.Fields(uptime)
		if len(parts) > 0 {
			secs, _ := fmt.Sscanf(parts[0], "%f", new(float64))
			if secs == 1 {
				var f float64
				fmt.Sscanf(parts[0], "%f", &f)
				d := time.Duration(f) * time.Second
				days := int(d.Hours()) / 24
				hours := int(d.Hours()) % 24
				if days > 0 {
					info.Uptime = fmt.Sprintf("%dd%dh", days, hours)
				} else {
					info.Uptime = fmt.Sprintf("%dh", hours)
				}
			}
		}
	}

	// Disk usage
	disk, err := runCommand("df", "-B1", "--output=used,size,used%", "/")
	if err == nil {
		lines := strings.Split(disk, "\n")
		if len(lines) >= 2 {
			fields := strings.Fields(lines[1])
			if len(fields) >= 3 {
				used, _ := fmt.Sscanf(fields[0], "%d", new(int64))
				total, _ := fmt.Sscanf(fields[1], "%d", new(int64))
				if used == 1 {
					var u, t int64
					fmt.Sscanf(fields[0], "%d", &u)
					fmt.Sscanf(fields[1], "%d", &t)
					info.DiskUsed = fmt.Sprintf("%.1f GB", float64(u)/1e9)
					info.DiskTotal = fmt.Sprintf("%.1f GB", float64(t)/1e9)
					info.DiskPercent = fields[2]
				}
			}
		}
	}

	return info
}

// ─── Backup Info ───────────────────────────────────────────

func getLastBackup() string {
	// Check the most recent backup file
	out, err := runCommand("bash", "-c",
		"ls -t backups/supabase_*.dump.gz 2>/dev/null | head -1")
	if err != nil || out == "" {
		return "never"
	}

	// Get file modification time
	modTime, err := runCommand("stat", "--format=%Y", out)
	if err != nil {
		return "unknown"
	}

	var ts int64
	fmt.Sscanf(modTime, "%d", &ts)
	elapsed := time.Since(time.Unix(ts, 0)).Round(time.Hour)

	if elapsed < 24*time.Hour {
		return fmt.Sprintf("%.0fh ago", elapsed.Hours())
	}
	return fmt.Sprintf("%.0fd ago", elapsed.Hours()/24)
}

// ─── Status Aggregation ────────────────────────────────────

func getStatus() StatusResponse {
	var wg sync.WaitGroup
	services := make([]Service, len(containerNames))
	serviceCh := make(chan Service, len(containerNames))

	for _, name := range containerNames {
		wg.Add(1)
		go func(n string) {
			defer wg.Done()
			serviceCh <- checkService(n)
		}(name)
	}
	wg.Wait()
	close(serviceCh)

	i := 0
	for s := range serviceCh {
		services[i] = s
		i++
	}
	sort.Slice(services, func(a, b int) bool {
		return services[a].Name < services[b].Name
	})

	// Aggregate status
	hasDown := false
	hasDegraded := false
	for _, s := range services {
		switch s.Status {
		case "down":
			hasDown = true
		case "degraded":
			hasDegraded = true
		}
	}

	overallStatus := "ok"
	healthy := true
	switch {
	case hasDown:
		overallStatus = "critical"
		healthy = false
	case hasDegraded:
		overallStatus = "degraded"
		healthy = true
	}

	return StatusResponse{
		Healthy:    healthy,
		Status:     overallStatus,
		Services:   services,
		System:     getSystemInfo(),
		LastBackup: getLastBackup(),
		CheckedAt:  time.Now().Format(time.RFC3339),
	}
}

// ─── Templates ─────────────────────────────────────────────

var tmpl = template.Must(template.New("dashboard").Parse(`<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<meta name="color-scheme" content="dark light">
<title>Supabase Status</title>
<style>
  :root {
    --bg: #f8f9fa;
    --card-bg: #ffffff;
    --text: #1a1a2e;
    --muted: #6c757d;
    --border: #dee2e6;
    --green: #28a745;
    --yellow: #ffc107;
    --red: #dc3545;
  }
  @media (prefers-color-scheme: dark) {
    :root {
      --bg: #0f0f1a;
      --card-bg: #1a1a2e;
      --text: #e0e0e0;
      --muted: #9ca3af;
      --border: #2d2d44;
      --green: #22c55e;
      --yellow: #eab308;
      --red: #ef4444;
    }
  }
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body {
    font-family: -apple-system, BlinkMacSystemFont, 'SF Mono', 'Segoe UI', system-ui, sans-serif;
    background: var(--bg);
    color: var(--text);
    padding: 20px;
    max-width: 1200px;
    margin: 0 auto;
  }
  h1 { font-size: 1.5rem; margin-bottom: 4px; }
  .subtitle { color: var(--muted); font-size: 0.85rem; margin-bottom: 20px; }
  .overview {
    display: flex; gap: 12px; flex-wrap: wrap; margin-bottom: 24px;
  }
  .badge {
    padding: 6px 16px; border-radius: 20px; font-size: 0.85rem; font-weight: 600;
  }
  .badge.ok { background: var(--green); color: white; }
  .badge.degraded { background: var(--yellow); color: black; }
  .badge.critical { background: var(--red); color: white; }
  .grid {
    display: grid; grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
    gap: 12px; margin-bottom: 24px;
  }
  .card {
    background: var(--card-bg); border: 1px solid var(--border);
    border-radius: 8px; padding: 16px;
    transition: box-shadow 0.2s;
  }
  .card:hover { box-shadow: 0 2px 8px rgba(0,0,0,0.15); }
  .card-header {
    display: flex; justify-content: space-between; align-items: center;
    margin-bottom: 8px;
  }
  .card-name { font-weight: 600; font-size: 0.95rem; }
  .dot {
    width: 10px; height: 10px; border-radius: 50%; display: inline-block;
  }
  .dot.healthy { background: var(--green); }
  .dot.degraded { background: var(--yellow); }
  .dot.down, .dot.critical { background: var(--red); }
  .dot.unknown { background: var(--muted); }
  .card-detail { font-size: 0.8rem; color: var(--muted); }
  .card-error { font-size: 0.8rem; color: var(--red); margin-top: 4px; }
  .system-grid {
    display: grid; grid-template-columns: repeat(auto-fill, minmax(160px, 1fr));
    gap: 12px; margin-bottom: 24px;
  }
  .system-card {
    background: var(--card-bg); border: 1px solid var(--border);
    border-radius: 8px; padding: 12px; text-align: center;
  }
  .system-value { font-size: 1.2rem; font-weight: 700; }
  .system-label { font-size: 0.75rem; color: var(--muted); margin-top: 4px; }
  .footer { font-size: 0.8rem; color: var(--muted); text-align: center; margin-top: 24px; }
</style>
</head>
<body>
<h1>Supabase Status</h1>
<div class="subtitle">Checked {{ .CheckedAt | formatTime }} &middot; Auto-refresh {{ .RefreshSec }}s</div>

<div class="overview">
  <span class="badge {{ .Status }}">{{ .Status | upper }}</span>
  <span class="badge">Backup: {{ .LastBackup }}</span>
  <span class="badge">{{ .HealthyCount }}/{{ .TotalCount }} healthy</span>
</div>

<div class="grid">
{{ range .Services }}
  <div class="card">
    <div class="card-header">
      <span class="card-name">{{ .Name | trimPrefix }}</span>
      <span class="dot {{ .Status }}"></span>
    </div>
    <div class="card-detail">
      Status: <strong>{{ .Status }}</strong>
      {{ if .Uptime }} &middot; Uptime: {{ .Uptime }}{{ end }}
    </div>
    {{ if .Error }}
    <div class="card-error">{{ .Error }}</div>
    {{ end }}
  </div>
{{ end }}
</div>

<h2>System</h2>
<div class="system-grid">
  <div class="system-card">
    <div class="system-value">{{ .System.Uptime }}</div>
    <div class="system-label">Uptime</div>
  </div>
  <div class="system-card">
    <div class="system-value">{{ .System.DiskPercent }}</div>
    <div class="system-label">Disk Usage</div>
  </div>
  <div class="system-card">
    <div class="system-value">{{ .System.DiskUsed }} / {{ .System.DiskTotal }}</div>
    <div class="system-label">Disk Space</div>
  </div>
</div>

<div class="footer">
  <a href="/api/status">JSON</a> &middot;
  <a href="/api/health">Healthcheck</a>
</div>

<script>
  setTimeout(function(){ location.reload(); }, {{ .RefreshMs }});
</script>
</body>
</html>`))

func formatTime(s string) string {
	t, err := time.Parse(time.RFC3339, s)
	if err != nil {
		return s
	}
	return t.Local().Format("15:04:05")
}

// ─── Template Data ─────────────────────────────────────────

type TemplateData struct {
	StatusResponse
	RefreshSec string
	RefreshMs  int
	TotalCount int
	HealthyCount int
}

func trimPrefix(name string) string {
	return strings.TrimPrefix(name, "supabase-")
}

// ─── HTTP Handlers ─────────────────────────────────────────

func healthHandler(w http.ResponseWriter, r *http.Request) {
	status := getStatus()
	w.Header().Set("Content-Type", "application/json")

	if status.Status == "critical" {
		w.WriteHeader(http.StatusServiceUnavailable)
	} else if status.Status == "degraded" {
		w.WriteHeader(http.StatusOK)
	}

	json.NewEncoder(w).Encode(map[string]interface{}{
		"status":    status.Status,
		"healthy":    status.Healthy,
		"checked_at": status.CheckedAt,
	})
}

func statusHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(getStatus())
}

func dashHandler(w http.ResponseWriter, r *http.Request) {
	status := getStatus()

	healthyCount := 0
	for _, s := range status.Services {
		if s.Status == "healthy" {
			healthyCount++
		}
	}

	refresh, _ := fmt.Sscanf(refreshSec, "%d", new(int))
	var refreshMs int
	if refresh == 1 {
		var s int
		fmt.Sscanf(refreshSec, "%d", &s)
		refreshMs = s * 1000
	} else {
		refreshMs = 30000
	}

	data := TemplateData{
		StatusResponse: status,
		RefreshSec:     refreshSec,
		RefreshMs:      refreshMs,
		TotalCount:     len(status.Services),
		HealthyCount:   healthyCount,
	}

	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	tmpl.Execute(w, data)
}

// ─── Main ──────────────────────────────────────────────────

func main() {
	http.HandleFunc("/", dashHandler)
	http.HandleFunc("/api/status", statusHandler)
	http.HandleFunc("/api/health", healthHandler)

	addr := fmt.Sprintf(":%s", port)
	fmt.Printf("Admin panel starting on %s\n", addr)
	if err := http.ListenAndServe(addr, nil); err != nil {
		fmt.Fprintf(os.Stderr, "Server error: %v\n", err)
		os.Exit(1)
	}
}
