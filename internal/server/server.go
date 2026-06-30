package server

import (
	"context"
	"embed"
	"encoding/json"
	"fmt"
	"io/fs"
	"log/slog"
	"net/http"
	"time"

	"neotranscoder/internal/buildinfo"
	"neotranscoder/internal/config"
	"neotranscoder/internal/doctor"
	"neotranscoder/internal/ffmpeg"
	"neotranscoder/internal/probe"
	"neotranscoder/internal/streams"
)

//go:embed static/*
var embeddedWeb embed.FS

type Server struct {
	cfg   config.Config
	log   *slog.Logger
	store *streams.Store
	jobs  *streams.JobManager
}

func New(cfg config.Config, log *slog.Logger) *Server {
	store := streams.NewStore()
	return &Server{
		cfg:   cfg,
		log:   log,
		store: store,
		jobs:  streams.NewJobManager(cfg.FFmpeg.Path, store, log),
	}
}

func (s *Server) Run(ctx context.Context) error {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /api/health", s.health)
	mux.HandleFunc("GET /api/doctor", s.doctor)
	mux.HandleFunc("POST /api/probe", s.probe)
	mux.HandleFunc("GET /api/streams", s.listStreams)
	mux.HandleFunc("POST /api/streams", s.upsertStream)
	mux.HandleFunc("GET /api/streams/{id}", s.getStream)
	mux.HandleFunc("PUT /api/streams/{id}", s.upsertStream)
	mux.HandleFunc("DELETE /api/streams/{id}", s.deleteStream)
	mux.HandleFunc("POST /api/streams/{id}/start", s.startStream)
	mux.HandleFunc("POST /api/streams/{id}/stop", s.stopStream)
	mux.HandleFunc("POST /api/streams/{id}/restart", s.restartStream)
	mux.HandleFunc("GET /api/streams/{id}/ffmpeg-command", s.ffmpegCommand)
	mux.Handle("/", s.web())

	srv := &http.Server{
		Addr:              s.cfg.Addr(),
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
	}

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

func (s *Server) health(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{
		"ok":      true,
		"service": "neotranscoder",
		"version": buildinfo.Version,
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
	if !s.store.Delete(id) {
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
	args, err := ffmpeg.BuildArgs(ffmpeg.Stream{
		InputURL:  view.Config.InputURL,
		OutputURL: view.Config.OutputURL,
		VideoMap:  view.Config.VideoMap,
		AudioMap:  view.Config.AudioMap,
	}, ffmpeg.H264VeryFast4M())
	if err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"path": s.cfg.FFmpeg.Path,
		"args": args,
	})
}

func (s *Server) web() http.Handler {
	root, err := fs.Sub(embeddedWeb, "static")
	if err != nil {
		panic(fmt.Sprintf("embedded web: %v", err))
	}
	return http.FileServer(http.FS(root))
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
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
