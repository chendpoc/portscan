#pragma once

#include <stdint.h>

typedef struct {
    uint32_t pid;
    uint8_t protocol; /* 6 tcp, 17 udp */
    uint8_t tcp_state; /* TCPSocketState or 255 for udp */
    uint16_t local_port;
    uint16_t remote_port;
    char local_address[64];
    char remote_address[64];
} pm_socket_record;

#ifdef __cplusplus
extern "C" {
#endif

int pm_collect_sockets(
    pm_socket_record *out,
    int capacity,
    int include_udp,
    int include_ipv6
);

#ifdef __cplusplus
}
#endif
