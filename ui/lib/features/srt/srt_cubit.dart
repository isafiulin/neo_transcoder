import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:neotranscoder_ui/core/api/models.dart';
import 'package:neotranscoder_ui/core/api/srt_models.dart';
import 'package:neotranscoder_ui/core/state/load_status.dart';
import 'package:neotranscoder_ui/data/repositories/srt_repository.dart';

class SrtState extends Equatable {
  const SrtState({
    this.status = LoadStatus.initial,
    this.relays = const <SrtRelayView>[],
    this.clients = const <SrtClient>[],
    this.sessions = const <SrtSession>[],
    this.audit = const <SrtAuditEvent>[],
    this.error = '',
    this.busyIds = const <String>{},
    this.auditRelayId = '',
    this.auditClientId = '',
    this.auditType = '',
  });

  final LoadStatus status;
  final List<SrtRelayView> relays;
  final List<SrtClient> clients;
  final List<SrtSession> sessions;
  final List<SrtAuditEvent> audit;
  final String error;
  final Set<String> busyIds;
  final String auditRelayId;
  final String auditClientId;
  final String auditType;

  SrtRelayView? relay(String id) {
    for (final SrtRelayView relay in relays) {
      if (relay.config.id == id) {
        return relay;
      }
    }
    return null;
  }

  SrtClient? client(String id) {
    for (final SrtClient client in clients) {
      if (client.id == id) {
        return client;
      }
    }
    return null;
  }

  SrtState copyWith({
    LoadStatus? status,
    List<SrtRelayView>? relays,
    List<SrtClient>? clients,
    List<SrtSession>? sessions,
    List<SrtAuditEvent>? audit,
    String? error,
    Set<String>? busyIds,
    String? auditRelayId,
    String? auditClientId,
    String? auditType,
  }) {
    return SrtState(
      status: status ?? this.status,
      relays: relays ?? this.relays,
      clients: clients ?? this.clients,
      sessions: sessions ?? this.sessions,
      audit: audit ?? this.audit,
      error: error ?? this.error,
      busyIds: busyIds ?? this.busyIds,
      auditRelayId: auditRelayId ?? this.auditRelayId,
      auditClientId: auditClientId ?? this.auditClientId,
      auditType: auditType ?? this.auditType,
    );
  }

  @override
  List<Object?> get props => <Object?>[
        status,
        relays,
        clients,
        sessions,
        audit,
        error,
        busyIds,
        auditRelayId,
        auditClientId,
        auditType,
      ];
}

class SrtCubit extends Cubit<SrtState> {
  SrtCubit({required SrtRepository repository})
      : _repository = repository,
        super(const SrtState());

  final SrtRepository _repository;
  StreamSubscription<ApiEvent>? _events;
  final List<SrtAuditEvent> _pendingAudit = <SrtAuditEvent>[];
  Timer? _auditFlushTimer;
  bool _reloadQueued = false;

  Future<void> load() async {
    if (state.status == LoadStatus.initial) {
      _safeEmit(state.copyWith(status: LoadStatus.loading, error: ''));
    }
    try {
      final List<Object> result = await Future.wait<Object>(<Future<Object>>[
        _repository.srtRelays(),
        _repository.srtClients(),
        _repository.srtSessions(),
        _repository.srtAudit(),
      ]);
      _safeEmit(state.copyWith(
        status: LoadStatus.ready,
        relays: result[0] as List<SrtRelayView>,
        clients: result[1] as List<SrtClient>,
        sessions: result[2] as List<SrtSession>,
        audit: result[3] as List<SrtAuditEvent>,
        error: '',
      ));
    } on Object catch (error) {
      _safeEmit(state.copyWith(status: LoadStatus.failure, error: '$error'));
    }
  }

  void subscribe() {
    _events ??= _repository.events().listen(_onEvent);
  }

  Future<SrtRelayView> saveRelay(SrtRelay relay, {String? originalId}) async {
    late SrtRelayView saved;
    await _run(
        relay.id,
        () async => saved =
            await _repository.saveSrtRelay(relay.toJson(), id: originalId));
    await _reloadConfiguration();
    return saved;
  }

  Future<void> deleteRelay(String id) async {
    await _run(id, () => _repository.deleteSrtRelay(id));
    await _reloadConfiguration();
  }

  Future<void> startRelay(String id) =>
      _run(id, () => _repository.startSrtRelay(id));

  Future<void> stopRelay(String id) =>
      _run(id, () => _repository.stopSrtRelay(id));

  Future<void> restartRelay(String id) =>
      _run(id, () => _repository.restartSrtRelay(id));

  Future<SrtClientCredential> saveClient(
    Map<String, Object?> body, {
    String? originalId,
  }) async {
    late SrtClientCredential credential;
    await _run(body['id'] as String? ?? originalId ?? '', () async {
      credential = await _repository.saveSrtClient(body, id: originalId);
    });
    await _reloadConfiguration();
    return credential;
  }

  Future<SrtClientCredential> rotateClientKey(String id) async {
    late SrtClientCredential credential;
    await _run(id, () async {
      credential = await _repository.rotateSrtClientKey(id);
    });
    await _reloadConfiguration();
    return credential;
  }

  Future<void> deleteClient(String id) async {
    await _run(id, () => _repository.deleteSrtClient(id));
    await _reloadConfiguration();
  }

  Future<void> reloadAudit({
    String relayId = '',
    String clientId = '',
    String type = '',
  }) async {
    _discardPendingAudit();
    _safeEmit(state.copyWith(
      auditRelayId: relayId,
      auditClientId: clientId,
      auditType: type,
      error: '',
    ));
    try {
      final List<SrtAuditEvent> audit = await _repository.srtAudit(
        relayId: relayId,
        clientId: clientId,
        type: type,
      );
      _safeEmit(state.copyWith(
        audit: audit,
        auditRelayId: relayId,
        auditClientId: clientId,
        auditType: type,
        error: '',
      ));
    } on Object catch (error) {
      _safeEmit(state.copyWith(error: '$error'));
    }
  }

  Future<void> _run(String id, Future<void> Function() operation) async {
    _safeEmit(
      state.copyWith(busyIds: <String>{...state.busyIds, id}, error: ''),
    );
    try {
      await operation();
    } on Object catch (error) {
      _safeEmit(state.copyWith(error: '$error'));
      rethrow;
    } finally {
      _safeEmit(
        state.copyWith(busyIds: <String>{...state.busyIds}..remove(id)),
      );
    }
  }

  void _onEvent(ApiEvent event) {
    final SrtRelayState? relayState = event.srtRelayState;
    if (relayState != null && event.relayId.isNotEmpty) {
      _patchRelay(event.relayId, relayState);
    }
    final SrtSession? session = event.srtSession;
    if (session != null) {
      _patchSession(session);
    }
    final SrtAuditEvent? audit = event.srtAuditEvent;
    if (audit != null && _auditMatches(audit)) {
      _pendingAudit.add(audit);
      _auditFlushTimer ??= Timer(
        const Duration(milliseconds: 250),
        _flushPendingAudit,
      );
    }
    if (_configurationEvents.contains(event.type)) {
      _queueConfigurationReload();
    }
  }

  bool _auditMatches(SrtAuditEvent event) {
    return (state.auditRelayId.isEmpty ||
            event.relayId == state.auditRelayId) &&
        (state.auditClientId.isEmpty ||
            event.clientId == state.auditClientId) &&
        (state.auditType.isEmpty || event.type == state.auditType);
  }

  void _flushPendingAudit() {
    _auditFlushTimer = null;
    if (_pendingAudit.isEmpty || isClosed) {
      return;
    }
    const int maxVisibleAuditEvents = 500;
    final List<SrtAuditEvent> events = <SrtAuditEvent>[
      ..._pendingAudit.reversed,
      ...state.audit,
    ];
    _pendingAudit.clear();
    _safeEmit(state.copyWith(
      audit: events.length > maxVisibleAuditEvents
          ? events.sublist(0, maxVisibleAuditEvents)
          : events,
    ));
  }

  void _discardPendingAudit() {
    _auditFlushTimer?.cancel();
    _auditFlushTimer = null;
    _pendingAudit.clear();
  }

  void _patchRelay(String id, SrtRelayState relayState) {
    final List<SrtRelayView> relays = List<SrtRelayView>.of(state.relays);
    final int index =
        relays.indexWhere((SrtRelayView item) => item.config.id == id);
    if (index == -1) {
      _queueConfigurationReload();
      return;
    }
    relays[index] =
        SrtRelayView(config: relays[index].config, state: relayState);
    _safeEmit(state.copyWith(status: LoadStatus.ready, relays: relays));
  }

  void _patchSession(SrtSession session) {
    final List<SrtSession> sessions = List<SrtSession>.of(state.sessions);
    final int index =
        sessions.indexWhere((SrtSession item) => item.id == session.id);
    if (index == -1) {
      sessions.insert(0, session);
    } else {
      sessions[index] = session;
    }
    _safeEmit(state.copyWith(sessions: sessions));
  }

  void _queueConfigurationReload() {
    if (_reloadQueued || isClosed) {
      return;
    }
    _reloadQueued = true;
    scheduleMicrotask(() async {
      try {
        await _reloadConfiguration();
      } finally {
        _reloadQueued = false;
      }
    });
  }

  Future<void> _reloadConfiguration() async {
    try {
      final List<Object> result = await Future.wait<Object>(<Future<Object>>[
        _repository.srtRelays(),
        _repository.srtClients(),
      ]);
      _safeEmit(state.copyWith(
        status: LoadStatus.ready,
        relays: result[0] as List<SrtRelayView>,
        clients: result[1] as List<SrtClient>,
        error: '',
      ));
    } on Object catch (error) {
      _safeEmit(state.copyWith(error: '$error'));
    }
  }

  void _safeEmit(SrtState next) {
    if (!isClosed) {
      emit(next);
    }
  }

  @override
  Future<void> close() async {
    _discardPendingAudit();
    await _events?.cancel();
    return super.close();
  }
}

const Set<String> _configurationEvents = <String>{
  'srt_relay_saved',
  'srt_relay_deleted',
  'srt_client_saved',
  'srt_client_deleted',
  'srt_client_key_rotated',
};
