#include "socket_scan.h"

#include <arpa/inet.h>
#include <libproc.h>
#include <stdlib.h>
#include <netinet/in.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/sysctl.h>

enum { PM_PROTO_TCP = 6, PM_PROTO_UDP = 17 };

static void write_addr(char *out, size_t out_len, int family, const void *addr_bytes) {
    if (family == AF_INET) {
        struct in_addr addr;
        memcpy(&addr, addr_bytes, sizeof(addr));
        inet_ntop(AF_INET, &addr, out, (socklen_t)out_len);
        return;
    }
    if (family == AF_INET6) {
        struct in6_addr addr;
        memcpy(&addr, addr_bytes, sizeof(addr));
        inet_ntop(AF_INET6, &addr, out, (socklen_t)out_len);
    }
}

static int append_socket(
    pm_socket_record *out,
    int capacity,
    int *count,
    uint32_t pid,
    uint8_t protocol,
    uint8_t tcp_state,
    int family,
    const struct in_sockinfo *sockinfo
) {
    if (*count >= capacity) {
        return 0;
    }
    pm_socket_record *record = &out[*count];
    memset(record, 0, sizeof(*record));
    record->pid = pid;
    record->protocol = protocol;
    record->tcp_state = tcp_state;

    uint8_t lbytes[4];
    uint8_t rbytes[4];
    memcpy(lbytes, &sockinfo->insi_lport, sizeof(sockinfo->insi_lport));
    memcpy(rbytes, &sockinfo->insi_fport, sizeof(sockinfo->insi_fport));
    uint16_t lport = (uint16_t)((lbytes[0] << 8) | lbytes[1]);
    uint16_t rport = (uint16_t)((rbytes[0] << 8) | rbytes[1]);
    record->local_port = lport;
    record->remote_port = rport;

    if (family == AF_INET) {
        write_addr(record->local_address, sizeof(record->local_address), AF_INET,
                   &sockinfo->insi_laddr.ina_46.i46a_addr4);
        write_addr(record->remote_address, sizeof(record->remote_address), AF_INET,
                   &sockinfo->insi_faddr.ina_46.i46a_addr4);
    } else if (family == AF_INET6) {
        write_addr(record->local_address, sizeof(record->local_address), AF_INET6,
                   &sockinfo->insi_laddr.ina_6);
        write_addr(record->remote_address, sizeof(record->remote_address), AF_INET6,
                   &sockinfo->insi_faddr.ina_6);
    }

    (*count)++;
    return 1;
}

static void scan_pid(
    pid_t pid,
    pm_socket_record *out,
    int capacity,
    int *count,
    int include_udp,
    int include_ipv6
) {
    int buffer_size =
        proc_pidinfo(pid, PROC_PIDLISTFDS, 0, NULL, 0);
    if (buffer_size <= 0) {
        return;
    }
    int fd_count = buffer_size / (int)sizeof(struct proc_fdinfo);
    struct proc_fdinfo *fds = calloc((size_t)fd_count, sizeof(struct proc_fdinfo));
    if (!fds) {
        return;
    }
    buffer_size = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, fds, buffer_size);
    if (buffer_size <= 0) {
        free(fds);
        return;
    }
    fd_count = buffer_size / (int)sizeof(struct proc_fdinfo);

    for (int i = 0; i < fd_count; i++) {
        if (fds[i].proc_fdtype != PROX_FDTYPE_SOCKET) {
            continue;
        }
        struct socket_fdinfo sinfo;
        int rc = proc_pidfdinfo(pid, fds[i].proc_fd, PROC_PIDFDSOCKETINFO, &sinfo, PROC_PIDFDSOCKETINFO_SIZE);
        if (rc <= 0) {
            continue;
        }
        int family = sinfo.psi.soi_family;
        if (family == AF_INET6 && !include_ipv6) {
            continue;
        }
        if (family != AF_INET && family != AF_INET6) {
            continue;
        }
        int kind = sinfo.psi.soi_kind;
        if (kind == SOCKINFO_TCP) {
            struct tcp_sockinfo tcp = sinfo.psi.soi_proto.pri_tcp;
            append_socket(out, capacity, count, (uint32_t)pid, PM_PROTO_TCP, (uint8_t)tcp.tcpsi_state, family,
                          &tcp.tcpsi_ini);
        } else if (include_udp && kind == SOCKINFO_IN) {
            struct in_sockinfo udp = sinfo.psi.soi_proto.pri_in;
            append_socket(out, capacity, count, (uint32_t)pid, PM_PROTO_UDP, 255, family, &udp);
        }
    }
    free(fds);
}

int pm_collect_sockets(
    pm_socket_record *out,
    int capacity,
    int include_udp,
    int include_ipv6
) {
    if (!out || capacity <= 0) {
        return 0;
    }
    int count = 0;
    int buffer_size = proc_listpids(PROC_ALL_PIDS, 0, NULL, 0);
    if (buffer_size <= 0) {
        return 0;
    }
    int pid_count = buffer_size / (int)sizeof(pid_t);
    pid_t *pids = calloc((size_t)pid_count, sizeof(pid_t));
    if (!pids) {
        return 0;
    }
    buffer_size = proc_listpids(PROC_ALL_PIDS, 0, pids, buffer_size);
    if (buffer_size <= 0) {
        free(pids);
        return 0;
    }
    pid_count = buffer_size / (int)sizeof(pid_t);
    for (int i = 0; i < pid_count; i++) {
        if (pids[i] <= 0) {
            continue;
        }
        scan_pid(pids[i], out, capacity, &count, include_udp, include_ipv6);
        if (count >= capacity) {
            break;
        }
    }
    free(pids);
    return count;
}
