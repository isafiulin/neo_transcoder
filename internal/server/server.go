package server

import (
	"context"
	"embed"
	"encoding/json"
	"fmt"
	"io/fs"
	"log/slog"
	"net/http"
	"strconv"
	"strings"
	"time"

	"neotranscoder/internal/auth"
	"neotranscoder/internal/buildinfo"
	"neotranscoder/internal/config"
	"neotranscoder/internal/doctor"
	"neotranscoder/internal/ffmpeg"
	"neotranscoder/internal/probe"
	"neotranscoder/internal/streams"
	"neotranscoder/internal/sysinfo"
)

//go:embed static/*
var embeddedWeb embed.FS

type contextKey string

const userContextKey contextKey = "user"

type Server struct {
	cfg   config.Config
	log   *slog.Logger
	store *streams.Store
	jobs  *streams.JobManager
	sys   *sysinfo.Collector
}

func New(cfg config.Config, log *slog.Logger) (*Server, error) {
	store, err := streams.NewStore(cfg.Storage.Path)
	if err != nil {
		return nil, fmt.Errorf("stream store: %w", err)
	}
	return &Server{
		cfg:   cfg,
		log:   log,
		store: store,
		jobs:  streams.NewJobManager(cfg.FFmpeg.Path, systemConfigFrom(cfg.FFmpeg), store, log),
		sys:   sysinfo.NewCollector(""),
	}, nil
}

func (s *Server) Run(ctx context.Context) error {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /api/health", s.health)
	mux.HandleFunc("GET /api/auth/required", s.authRequired)
	mux.HandleFunc("POST /api/auth/login", s.login)
	mux.HandleFunc("POST /api/auth/refresh", s.refresh)
	mux.HandleFunc("GET /api/auth/verify", s.verify)
	mux.HandleFunc("POST /api/auth/change-password", s.changeOwnPassword)
	mux.HandleFunc("GET /api/doctor", s.doctor)
	mux.HandleFunc("GET /api/events", s.events)
	mux.HandleFunc("GET /api/metrics", s.metrics)
	mux.HandleFunc("GET /api/system", s.system)
	mux.HandleFunc("GET /api/logs", s.logs)
	mux.HandleFunc("DELETE /api/logs", s.clearLogs)
	mux.HandleFunc("GET /api/users", s.listUsers)
	mux.HandleFunc("POST /api/users", s.createUser)
	mux.HandleFunc("PUT /api/users/{username}/password", s.changeUserPassword)
	mux.HandleFunc("DELETE /api/users/{username}", s.deleteUser)
	mux.HandleFunc("POST /api/probe", s.probe)
	mux.HandleFunc("GET /api/profiles", s.listProfiles)
	mux.HandleFunc("POST /api/profiles", s.upsertProfile)
	mux.HandleFunc("GET /api/profiles/{name}", s.getProfile)
	mux.HandleFunc("PUT /api/profiles/{name}", s.upsertProfile)
	mux.HandleFunc("DELETE /api/profiles/{name}", s.deleteProfile)
	mux.HandleFunc("GET /api/streams", s.listStreams)
	mux.HandleFunc("POST /api/streams", s.upsertStream)
	mux.HandleFunc("GET /api/streams/{id}", s.getStream)
	mux.HandleFunc("PUT /api/streams/{id}", s.upsertStream)
	mux.HandleFunc("DELETE /api/streams/{id}", s.deleteStream)
	mux.HandleFunc("POST /api/streams/{id}/start", s.startStream)
	mux.HandleFunc("POST /api/streams/{id}/stop", s.stopStream)
	mux.HandleFunc("POST /api/streams/{id}/restart", s.restartStream)
	mux.HandleFunc("GET /api/streams/{id}/ffmpeg-command", s.ffmpegCommand)
	mux.HandleFunc("GET /api/streams/{id}/logs", s.streamLogs)
	mux.HandleFunc("DELETE /api/streams/{id}/logs", s.clearStreamLogs)
	mux.Handle("/", s.web())

	handler := s.auth(mux)
	srv := &http.Server{
		Addr:              s.cfg.Addr(),
		Handler:           handler,
		ReadHeaderTimeout: 5 * time.Second,
	}

	go s.sys.Run(ctx)

	go func() {
		<-ctx.Done()
		s.jobs.StopAll()
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = srv.Shutdown(shutdownCtx)
	}()

	s.log.Info("starting neotranscoder", "addr", s.cfg.Addr())
	if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		return err
	}
	return nil
}

func (s *Server) auth(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/api/health" ||
			r.URL.Path == "/api/auth/required" ||
			r.URL.Path == "/api/auth/login" ||
			r.URL.Path == "/api/auth/refresh" ||
			!strings.HasPrefix(r.URL.Path, "/api/") {
			next.ServeHTTP(w, r)
			return
		}
		user, ok := s.userFromRequest(w, r, "access")
		if !ok {
			return
		}
		next.ServeHTTP(w, r.WithContext(context.WithValue(r.Context(), userContextKey, user)))
	})
}

func (s *Server) authRequired(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{
		"required": true,
	})
}

func (s *Server) login(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Username string `json:"username"`
		Password string `json:"password"`
	}
	if !readJSON(w, r, &req) {
		return
	}
	user, ok := s.store.Authenticate(req.Username, req.Password)
	if !ok {
		writeErrorText(w, http.StatusUnauthorized, "invalid username or password")
		return
	}
	s.writeTokenPair(w, user)
}

func (s *Server) refresh(w http.ResponseWriter, r *http.Request) {
	var req struct {
		RefreshToken string `json:"refresh_token"`
	}
	if !readJSON(w, r, &req) {
		return
	}
	claims, err := auth.VerifyToken(s.store.AuthSecret(), req.RefreshToken, "refresh", time.Now())
	if err != nil {
		writeErrorText(w, http.StatusUnauthorized, err.Error())
		return
	}
	user, ok := s.store.VerifyTokenClaims(claims)
	if !ok {
		writeErrorText(w, http.StatusUnauthorized, "invalid refresh token")
		return
	}
	s.writeTokenPair(w, user)
}

func (s *Server) verify(w http.ResponseWriter, r *http.Request) {
	user, ok := s.userFromRequest(w, r, "access")
	if !ok {
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"valid": true,
		"user":  auth.Public(user),
	})
}

func (s *Server) changeOwnPassword(w http.ResponseWriter, r *http.Request) {
	user, ok := s.userFromRequest(w, r, "access")
	if !ok {
		return
	}
	var req struct {
		CurrentPassword string `json:"current_password"`
		NewPassword     string `json:"new_password"`
	}
	if !readJSON(w, r, &req) {
		return
	}
	updated, err := s.store.ChangePassword(user.Username, req.CurrentPassword, req.NewPassword, true)
	if err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	writeJSON(w, http.StatusOK, updated)
}

func (s *Server) listUsers(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, s.store.ListUsers())
}

func (s *Server) createUser(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Username string `json:"username"`
		Password string `json:"password"`
	}
	if !readJSON(w, r, &req) {
		return
	}
	user, err := s.store.CreateUser(req.Username, req.Password)
	if err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	writeJSON(w, http.StatusCreated, user)
}

func (s *Server) changeUserPassword(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Password string `json:"password"`
	}
	if !readJSON(w, r, &req) {
		return
	}
	user, err := s.store.ChangePassword(r.PathValue("username"), "", req.Password, false)
	if err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	writeJSON(w, http.StatusOK, user)
}

func (s *Server) deleteUser(w http.ResponseWriter, r *http.Request) {
	deleted, err := s.store.DeleteUser(r.PathValue("username"))
	if err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	if !deleted {
		writeErrorText(w, http.StatusNotFound, "user not found")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) writeTokenPair(w http.ResponseWriter, user auth.User) {
	now := time.Now()
	accessExpires := now.Add(auth.AccessTokenTTL)
	refreshExpires := now.Add(auth.RefreshTokenTTL)
	accessToken, err := auth.IssueToken(s.store.AuthSecret(), auth.Claims{
		Subject:      user.Username,
		Type:         "access",
		TokenVersion: user.TokenVersion,
		ExpiresAt:    accessExpires,
	})
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	refreshToken, err := auth.IssueToken(s.store.AuthSecret(), auth.Claims{
		Subject:      user.Username,
		Type:         "refresh",
		TokenVersion: user.TokenVersion,
		ExpiresAt:    refreshExpires,
	})
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"access_token":         accessToken,
		"refresh_token":        refreshToken,
		"access_expires_at":    accessExpires,
		"refresh_expires_at":   refreshExpires,
		"must_change_password": user.MustChangePassword,
		"user":                 auth.Public(user),
	})
}

func (s *Server) userFromRequest(w http.ResponseWriter, r *http.Request, kind string) (auth.User, bool) {
	const prefix = "Bearer "
	header := r.Header.Get("Authorization")
	token := ""
	if strings.HasPrefix(header, prefix) {
		token = strings.TrimPrefix(header, prefix)
	}
	if token == "" && r.URL.Path == "/api/events" {
		token = r.URL.Query().Get("access_token")
	}
	if token == "" {
		writeErrorText(w, http.StatusUnauthorized, "missing bearer token")
		return auth.User{}, false
	}
	claims, err := auth.VerifyToken(s.store.AuthSecret(), token, kind, time.Now())
	if err != nil {
		writeErrorText(w, http.StatusUnauthorized, err.Error())
		return auth.User{}, false
	}
	user, ok := s.store.VerifyTokenClaims(claims)
	if !ok {
		writeErrorText(w, http.StatusUnauthorized, "invalid bearer token")
		return auth.User{}, false
	}
	return user, true
}

func (s *Server) health(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{
		"ok":      true,
		"service": "neotranscoder",
		"version": buildinfo.Version,
		"commit":  buildinfo.Commit,
		"date":    buildinfo.Date,
	})
}

func (s *Server) doctor(w http.ResponseWriter, _ *http.Request) {
	checks := doctor.Run(s.cfg)
	status := http.StatusOK
	if doctor.HasFailure(checks) {
		status = http.StatusServiceUnavailable
	}
	writeJSON(w, status, checks)
}

func (s *Server) events(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("Connection", "keep-alive")

	flusher, ok := w.(http.Flusher)
	if !ok {
		writeErrorText(w, http.StatusInternalServerError, "streaming is not supported")
		return
	}

	events := s.store.Subscribe(r.Context())
	for {
		select {
		case <-r.Context().Done():
			return
		case event, ok := <-events:
			if !ok {
				return
			}
			if err := writeSSE(w, event); err != nil {
				return
			}
			flusher.Flush()
		}
	}
}

func (s *Server) logs(w http.ResponseWriter, r *http.Request) {
	limit := queryLimit(r)
	writeJSON(w, http.StatusOK, s.store.Logs("", limit))
}

func (s *Server) clearLogs(w http.ResponseWriter, _ *http.Request) {
	s.store.ClearLogs("")
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) metrics(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, s.store.Metrics())
}

func (s *Server) system(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, s.sys.Snapshot())
}

func (s *Server) probe(w http.ResponseWriter, r *http.Request) {
	var req struct {
		InputURL string `json:"input_url"`
	}
	if !readJSON(w, r, &req) {
		return
	}
	result, err := probe.Run(r.Context(), s.cfg.FFmpeg.FFprobePath, req.InputURL)
	if err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	writeJSON(w, http.StatusOK, result)
}

func (s *Server) listStreams(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, s.store.List())
}

func (s *Server) listProfiles(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, s.store.ListProfiles())
}

func (s *Server) getProfile(w http.ResponseWriter, r *http.Request) {
	profile, ok := s.store.GetProfile(r.PathValue("name"))
	if !ok {
		writeErrorText(w, http.StatusNotFound, "profile not found")
		return
	}
	writeJSON(w, http.StatusOK, profile)
}

func (s *Server) upsertProfile(w http.ResponseWriter, r *http.Request) {
	var profile ffmpeg.Profile
	if !readJSON(w, r, &profile) {
		return
	}
	if pathName := r.PathValue("name"); pathName != "" {
		profile.Name = pathName
	}
	saved, err := s.store.UpsertProfile(profile)
	if err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	writeJSON(w, http.StatusOK, saved)
}

func (s *Server) deleteProfile(w http.ResponseWriter, r *http.Request) {
	deleted, err := s.store.DeleteProfile(r.PathValue("name"))
	if err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	if !deleted {
		writeErrorText(w, http.StatusNotFound, "profile not found")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) getStream(w http.ResponseWriter, r *http.Request) {
	view, ok := s.store.Get(r.PathValue("id"))
	if !ok {
		writeErrorText(w, http.StatusNotFound, "stream not found")
		return
	}
	writeJSON(w, http.StatusOK, view)
}

func (s *Server) upsertStream(w http.ResponseWriter, r *http.Request) {
	var cfg streams.Config
	if !readJSON(w, r, &cfg) {
		return
	}
	if pathID := r.PathValue("id"); pathID != "" {
		cfg.ID = pathID
	}
	view, err := s.store.Upsert(cfg)
	if err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	writeJSON(w, http.StatusOK, view)
}

func (s *Server) deleteStream(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	_ = s.jobs.Stop(id)
	deleted, err := s.store.Delete(id)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	if !deleted {
		writeErrorText(w, http.StatusNotFound, "stream not found")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) startStream(w http.ResponseWriter, r *http.Request) {
	if err := s.jobs.Start(r.PathValue("id")); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	s.getStream(w, r)
}

func (s *Server) stopStream(w http.ResponseWriter, r *http.Request) {
	if err := s.jobs.Stop(r.PathValue("id")); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	s.getStream(w, r)
}

func (s *Server) restartStream(w http.ResponseWriter, r *http.Request) {
	_ = s.jobs.Stop(r.PathValue("id"))
	if err := s.jobs.Start(r.PathValue("id")); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	s.getStream(w, r)
}

func (s *Server) ffmpegCommand(w http.ResponseWriter, r *http.Request) {
	view, ok := s.store.Get(r.PathValue("id"))
	if !ok {
		writeErrorText(w, http.StatusNotFound, "stream not found")
		return
	}
	profile, ok := s.store.GetProfile(view.Config.ProfileName)
	if !ok {
		writeErrorText(w, http.StatusBadRequest, "profile not found")
		return
	}
	args, err := ffmpeg.BuildArgs(ffmpeg.Stream{
		InputURL:     view.Config.InputURL,
		OutputURL:    view.Config.OutputURL,
		SourceType:   view.Config.SourceType,
		VideoMap:     view.Config.VideoMap,
		AudioMap:     view.Config.AudioMap,
		AudioMaps:    view.Config.AudioMaps,
		DisableAudio: view.Config.DisableAudio,
		Logo: ffmpeg.LogoOverlay{
			Enabled: view.Config.Logo.Enabled,
			Path:    view.Config.Logo.Path,
			X:       view.Config.Logo.X,
			Y:       view.Config.Logo.Y,
		},
		Options: view.Config.Options,
	}, profile, systemConfigFrom(s.cfg.FFmpeg))
	if err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"path": s.cfg.FFmpeg.Path,
		"args": args,
	})
}

func systemConfigFrom(cfg config.FFmpegConfig) ffmpeg.SystemConfig {
	return ffmpeg.SystemConfig{
		UDPFifoSize:        cfg.UDPFifoSize,
		UDPBufferSize:      cfg.UDPBufferSize,
		UDPOverrunNonfatal: cfg.UDPOverrunNonfatal,
		UDPReuse:           cfg.UDPReuse,
		AnalyzeDuration:    cfg.AnalyzeDuration,
		ProbeSize:          cfg.ProbeSize,
		Threads:            cfg.Threads,
		PktSize:            cfg.PktSize,
		DiscardCorrupt:     cfg.DiscardCorrupt,
		LogLevel:           cfg.LogLevel,
	}
}

func (s *Server) streamLogs(w http.ResponseWriter, r *http.Request) {
	limit := queryLimit(r)
	writeJSON(w, http.StatusOK, s.store.Logs(r.PathValue("id"), limit))
}

func (s *Server) clearStreamLogs(w http.ResponseWriter, r *http.Request) {
	s.store.ClearLogs(r.PathValue("id"))
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) web() http.Handler {
	root, err := fs.Sub(embeddedWeb, "static")
	if err != nil {
		panic(fmt.Sprintf("embedded web: %v", err))
	}
	files := http.FileServer(http.FS(root))
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		path := strings.TrimPrefix(r.URL.Path, "/")
		if path == "" {
			files.ServeHTTP(w, r)
			return
		}
		if _, err := fs.Stat(root, path); err == nil {
			files.ServeHTTP(w, r)
			return
		}
		r.URL.Path = "/"
		files.ServeHTTP(w, r)
	})
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func writeSSE(w http.ResponseWriter, event streams.Event) error {
	data, err := json.Marshal(event)
	if err != nil {
		return err
	}
	if _, err := fmt.Fprintf(w, "event: %s\n", event.Type); err != nil {
		return err
	}
	if _, err := fmt.Fprintf(w, "data: %s\n\n", data); err != nil {
		return err
	}
	return nil
}

func queryLimit(r *http.Request) int {
	value := r.URL.Query().Get("limit")
	if value == "" {
		return 200
	}
	limit, err := strconv.Atoi(value)
	if err != nil {
		return 200
	}
	return limit
}

func readJSON(w http.ResponseWriter, r *http.Request, v any) bool {
	defer r.Body.Close()
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(v); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return false
	}
	return true
}

func writeError(w http.ResponseWriter, status int, err error) {
	writeErrorText(w, status, err.Error())
}

func writeErrorText(w http.ResponseWriter, status int, message string) {
	writeJSON(w, status, map[string]any{
		"error": message,
	})
}
