#include "PcapWatcher.h"

/* standard libpcap sniffing structures */
#define ETHER_ADDR_LEN	6

/* Ethernet header */
struct sniff_ethernet {
    u_char ether_dhost[ETHER_ADDR_LEN]; /* Destination host address */
    u_char ether_shost[ETHER_ADDR_LEN]; /* Source host address */
    u_short ether_type; /* IP? ARP? RARP? etc */
};

/* IP header */
struct sniff_ip {
    u_char ip_vhl;		/* version << 4 | header length >> 2 */
    u_char ip_tos;		/* type of service */
    u_short ip_len;		/* total length */
    u_short ip_id;		/* identification */
    u_short ip_off;		/* fragment offset field */
#define IP_RF 0x8000		/* reserved fragment flag */
#define IP_DF 0x4000		/* dont fragment flag */
#define IP_MF 0x2000		/* more fragments flag */
#define IP_OFFMASK 0x1fff	/* mask for fragmenting bits */
    u_char ip_ttl;		/* time to live */
    u_char ip_p;		/* protocol */
    u_short ip_sum;		/* checksum */
    struct in_addr ip_src,ip_dst; /* source and dest address */
};
#define IP_HL(ip)		(((ip)->ip_vhl) & 0x0f)
#define IP_V(ip)		(((ip)->ip_vhl) >> 4)

/* IPv6 header */
struct sniff_ipv6 {
    uint32_t        ip_vtcfl;   /* version << 4 then traffic class and flow label */
    uint16_t        ip_len;     /* payload length */
    uint8_t         ip_nxt;     /* next header (protocol) */
    uint8_t         ip_hopl;    /* hop limit (ttl) */
    struct in6_addr ip_src, ip_dst;     /* source and dest address */
};
#define IPV6_VERSION(ip)          (ntohl((ip)->ip_vtcfl) >> 28)

/* TCP header */
struct sniff_tcp {
    u_short th_sport;	/* source port */
    u_short th_dport;	/* destination port */
    tcp_seq th_seq;		/* sequence number */
    tcp_seq th_ack;		/* acknowledgement number */

    u_char th_offx2;	/* data offset, rsvd */
#define TH_OFF(th)	(((th)->th_offx2 & 0xf0) >> 4)
    u_char th_flags;
#define TH_FIN 0x01
#define TH_SYN 0x02
#define TH_RST 0x04
#define TH_PUSH 0x08
#define TH_ACK 0x10
#define TH_URG 0x20
#define TH_ECE 0x40
#define TH_CWR 0x80
#define TH_FLAGS (TH_FIN|TH_SYN|TH_RST|TH_ACK|TH_URG|TH_ECE|TH_CWR)
    u_short th_win;		/* window */
    u_short th_sum;		/* checksum */
    u_short th_urp;		/* urgent pointer */
};

struct sniff_udp {
    u_short udp_sport; /* source port */
    u_short udp_dport; /* destination port */
    u_short udp_hlen;	 /* Udp header length*/
    u_short udp_chksum;	 /* Udp Checksum */
};

PcapWatcher::PcapWatcher(QObject *parent) :
    QObject(parent), m_filterString("port 53"), m_deviceName(""), m_pcapHandle(0)
{
}

QString PcapWatcher::deviceName()
{
    return m_deviceName;
}

void PcapWatcher::setDeviceName(const QString &deviceName)
{
    m_deviceName = deviceName;
}

void PcapWatcher::openDevice()
{
    bpf_u_int32 mask, net;

    closeDevice();

    if (pcap_lookupnet(m_deviceName.toAscii().data(), &net, &mask, m_errorBuffer)) {
        emit failedToOpenDevice(tr("could not get netmask for device: %s").arg(m_deviceName));
        return;
    }

    m_pcapHandle = pcap_open_live(m_deviceName.toAscii().data(), BUFSIZ, 1, 1000, m_errorBuffer);
    if (!m_pcapHandle) {
        // TODO: do something on error
        emit failedToOpenDevice(QString(m_errorBuffer));
        return;
    }

    if (m_filterString.length() > 0) {
        if (pcap_compile(m_pcapHandle, &m_filterCompiled, m_filterString.toAscii().data(), 1, mask) < -1) {
            emit failedToOpenDevice(tr("failed to parse the filter: %s").arg(pcap_geterr(m_pcapHandle)));
            return;
        }
    }

    if (pcap_setfilter(m_pcapHandle, &m_filterCompiled) < -1) {
        emit failedToOpenDevice(tr("failed to install the filter: %s").arg(pcap_geterr(m_pcapHandle)));
        return;
    }
}

void PcapWatcher::closeDevice()
{
    if (m_pcapHandle) {
        pcap_close(m_pcapHandle);
        m_pcapHandle = 0;
    }
}
