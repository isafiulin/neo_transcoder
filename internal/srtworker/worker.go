package srtworker

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/url"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"neotranscoder/internal/srtrelay"
)

const (
	sessionQueueSize   = 512
	maxQueueDropBurst  = 256
	handshakeAuditWait = 10 * time.Second
)

var (
	workerSequence atomic.Uint64
	workerRegistry sync.Map
)

type worker struct {
	config  srtrelay.WorkerConfig
	clients map[string]clientACL
	events  chan srtrelay.WorkerEvent
	handle  uintptr

	mu           sync.RWMutex
	sessions     map[string]*clientSession
	pending      map[string]pendingAttempt
	reservations map[string]int
	attempts     map[string]attemptWindow
	listener     int
	input        *net.UDPConn

	inputBytes      atomic.Int64
	inputPackets    atomic.Int64
	lastInputAt     atomic.Int64
	continuityError atomic.Int64
	stopping        atomic.Bool
	wg              sync.WaitGroup
}

type clientACL struct {
	config   srtrelay.WorkerClient
	networks []*net.IPNet
}

type pendingAttempt struct {
	clientID   string
	remoteIP   string
	remotePort int
	streamID   string
}

type attemptWindow struct {
	started  time.Time
	count    int
	reported bool
}

type clientSession struct {
	worker    *worker
	socket    int
	queue     chan []byte
	done      chan struct{}
	closeOnce sync.Once
	data      srtrelay.Session
	dropBurst atomic.Int64
	appDrops  atomic.Int64
	fatal     chan<- error
}

func Run(ctx context.Context, config srtrelay.WorkerConfig, stdout, stderr io.Writer) error {
	w, err := newWorker(config)
	if err != nil {
		return err
	}
	if err := nativeStartup(); err != nil {
		return err
	}
	defer nativeCleanup()

	w.handle = uintptr(workerSequence.Add(1))
	workerRegistry.Store(w.handle, w)
	defer workerRegistry.Delete(w.handle)

	ctx, cancel := context.WithCancel(ctx)
	defer cancel()
	eventErr := make(chan error, 1)
	go writeEvents(w.events, stdout, eventErr)

	input, err := openMulticast(config.Relay)
	if err != nil {
		return fmt.Errorf("multicast input: %w", err)
	}
	w.input = input
	defer input.Close()

	runErr := make(chan error, 3)
	endpoint := -1
	if config.Relay.Direction == srtrelay.DirectionPublish {
		endpoint, err = nativeOpenCaller(
			config.Relay.DestinationAddress, config.Relay.DestinationPort,
			config.Relay.LatencyMS, config.Relay.PayloadSize,
			config.Relay.StreamID, config.PublishPassphrase,
		)
		if err != nil {
			return fmt.Errorf("SRT caller connect: %w", err)
		}
		now := time.Now().UTC()
		session := &clientSession{
			worker: w, socket: endpoint, queue: make(chan []byte, sessionQueueSize),
			done: make(chan struct{}), fatal: runErr,
			data: srtrelay.Session{
				ID: fmt.Sprintf("publish-%d", now.UnixNano()), RelayID: config.Relay.ID,
				ClientID: config.Relay.StreamID, RemoteIP: config.Relay.DestinationAddress,
				RemotePort: config.Relay.DestinationPort, StreamID: config.Relay.StreamID,
				Encrypted: config.Relay.EncryptionMode == srtrelay.EncryptionAES256, ConnectedAt: now,
			},
		}
		w.sessions[session.data.ID] = session
		data := session.data
		w.emit(srtrelay.WorkerEvent{Type: "session_connected", Time: now, Session: &data})
		w.wg.Add(1)
		go session.sendLoop()
	} else {
		endpoint, err = nativeOpenListener(
			config.Relay.BindAddress, config.Relay.Port, config.Relay.LatencyMS,
			config.Relay.PayloadSize, listenerMinimumVersion(config.Relay), w.handle,
		)
		if err != nil {
			return fmt.Errorf("SRT listener: %w", err)
		}
		w.listener = endpoint
		w.wg.Add(1)
		go w.acceptLoop(runErr)
	}
	defer nativeClose(endpoint)

	w.emit(srtrelay.WorkerEvent{Type: "relay_ready", Time: time.Now().UTC()})
	w.wg.Add(2)
	go w.inputLoop(runErr)
	go w.metricsLoop(ctx)

	var result error
	select {
	case <-ctx.Done():
	case err := <-eventErr:
		result = fmt.Errorf("event output: %w", err)
	case err := <-runErr:
		result = err
	}
	w.stopping.Store(true)
	cancel()
	_ = input.Close()
	nativeClose(endpoint)
	w.closeAllSessions("relay stopped")
	w.mu.Lock()
	clear(w.pending)
	clear(w.reservations)
	w.mu.Unlock()
	w.wg.Wait()
	close(w.events)
	select {
	case err := <-eventErr:
		if result == nil && err != nil {
			result = fmt.Errorf("event output: %w", err)
		}
	case <-time.After(time.Second):
	}
	if result != nil {
		fmt.Fprintln(stderr, result)
	}
	return result
}

func listenerMinimumVersion(relay srtrelay.Relay) int {
	if relay.AllowMissingStreamID {
		// ponytail: compatibility mode accepts legacy HSv4 receivers. The
		// listener still enforces the selected client ACL and encryption policy.
		return 0x010000
	}
	return 0x010300
}

func newWorker(config srtrelay.WorkerConfig) (*worker, error) {
	if config.Relay.Direction == "" {
		config.Relay.Direction = srtrelay.DirectionListener
	}
	if config.Relay.Direction == srtrelay.DirectionPublish {
		if config.Relay.EncryptionMode == srtrelay.EncryptionAES256 &&
			(len(config.PublishPassphrase) < 10 || len(config.PublishPassphrase) > 79) {
			return nil, fmt.Errorf("invalid SRT publish passphrase")
		}
		if config.Relay.EncryptionMode == srtrelay.EncryptionNone && config.PublishPassphrase != "" {
			return nil, fmt.Errorf("unencrypted SRT publish relay must not have a passphrase")
		}
	}
	if config.Relay.InputTimeoutSeconds == 0 {
		config.Relay.InputTimeoutSeconds = 10
	}
	if config.Relay.InputTimeoutSeconds < 3 || config.Relay.InputTimeoutSeconds > 300 {
		return nil, fmt.Errorf("input_timeout_seconds must be between 3 and 300")
	}
	clients := make(map[string]clientACL, len(config.Clients))
	for _, client := range config.Clients {
		if client.EncryptionMode == "" {
			client.EncryptionMode = srtrelay.EncryptionAES256
		}
		if client.ID == "" || (client.EncryptionMode != srtrelay.EncryptionAES256 && client.EncryptionMode != srtrelay.EncryptionNone) {
			return nil, fmt.Errorf("invalid SRT client %q", client.ID)
		}
		if client.EncryptionMode == srtrelay.EncryptionAES256 && (len(client.Passphrase) < 10 || len(client.Passphrase) > 79) {
			return nil, fmt.Errorf("invalid SRT client %q passphrase", client.ID)
		}
		if client.EncryptionMode == srtrelay.EncryptionNone && client.Passphrase != "" {
			return nil, fmt.Errorf("unencrypted SRT client %q must not have a passphrase", client.ID)
		}
		acl := clientACL{config: client}
		for _, value := range client.AllowedCIDRs {
			_, network, err := net.ParseCIDR(value)
			if err != nil {
				return nil, fmt.Errorf("client %q CIDR %q: %w", client.ID, value, err)
			}
			acl.networks = append(acl.networks, network)
		}
		clients[client.ID] = acl
	}
	if config.Relay.AllowMissingStreamID {
		if config.Relay.Direction != srtrelay.DirectionListener {
			return nil, fmt.Errorf("missing Stream ID compatibility is listener-only")
		}
		if _, ok := clients[config.Relay.DefaultClientID]; !ok {
			return nil, fmt.Errorf("default SRT client %q is unavailable", config.Relay.DefaultClientID)
		}
	}
	w := &worker{
		config:       config,
		clients:      clients,
		events:       make(chan srtrelay.WorkerEvent, 1024),
		sessions:     make(map[string]*clientSession),
		pending:      make(map[string]pendingAttempt),
		reservations: make(map[string]int),
		attempts:     make(map[string]attemptWindow),
		listener:     -1,
	}
	w.lastInputAt.Store(time.Now().UnixNano())
	return w, nil
}

func (w *worker) authorize(remoteIP string, remotePort int, streamID string) (string, int) {
	now := time.Now().UTC()
	baseSession := srtrelay.Session{RemoteIP: remoteIP, RemotePort: remotePort, StreamID: streamID}
	key := attemptKey(remoteIP, remotePort, streamID)
	if secret, ok := w.pendingSecret(key); ok {
		return secret, 0
	}
	allowed, report := w.allowConnectionAttempt(remoteIP, now)
	if !allowed {
		if report {
			w.emitRejected(baseSession, "connection attempt rate limit exceeded")
		}
		return "", 429
	}
	w.emit(srtrelay.WorkerEvent{Type: "connection_attempt", Time: now, Session: &baseSession})
	clientID, err := clientIDFromStreamID(streamID)
	if err != nil {
		if streamID != "" || !w.config.Relay.AllowMissingStreamID {
			w.emitRejected(baseSession, err.Error())
			return "", 400
		}
		clientID = w.config.Relay.DefaultClientID
	}
	baseSession.ClientID = clientID
	acl, ok := w.clients[clientID]
	if !ok {
		w.emitRejected(baseSession, "unknown or disabled SRT client")
		return "", 404
	}
	ip := net.ParseIP(remoteIP)
	if ip == nil || !ipAllowed(ip, acl.networks) {
		w.emitRejected(baseSession, "remote IP is not allowed")
		return "", 403
	}

	w.mu.Lock()
	if attempt, ok := w.pending[key]; ok {
		secret := w.clients[attempt.clientID].config.Passphrase
		w.mu.Unlock()
		return secret, 0
	}
	activeForClient := w.reservations[clientID]
	for _, session := range w.sessions {
		if session.data.ClientID == clientID {
			activeForClient++
		}
	}
	if activeForClient >= acl.config.MaxSessions {
		w.mu.Unlock()
		w.emitRejected(baseSession, "client session limit reached")
		return "", 429
	}
	if len(w.sessions)+len(w.pending) >= w.config.Relay.MaxClients {
		w.mu.Unlock()
		w.emitRejected(baseSession, "relay client limit reached")
		return "", 429
	}
	w.pending[key] = pendingAttempt{clientID: clientID, remoteIP: remoteIP, remotePort: remotePort, streamID: streamID}
	w.reservations[clientID]++
	w.mu.Unlock()

	time.AfterFunc(handshakeAuditWait, func() { w.expireAttempt(key) })
	return acl.config.Passphrase, 0
}

func (w *worker) pendingSecret(key string) (string, bool) {
	w.mu.RLock()
	defer w.mu.RUnlock()
	attempt, ok := w.pending[key]
	if !ok {
		return "", false
	}
	acl, ok := w.clients[attempt.clientID]
	if !ok {
		return "", false
	}
	return acl.config.Passphrase, true
}

func (w *worker) allowConnectionAttempt(remoteIP string, now time.Time) (bool, bool) {
	const (
		attemptsPerMinute = 60
		maxTrackedIPs     = 10000
	)
	w.mu.Lock()
	defer w.mu.Unlock()
	window, exists := w.attempts[remoteIP]
	if !exists && len(w.attempts) >= maxTrackedIPs {
		for ip, candidate := range w.attempts {
			if now.Sub(candidate.started) >= time.Minute {
				delete(w.attempts, ip)
			}
		}
	}
	if !exists && len(w.attempts) >= maxTrackedIPs {
		// ponytail: the in-worker limiter has a hard memory ceiling. A public
		// deployment should enforce broad flood control in the host firewall.
		return false, false
	}
	if !exists || now.Sub(window.started) >= time.Minute {
		w.attempts[remoteIP] = attemptWindow{started: now, count: 1}
		return true, false
	}
	window.count++
	if window.count <= attemptsPerMinute {
		w.attempts[remoteIP] = window
		return true, false
	}
	report := !window.reported
	window.reported = true
	w.attempts[remoteIP] = window
	return false, report
}

func (w *worker) expireAttempt(key string) {
	w.mu.Lock()
	attempt, ok := w.pending[key]
	if ok {
		delete(w.pending, key)
		w.reservations[attempt.clientID]--
	}
	w.mu.Unlock()
	if ok {
		w.emitRejected(srtrelay.Session{
			ClientID:   attempt.clientID,
			RemoteIP:   attempt.remoteIP,
			RemotePort: attempt.remotePort,
			StreamID:   attempt.streamID,
		}, "SRT handshake did not complete: encryption mismatch or timeout")
	}
}

func (w *worker) acceptLoop(errors chan<- error) {
	defer w.wg.Done()
	for {
		socket, remoteIP, remotePort, streamID, peerVersion, encrypted, err := nativeAccept(w.listener)
		if err != nil {
			if w.isStopping() {
				return
			}
			errors <- fmt.Errorf("SRT accept: %w", err)
			return
		}
		key := attemptKey(remoteIP, remotePort, streamID)
		w.mu.Lock()
		attempt, authorized := w.pending[key]
		if authorized {
			delete(w.pending, key)
			w.reservations[attempt.clientID]--
		}
		clientID := attempt.clientID
		if !authorized {
			clientID, err = clientIDFromStreamID(streamID)
			if err != nil {
				w.mu.Unlock()
				nativeClose(socket)
				continue
			}
		}
		sessionID, idErr := randomSessionID()
		if idErr != nil {
			w.mu.Unlock()
			nativeClose(socket)
			continue
		}
		session := &clientSession{
			worker: w,
			socket: socket,
			queue:  make(chan []byte, sessionQueueSize),
			done:   make(chan struct{}),
			data: srtrelay.Session{
				ID:          sessionID,
				RelayID:     w.config.Relay.ID,
				ClientID:    clientID,
				RemoteIP:    remoteIP,
				RemotePort:  remotePort,
				StreamID:    streamID,
				PeerVersion: peerVersion,
				Encrypted:   encrypted,
				ConnectedAt: time.Now().UTC(),
			},
		}
		w.sessions[sessionID] = session
		w.mu.Unlock()
		data := session.data
		w.emit(srtrelay.WorkerEvent{Type: "session_connected", Time: data.ConnectedAt, Session: &data})
		w.wg.Add(1)
		go session.sendLoop()
	}
}

func (w *worker) inputLoop(errors chan<- error) {
	defer w.wg.Done()
	buffer := make([]byte, 65535)
	pending := make([]byte, 0, w.config.Relay.PayloadSize*2)
	continuity := newContinuityTracker()
	for {
		count, _, err := w.input.ReadFromUDP(buffer)
		if err != nil {
			if w.isStopping() {
				return
			}
			errors <- fmt.Errorf("multicast read: %w", err)
			return
		}
		w.inputBytes.Add(int64(count))
		w.inputPackets.Add(int64(count / 188))
		w.lastInputAt.Store(time.Now().UnixNano())
		w.continuityError.Add(continuity.observe(buffer[:count]))
		pending = append(pending, buffer[:count]...)
		for len(pending) >= w.config.Relay.PayloadSize {
			packet := append([]byte(nil), pending[:w.config.Relay.PayloadSize]...)
			pending = pending[w.config.Relay.PayloadSize:]
			w.broadcast(packet)
		}
		if cap(pending) > w.config.Relay.PayloadSize*8 {
			pending = append(make([]byte, 0, w.config.Relay.PayloadSize*2), pending...)
		}
	}
}

func (w *worker) broadcast(packet []byte) {
	w.mu.RLock()
	sessions := make([]*clientSession, 0, len(w.sessions))
	for _, session := range w.sessions {
		sessions = append(sessions, session)
	}
	w.mu.RUnlock()
	for _, session := range sessions {
		select {
		case <-session.done:
			continue
		default:
		}
		select {
		case session.queue <- packet:
			session.dropBurst.Store(0)
		case <-session.done:
		default:
			session.appDrops.Add(1)
			if session.dropBurst.Add(1) == maxQueueDropBurst {
				go session.close("client send queue remained full")
			}
		}
	}
}

func (session *clientSession) sendLoop() {
	defer session.worker.wg.Done()
	for {
		select {
		case <-session.done:
			return
		case packet := <-session.queue:
			if err := nativeSend(session.socket, packet); err != nil {
				session.close("SRT send failed: " + err.Error())
				return
			}
		}
	}
}

func (session *clientSession) close(reason string) {
	session.closeOnce.Do(func() {
		close(session.done)
		nativeClose(session.socket)
		session.worker.mu.Lock()
		delete(session.worker.sessions, session.data.ID)
		now := time.Now().UTC()
		session.data.DisconnectedAt = &now
		session.data.DisconnectReason = reason
		session.worker.mu.Unlock()
		data := session.data
		session.worker.emit(srtrelay.WorkerEvent{Type: "session_disconnected", Time: now, Reason: reason, Session: &data})
		if session.fatal != nil && !session.worker.stopping.Load() {
			select {
			case session.fatal <- fmt.Errorf("%s", reason):
			default:
			}
		}
	})
}

func (w *worker) metricsLoop(ctx context.Context) {
	defer w.wg.Done()
	ticker := time.NewTicker(time.Second)
	defer ticker.Stop()
	lastInputBytes := w.inputBytes.Load()
	for {
		select {
		case <-ctx.Done():
			return
		case now := <-ticker.C:
			currentInputBytes := w.inputBytes.Load()
			inputBitrate := (currentInputBytes - lastInputBytes) * 8
			lastInputBytes = currentInputBytes
			var outputBitrate int64
			w.mu.RLock()
			sessions := make([]*clientSession, 0, len(w.sessions))
			for _, session := range w.sessions {
				sessions = append(sessions, session)
			}
			w.mu.RUnlock()
			for _, session := range sessions {
				stats, err := nativeStats(session.socket)
				if err != nil {
					continue
				}
				stats.PacketsDropped += session.appDrops.Load()
				session.worker.mu.Lock()
				session.data.Stats = srtrelay.SessionStats{
					BytesSent:       stats.BytesSent,
					PacketsSent:     stats.PacketsSent,
					PacketsLost:     stats.PacketsLost,
					PacketsRetrans:  stats.PacketsRetrans,
					PacketsDropped:  stats.PacketsDropped,
					BitrateBPS:      stats.BitrateBPS,
					RTTMilliseconds: stats.RTTMS,
					LatencyMS:       w.config.Relay.LatencyMS,
				}
				data := session.data
				session.worker.mu.Unlock()
				outputBitrate += stats.BitrateBPS
				w.emit(srtrelay.WorkerEvent{Type: "session_stats", Time: now.UTC(), Session: &data})
			}
			reason := inputStallReason(
				now,
				time.Unix(0, w.lastInputAt.Load()),
				time.Duration(w.config.Relay.InputTimeoutSeconds)*time.Second,
			)
			w.emit(srtrelay.WorkerEvent{
				Type:             "relay_metrics",
				Time:             now.UTC(),
				Reason:           reason,
				ActiveClients:    len(sessions),
				InputBitrateBPS:  inputBitrate,
				OutputBitrateBPS: outputBitrate,
				InputPackets:     w.inputPackets.Load(),
				ContinuityErrors: w.continuityError.Load(),
			})
		}
	}
}

func inputStallReason(now, lastInput time.Time, timeout time.Duration) string {
	if timeout <= 0 || now.Sub(lastInput) < timeout {
		return ""
	}
	return fmt.Sprintf("multicast input has no packets for %d seconds", int(timeout/time.Second))
}

func (w *worker) closeAllSessions(reason string) {
	w.mu.RLock()
	sessions := make([]*clientSession, 0, len(w.sessions))
	for _, session := range w.sessions {
		sessions = append(sessions, session)
	}
	w.mu.RUnlock()
	for _, session := range sessions {
		session.close(reason)
	}
}

func (w *worker) isStopping() bool {
	return w.stopping.Load()
}

func (w *worker) emit(event srtrelay.WorkerEvent) bool {
	select {
	case w.events <- event:
		return true
	default:
		return false
	}
}

func (w *worker) emitRejected(session srtrelay.Session, reason string) {
	w.emit(srtrelay.WorkerEvent{Type: "connection_rejected", Time: time.Now().UTC(), Reason: reason, Session: &session})
}

func writeEvents(events <-chan srtrelay.WorkerEvent, output io.Writer, result chan<- error) {
	writer := bufio.NewWriter(output)
	encoder := json.NewEncoder(writer)
	for event := range events {
		if err := encoder.Encode(event); err != nil {
			result <- err
			return
		}
		if err := writer.Flush(); err != nil {
			result <- err
			return
		}
	}
	result <- writer.Flush()
}

func openMulticast(relay srtrelay.Relay) (*net.UDPConn, error) {
	u, err := url.Parse(relay.InputURL)
	if err != nil {
		return nil, err
	}
	port, err := strconv.Atoi(u.Port())
	if err != nil {
		return nil, fmt.Errorf("invalid multicast port")
	}
	address := &net.UDPAddr{IP: net.ParseIP(u.Hostname()), Port: port}
	var networkInterface *net.Interface
	if relay.NetworkInterface != "" {
		networkInterface, err = net.InterfaceByName(relay.NetworkInterface)
		if err != nil {
			return nil, err
		}
	} else if localAddress := u.Query().Get("localaddr"); localAddress != "" {
		networkInterface, err = interfaceByIP(net.ParseIP(localAddress))
		if err != nil {
			return nil, err
		}
	}
	connection, err := net.ListenMulticastUDP("udp4", networkInterface, address)
	if err != nil {
		return nil, err
	}
	if err := connection.SetReadBuffer(8 * 1024 * 1024); err != nil {
		_ = connection.Close()
		return nil, err
	}
	return connection, nil
}

func interfaceByIP(ip net.IP) (*net.Interface, error) {
	if ip == nil {
		return nil, fmt.Errorf("localaddr must be an IP address")
	}
	interfaces, err := net.Interfaces()
	if err != nil {
		return nil, err
	}
	for index := range interfaces {
		addresses, err := interfaces[index].Addrs()
		if err != nil {
			continue
		}
		for _, address := range addresses {
			candidate := net.ParseIP(strings.Split(address.String(), "/")[0])
			if candidate != nil && candidate.Equal(ip) {
				return &interfaces[index], nil
			}
		}
	}
	return nil, fmt.Errorf("no network interface has address %s", ip)
}

func ipAllowed(ip net.IP, networks []*net.IPNet) bool {
	for _, network := range networks {
		if network.Contains(ip) {
			return true
		}
	}
	return false
}

func attemptKey(ip string, port int, streamID string) string {
	return net.JoinHostPort(ip, strconv.Itoa(port)) + "\x00" + streamID
}

func randomSessionID() (string, error) {
	return randomID("srt_")
}
