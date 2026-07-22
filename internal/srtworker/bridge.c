//go:build libsrt && cgo

#include "bridge.h"
#include "_cgo_export.h"

#include <arpa/inet.h>
#include <netdb.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>

#include <srt/srt.h>

static void copy_error(char *target, int size, const char *message) {
    if (target == NULL || size <= 0) {
        return;
    }
    snprintf(target, (size_t)size, "%s", message == NULL ? "unknown SRT error" : message);
}

static int set_option(SRTSOCKET socket, SRT_SOCKOPT option,
                      const void *value, int size,
                      char *error, int error_size) {
    if (srt_setsockopt(socket, 0, option, value, size) == SRT_ERROR) {
        copy_error(error, error_size, srt_getlasterror_str());
        return -1;
    }
    return 0;
}

static int listener_callback(void *opaque, SRTSOCKET socket, int handshake_version,
                             const struct sockaddr *peer, const char *stream_id) {
    char host[NI_MAXHOST] = {0};
    char service[NI_MAXSERV] = {0};
    socklen_t peer_size = peer->sa_family == AF_INET6
        ? (socklen_t)sizeof(struct sockaddr_in6)
        : (socklen_t)sizeof(struct sockaddr_in);
    if (getnameinfo(peer, peer_size, host, sizeof(host), service, sizeof(service),
                    NI_NUMERICHOST | NI_NUMERICSERV) != 0) {
        srt_setrejectreason(socket, SRT_REJC_PREDEFINED + 400);
        return -1;
    }

    char passphrase[80] = {0};
    int decision = goSRTAuthorize(
        (uintptr_t)opaque,
        socket,
        handshake_version,
        host,
        atoi(service),
        (char *)(stream_id == NULL ? "" : stream_id),
        passphrase,
        (int)sizeof(passphrase));
    if (decision != 0) {
        srt_setrejectreason(socket, SRT_REJC_PREDEFINED + decision);
        return -1;
    }

    if (passphrase[0] != '\0') {
        int enabled = 1;
        int key_length = 32;
        if (set_option(socket, SRTO_SENDER, &enabled, sizeof(enabled), NULL, 0) != 0 ||
            set_option(socket, SRTO_ENFORCEDENCRYPTION, &enabled, sizeof(enabled), NULL, 0) != 0 ||
            set_option(socket, SRTO_PBKEYLEN, &key_length, sizeof(key_length), NULL, 0) != 0 ||
            set_option(socket, SRTO_PASSPHRASE, passphrase, (int)strlen(passphrase), NULL, 0) != 0) {
            memset(passphrase, 0, sizeof(passphrase));
            srt_setrejectreason(socket, SRT_REJC_PREDEFINED + 500);
            return -1;
        }
    }
    memset(passphrase, 0, sizeof(passphrase));
    return 0;
}

int neo_srt_startup(char *error, int error_size) {
    if (srt_startup() == SRT_ERROR) {
        copy_error(error, error_size, srt_getlasterror_str());
        return -1;
    }
    srt_setloglevel(LOG_CRIT);
    return 0;
}

void neo_srt_cleanup(void) {
    srt_cleanup();
}

int neo_srt_listener_open(const char *bind_address, int port, int latency_ms,
                          int payload_size, int minimum_version, int enforce_encryption,
                          uintptr_t handle, char *error, int error_size) {
    SRTSOCKET socket = srt_create_socket();
    if (socket == SRT_INVALID_SOCK) {
        copy_error(error, error_size, srt_getlasterror_str());
        return -1;
    }

    int enabled = 1;
    SRT_TRANSTYPE transmission_type = SRTT_LIVE;
    if (set_option(socket, SRTO_SENDER, &enabled, sizeof(enabled), error, error_size) != 0 ||
        set_option(socket, SRTO_TRANSTYPE, &transmission_type, sizeof(transmission_type), error, error_size) != 0 ||
        set_option(socket, SRTO_PEERLATENCY, &latency_ms, sizeof(latency_ms), error, error_size) != 0 ||
        set_option(socket, SRTO_PAYLOADSIZE, &payload_size, sizeof(payload_size), error, error_size) != 0 ||
        set_option(socket, SRTO_MINVERSION, &minimum_version, sizeof(minimum_version), error, error_size) != 0 ||
        set_option(socket, SRTO_ENFORCEDENCRYPTION, &enforce_encryption, sizeof(enforce_encryption), error, error_size) != 0) {
        srt_close(socket);
        return -1;
    }

    char service[16];
    snprintf(service, sizeof(service), "%d", port);
    struct addrinfo hints;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_DGRAM;
    hints.ai_flags = AI_NUMERICHOST | AI_PASSIVE;
    struct addrinfo *addresses = NULL;
    int gai_error = getaddrinfo(bind_address, service, &hints, &addresses);
    if (gai_error != 0) {
        copy_error(error, error_size, gai_strerror(gai_error));
        srt_close(socket);
        return -1;
    }
    if (srt_bind(socket, addresses->ai_addr, (int)addresses->ai_addrlen) == SRT_ERROR) {
        copy_error(error, error_size, srt_getlasterror_str());
        freeaddrinfo(addresses);
        srt_close(socket);
        return -1;
    }
    freeaddrinfo(addresses);
    if (srt_listen_callback(socket, listener_callback, (void *)handle) == SRT_ERROR ||
        srt_listen(socket, 1024) == SRT_ERROR) {
        copy_error(error, error_size, srt_getlasterror_str());
        srt_close(socket);
        return -1;
    }
    return socket;
}

int neo_srt_caller_open(const char *destination_address, int port,
                        int latency_ms, int payload_size,
                        const char *stream_id, const char *passphrase,
                        char *error, int error_size) {
    SRTSOCKET socket = srt_create_socket();
    if (socket == SRT_INVALID_SOCK) {
        copy_error(error, error_size, srt_getlasterror_str());
        return -1;
    }
    int enabled = 1;
    int key_length = 32;
    int minimum_version = 0x010300;
    SRT_TRANSTYPE transmission_type = SRTT_LIVE;
    if (set_option(socket, SRTO_SENDER, &enabled, sizeof(enabled), error, error_size) != 0 ||
        set_option(socket, SRTO_TRANSTYPE, &transmission_type, sizeof(transmission_type), error, error_size) != 0 ||
        set_option(socket, SRTO_PEERLATENCY, &latency_ms, sizeof(latency_ms), error, error_size) != 0 ||
        set_option(socket, SRTO_PAYLOADSIZE, &payload_size, sizeof(payload_size), error, error_size) != 0 ||
        set_option(socket, SRTO_MINVERSION, &minimum_version, sizeof(minimum_version), error, error_size) != 0 ||
        set_option(socket, SRTO_STREAMID, stream_id, (int)strlen(stream_id), error, error_size) != 0) {
        srt_close(socket);
        return -1;
    }
    if (passphrase[0] != '\0' &&
        (set_option(socket, SRTO_PBKEYLEN, &key_length, sizeof(key_length), error, error_size) != 0 ||
         set_option(socket, SRTO_PASSPHRASE, passphrase, (int)strlen(passphrase), error, error_size) != 0)) {
        srt_close(socket);
        return -1;
    }
    char service[16];
    snprintf(service, sizeof(service), "%d", port);
    struct addrinfo hints;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_DGRAM;
    hints.ai_flags = AI_NUMERICHOST;
    struct addrinfo *addresses = NULL;
    int gai_error = getaddrinfo(destination_address, service, &hints, &addresses);
    if (gai_error != 0) {
        copy_error(error, error_size, gai_strerror(gai_error));
        srt_close(socket);
        return -1;
    }
    if (srt_connect(socket, addresses->ai_addr, (int)addresses->ai_addrlen) == SRT_ERROR) {
        copy_error(error, error_size, srt_getlasterror_str());
        freeaddrinfo(addresses);
        srt_close(socket);
        return -1;
    }
    freeaddrinfo(addresses);
    return socket;
}

int neo_srt_accept(int listener, char *remote_ip, int remote_ip_size,
                   int *remote_port, char *stream_id, int stream_id_size,
                   char *peer_version, int peer_version_size, int *encrypted,
                   char *error, int error_size) {
    struct sockaddr_storage peer;
    int peer_size = sizeof(peer);
    SRTSOCKET socket = srt_accept(listener, (struct sockaddr *)&peer, &peer_size);
    if (socket == SRT_INVALID_SOCK) {
        copy_error(error, error_size, srt_getlasterror_str());
        return -1;
    }
    char service[NI_MAXSERV] = {0};
    if (getnameinfo((struct sockaddr *)&peer, (socklen_t)peer_size,
                    remote_ip, (socklen_t)remote_ip_size,
                    service, sizeof(service),
                    NI_NUMERICHOST | NI_NUMERICSERV) != 0) {
        copy_error(error, error_size, "cannot resolve accepted SRT peer address");
        srt_close(socket);
        return -1;
    }
    *remote_port = atoi(service);

    int stream_size = stream_id_size - 1;
    if (srt_getsockopt(socket, 0, SRTO_STREAMID, stream_id, &stream_size) == SRT_ERROR) {
        stream_id[0] = '\0';
    } else {
        stream_id[stream_size] = '\0';
    }
    int version = 0;
    int version_size = sizeof(version);
    if (srt_getsockopt(socket, 0, SRTO_PEERVERSION, &version, &version_size) == SRT_ERROR) {
        version = 0;
    }
    snprintf(peer_version, (size_t)peer_version_size, "%d.%d.%d",
             (version >> 16) & 0xff, (version >> 8) & 0xff, version & 0xff);
    int key_state = SRT_KM_S_UNSECURED;
    int key_state_size = sizeof(key_state);
    if (srt_getsockopt(socket, 0, SRTO_KMSTATE, &key_state, &key_state_size) == SRT_ERROR) {
        key_state = SRT_KM_S_UNSECURED;
    }
    *encrypted = key_state == SRT_KM_S_SECURED;
    return socket;
}

int neo_srt_send(int socket, const char *data, int size,
                 char *error, int error_size) {
    int sent = srt_sendmsg(socket, data, size, -1, 1);
    if (sent == SRT_ERROR || sent != size) {
        copy_error(error, error_size, srt_getlasterror_str());
        return -1;
    }
    return 0;
}

int neo_srt_stats(int socket, NeoSRTStats *stats,
                  char *error, int error_size) {
    SRT_TRACEBSTATS source;
    memset(&source, 0, sizeof(source));
    if (srt_bstats(socket, &source, 0) == SRT_ERROR) {
        copy_error(error, error_size, srt_getlasterror_str());
        return -1;
    }
    stats->bytes_sent = (int64_t)source.byteSentUniqueTotal;
    stats->packets_sent = source.pktSentUniqueTotal;
    stats->packets_lost = source.pktSndLossTotal;
    stats->packets_retrans = source.pktRetransTotal;
    stats->packets_dropped = source.pktSndDropTotal;
    stats->bitrate_bps = (int64_t)(source.mbpsSendRate * 1000000.0);
    stats->rtt_ms = source.msRTT;
    return 0;
}

void neo_srt_close(int socket) {
    if (socket != SRT_INVALID_SOCK) {
        srt_close(socket);
    }
}
