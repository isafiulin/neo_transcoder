#ifndef NEOTRANSCODER_SRT_BRIDGE_H
#define NEOTRANSCODER_SRT_BRIDGE_H

#include <stdint.h>

typedef struct NeoSRTStats {
    int64_t bytes_sent;
    int64_t packets_sent;
    int64_t packets_lost;
    int64_t packets_retrans;
    int64_t packets_dropped;
    int64_t bitrate_bps;
    double rtt_ms;
} NeoSRTStats;

int neo_srt_startup(char *error, int error_size);
void neo_srt_cleanup(void);
int neo_srt_listener_open(const char *bind_address, int port, int latency_ms,
                          int payload_size, int minimum_version, uintptr_t handle,
                          char *error, int error_size);
int neo_srt_caller_open(const char *destination_address, int port,
                        int latency_ms, int payload_size,
                        const char *stream_id, const char *passphrase,
                        char *error, int error_size);
int neo_srt_accept(int listener, char *remote_ip, int remote_ip_size,
                   int *remote_port, char *stream_id, int stream_id_size,
                   char *peer_version, int peer_version_size, int *encrypted,
                   char *error, int error_size);
int neo_srt_send(int socket, const char *data, int size,
                 char *error, int error_size);
int neo_srt_stats(int socket, NeoSRTStats *stats,
                  char *error, int error_size);
void neo_srt_close(int socket);

#endif
