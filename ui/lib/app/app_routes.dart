abstract final class AppRoutes {
  static const splash = '/splash';
  static const login = '/login';
  static const dashboard = '/';
  static const streams = '/streams';
  static const profiles = '/profiles';
  static const srt = '/srt';
  static const srtRelays = '/srt/relays';
  static const srtRelayNew = '/srt/relays/new';
  static String srtRelayEdit(String id) => '/srt/relays/$id/edit';
  static const srtClients = '/srt/clients';
  static const srtClientNew = '/srt/clients/new';
  static String srtClientEdit(String id) => '/srt/clients/$id/edit';
  static const srtSessions = '/srt/sessions';
  static const srtAudit = '/srt/audit';
  static const logs = '/logs';
  static const settings = '/settings';
}
