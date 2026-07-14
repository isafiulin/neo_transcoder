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
	"neotranscoder/internal/srtrelay"
	"neotranscoder/internal/streams"
	"neotranscoder/internal/sysinfo"
)

//go:embed static/*
var embeddedWeb embed.FS

type contextKey string

const userContextKey contextKey = "user"

type Server struct {
	cfg      config.Config
	log      *slog.Logger
	store    *streams.Store
	jobs     *streams.JobManager
	srtStore *srtrelay.Store
	srtJobs  *srtrelay.Manager
	srtErr   error
	sys      *sysinfo.Collector
}

func New(cfg config.Config, log *slog.Logger) (*Server, error) {
	store, err := streams.NewStore(cfg.Storage.Path)
	if err != nil {
		return nil, fmt.Errorf("stream store: %w", err)
	}
	srtStore, err := srtrelay.NewStore(
		cfg.SRT.StatePath,
		cfg.SRT.MasterKeyPath,
		cfg.SRT.AuditDir,
		cfg.SRT.AuditRetentionDays,
	)
	var srtErr error
	if err != nil {
		srtErr = err
		log.Error("SRT store unavailable; SRT API disabled", "error", err)
		srtStore, err = srtrelay.NewEphemeralStore()
		if err != nil {
			return nil, fmt.Errorf("SRT fallback store: %w", err)
		}
	}
	return &Server{
		cfg:      cfg,
		log:      log,
		store:    store,
		jobs:     streams.NewJobManager(cfg.FFmpeg.Path, systemConfigFrom(cfg.FFmpeg), store, log),
		srtStore: srtStore,
		srtJobs:  srtrelay.NewManager(cfg.SRT.WorkerPath, srtStore, log),
		srtErr:   srtErr,
		sys:      sysinfo.NewCollector(""),
	}, nil
}

func (s *Server) Run(ctx context.Context) error {
	handler := s.handler()
	srv := &http.Server{
		Addr:              s.cfg.Addr(),
		Handler:           handler,
		ReadHeaderTimeout: 5 * time.Second,
	}

	go s.sys.Run(ctx)
	if s.srtErr == nil {
		go s.srtJobs.StartEnabled()
	}

	go func() {
		<-ctx.Done()
		s.jobs.StopAll()
		s.srtJobs.StopAll()
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

func (s *Server) handler() http.Handler {
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
	mux.HandleFunc("GET /api/srt/relays", s.withSRT(s.listSRTRelays))
	mux.HandleFunc("POST /api/srt/relays", s.withSRT(s.upsertSRTRelay))
	mux.HandleFunc("GET /api/srt/relays/{id}", s.withSRT(s.getSRTRelay))
	mux.HandleFunc("PUT /api/srt/relays/{id}", s.withSRT(s.upsertSRTRelay))
	mux.HandleFunc("DELETE /api/srt/relays/{id}", s.withSRT(s.deleteSRTRelay))
	mux.HandleFunc("POST /api/srt/relays/{id}/start", s.withSRT(s.startSRTRelay))
	mux.HandleFunc("POST /api/srt/relays/{id}/stop", s.withSRT(s.stopSRTRelay))
	mux.HandleFunc("POST /api/srt/relays/{id}/restart", s.withSRT(s.restartSRTRelay))
	mux.HandleFunc("POST /api/srt/relays/{id}/rotate-key", s.withSRT(s.rotateSRTRelayKey))
	mux.HandleFunc("GET /api/srt/clients", s.withSRT(s.listSRTClients))
	mux.HandleFunc("POST /api/srt/clients", s.withSRT(s.upsertSRTClient))
	mux.HandleFunc("PUT /api/srt/clients/{id}", s.withSRT(s.upsertSRTClient))
	mux.HandleFunc("DELETE /api/srt/clients/{id}", s.withSRT(s.deleteSRTClient))
	mux.HandleFunc("POST /api/srt/clients/{id}/rotate-key", s.withSRT(s.rotateSRTClientKey))
	mux.HandleFunc("GET /api/srt/sessions", s.withSRT(s.listSRTSessions))
	mux.HandleFunc("GET /api/srt/audit", s.withSRT(s.listSRTAudit))
	mux.HandleFunc("DELETE /api/srt/audit", s.withSRT(s.clearSRTAudit))
	mux.Handle("/", s.web())
	return s.auth(mux)
}

func (s *Server) withSRT(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if s.srtErr != nil {
			writeErrorText(w, http.StatusServiceUnavailable, "SRT store unavailable: "+s.srtErr.Error())
			return
		}
		next(w, r)
	}
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

	streamEvents := s.store.Subscribe(r.Context())
	srtEvents := s.srtStore.Subscribe(r.Context())
	flusher.Flush()
	for {
		select {
		case <-r.Context().Done():
			return
		case event, ok := <-streamEvents:
			if !ok {
				return
			}
			if err := writeSSE(w, event.Type, event); err != nil {
				return
			}
			flusher.Flush()
		case event, ok := <-srtEvents:
			if !ok {
				return
			}
			if err := writeSSE(w, event.Type, event); err != nil {
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
		Options:   view.Config.Options,
		KeepStats: view.Config.KeepStats,
	}, profile, systemConfigFrom(s.cfg.FFmpeg).WithLogLevel(view.Config.LogLevel))
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
		UDPFifoSize:        cfg.UDP.FifoSize,
		UDPBufferSize:      cfg.UDP.BufferSize,
		UDPOverrunNonfatal: cfg.UDP.OverrunNonfatal,
		UDPReuse:           cfg.UDP.Reuse,
		PktSize:            cfg.UDP.PktSize,
		AnalyzeDuration:    cfg.Probe.AnalyzeDuration,
		ProbeSize:          cfg.Probe.ProbeSize,
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

func (s *Server) listSRTRelays(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, s.srtStore.ListRelays())
}

func (s *Server) getSRTRelay(w http.ResponseWriter, r *http.Request) {
	view, ok := s.srtStore.GetRelay(r.PathValue("id"))
	if !ok {
		writeErrorText(w, http.StatusNotFound, "SRT relay not found")
		return
	}
	writeJSON(w, http.StatusOK, view)
}

func (s *Server) upsertSRTRelay(w http.ResponseWriter, r *http.Request) {
	var relay srtrelay.Relay
	if !readJSON(w, r, &relay) {
		return
	}
	if pathID := r.PathValue("id"); pathID != "" {
		relay.ID = pathID
	}
	wasRunning := s.srtJobs.IsRunning(relay.ID)
	view, err := s.srtStore.UpsertRelay(relay)
	if err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	s.recordSRTOperatorAudit(r, srtrelay.AuditEvent{
		Type:    "relay_config_saved",
		RelayID: view.Config.ID,
		Details: map[string]any{"name": view.Config.Name, "listen_port": view.Config.Port},
	})
	if wasRunning {
		var applyErr error
		if view.Config.Enabled {
			applyErr = s.srtJobs.Restart(view.Config.ID)
		} else {
			applyErr = s.srtJobs.Stop(view.Config.ID)
		}
		if applyErr != nil {
			s.srtApplyWarning(w, view.Config.ID, "", applyErr)
		}
	}
	writeJSON(w, http.StatusOK, view)
}

func (s *Server) deleteSRTRelay(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if s.srtJobs.IsRunning(id) {
		writeErrorText(w, http.StatusBadRequest, "relay must be stopped before deletion")
		return
	}
	deleted, err := s.srtStore.DeleteRelay(id)
	if err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	if !deleted {
		writeErrorText(w, http.StatusNotFound, "SRT relay not found")
		return
	}
	s.recordSRTOperatorAudit(r, srtrelay.AuditEvent{Type: "relay_config_deleted", RelayID: id, Level: "warning"})
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) startSRTRelay(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if err := s.srtJobs.Start(id); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	s.recordSRTOperatorAudit(r, srtrelay.AuditEvent{Type: "relay_started", RelayID: id})
	s.getSRTRelay(w, r)
}

func (s *Server) stopSRTRelay(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if err := s.srtJobs.Stop(id); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	s.recordSRTOperatorAudit(r, srtrelay.AuditEvent{Type: "relay_stopped", RelayID: id})
	s.getSRTRelay(w, r)
}

func (s *Server) restartSRTRelay(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if err := s.srtJobs.Restart(id); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	s.recordSRTOperatorAudit(r, srtrelay.AuditEvent{Type: "relay_restarted", RelayID: id})
	s.getSRTRelay(w, r)
}

func (s *Server) rotateSRTRelayKey(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if _, ok := s.srtStore.GetRelay(id); !ok {
		writeErrorText(w, http.StatusNotFound, "SRT relay not found")
		return
	}
	view, err := s.srtStore.RotateRelayKey(id)
	if err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	s.recordSRTOperatorAudit(r, srtrelay.AuditEvent{Type: "relay_key_rotated", RelayID: id, Level: "warning"})
	if s.srtJobs.IsRunning(id) {
		if err := s.srtJobs.Restart(id); err != nil {
			s.srtApplyWarning(w, id, "", err)
		}
	}
	writeJSON(w, http.StatusOK, view)
}

func (s *Server) listSRTClients(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, s.srtStore.ListClients())
}

func (s *Server) upsertSRTClient(w http.ResponseWriter, r *http.Request) {
	var client srtrelay.Client
	if !readJSON(w, r, &client) {
		return
	}
	pathID := r.PathValue("id")
	var credential srtrelay.ClientCredential
	var err error
	if pathID != "" {
		client.ID = pathID
	}
	previous, hadPrevious := s.srtStore.GetClient(client.ID)
	if pathID == "" {
		credential, err = s.srtStore.CreateClient(client)
	} else {
		credential, err = s.srtStore.UpsertClient(client)
	}
	if err != nil {
		if pathID == "" && strings.Contains(err.Error(), "already exists") {
			writeErrorText(w, http.StatusConflict, err.Error())
			return
		}
		writeError(w, http.StatusBadRequest, err)
		return
	}
	s.recordSRTOperatorAudit(r, srtrelay.AuditEvent{
		Type:     "client_config_saved",
		ClientID: credential.Client.ID,
		Details: map[string]any{
			"allowed_relays":  credential.Client.AllowedRelayIDs,
			"allowed_cidrs":   credential.Client.AllowedCIDRs,
			"encryption_mode": credential.Client.EncryptionMode,
		},
	})
	if err := s.restartSRTClientRelays(previous, credential.Client, hadPrevious); err != nil {
		s.srtApplyWarning(w, "", credential.Client.ID, err)
	}
	status := http.StatusOK
	if pathID == "" {
		status = http.StatusCreated
	}
	writeJSON(w, status, credential)
}

func (s *Server) rotateSRTClientKey(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if _, ok := s.srtStore.GetClient(id); !ok {
		writeErrorText(w, http.StatusNotFound, "SRT client not found")
		return
	}
	credential, err := s.srtStore.RotateClientKey(id)
	if err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	s.recordSRTOperatorAudit(r, srtrelay.AuditEvent{Type: "client_key_rotated", ClientID: id, Level: "warning"})
	if err := s.restartSRTRelays(credential.Client.AllowedRelayIDs); err != nil {
		s.srtApplyWarning(w, "", credential.Client.ID, err)
	}
	writeJSON(w, http.StatusOK, credential)
}

func (s *Server) deleteSRTClient(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	client, _ := s.srtStore.GetClient(id)
	deleted, err := s.srtStore.DeleteClient(id)
	if err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	if !deleted {
		writeErrorText(w, http.StatusNotFound, "SRT client not found")
		return
	}
	s.recordSRTOperatorAudit(r, srtrelay.AuditEvent{Type: "client_deleted", ClientID: id, Level: "warning"})
	if err := s.restartSRTRelays(client.AllowedRelayIDs); err != nil {
		s.srtApplyWarning(w, "", id, err)
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) restartSRTClientRelays(previous, current srtrelay.Client, hadPrevious bool) error {
	ids := append([]string(nil), current.AllowedRelayIDs...)
	if hadPrevious {
		ids = append(ids, previous.AllowedRelayIDs...)
	}
	return s.restartSRTRelays(ids)
}

func (s *Server) restartSRTRelays(ids []string) error {
	seen := make(map[string]struct{}, len(ids))
	for _, id := range ids {
		if _, ok := seen[id]; ok || !s.srtJobs.IsRunning(id) {
			continue
		}
		seen[id] = struct{}{}
		view, exists := s.srtStore.GetRelay(id)
		if !exists {
			continue
		}
		var err error
		if view.Config.Enabled {
			err = s.srtJobs.Restart(id)
		} else {
			err = s.srtJobs.Stop(id)
		}
		if err != nil {
			return fmt.Errorf("relay %s: %w", id, err)
		}
	}
	return nil
}

func (s *Server) srtApplyWarning(w http.ResponseWriter, relayID, clientID string, err error) {
	message := "configuration persisted but running SRT relay restart failed: " + err.Error()
	w.Header().Set("X-Neotranscoder-Warning", message)
	s.log.Error("apply SRT configuration", "relay_id", relayID, "client_id", clientID, "error", err)
	_, _ = s.srtStore.RecordAudit(srtrelay.AuditEvent{
		Type:     "configuration_apply_failed",
		Level:    "error",
		RelayID:  relayID,
		ClientID: clientID,
		Reason:   err.Error(),
	})
}

func (s *Server) listSRTSessions(w http.ResponseWriter, r *http.Request) {
	activeOnly := r.URL.Query().Get("active") == "true"
	writeJSON(w, http.StatusOK, s.srtStore.ListSessions(activeOnly))
}

func (s *Server) listSRTAudit(w http.ResponseWriter, r *http.Request) {
	events, err := s.srtStore.Audit(srtrelay.AuditFilter{
		RelayID:  r.URL.Query().Get("relay_id"),
		ClientID: r.URL.Query().Get("client_id"),
		Type:     r.URL.Query().Get("type"),
		Limit:    queryLimit(r),
	})
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, events)
}

func (s *Server) clearSRTAudit(w http.ResponseWriter, r *http.Request) {
	filter := srtrelay.AuditFilter{
		RelayID:  r.URL.Query().Get("relay_id"),
		ClientID: r.URL.Query().Get("client_id"),
		Type:     r.URL.Query().Get("type"),
	}
	cleared, err := s.srtStore.ClearAudit(filter)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	s.recordSRTOperatorAudit(r, srtrelay.AuditEvent{
		Type:     "audit_cleared",
		Level:    "warning",
		RelayID:  filter.RelayID,
		ClientID: filter.ClientID,
		Details: map[string]any{
			"type":    filter.Type,
			"cleared": cleared,
		},
	})
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) recordSRTOperatorAudit(r *http.Request, event srtrelay.AuditEvent) {
	if user, ok := r.Context().Value(userContextKey).(auth.User); ok {
		event.Actor = user.Username
	}
	if _, err := s.srtStore.RecordAudit(event); err != nil {
		s.log.Error("write SRT audit", "event", event.Type, "error", err)
	}
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

func writeSSE(w http.ResponseWriter, eventType string, event any) error {
	data, err := json.Marshal(event)
	if err != nil {
		return err
	}
	if _, err := fmt.Fprintf(w, "event: %s\n", eventType); err != nil {
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
