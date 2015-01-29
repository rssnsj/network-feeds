/*
 *  nat64.c -- IPv4/IPv6 header rewriting routines
 *
 *  part of TAYGA <http://www.litech.org/tayga/>
 *  Copyright (C) 2010  Nathan Lutchansky <lutchann@litech.org>
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 */

#include <linux/ip.h>
#include <linux/ipv6.h>

#include "tayga.h"

static inline u16 swap_u16(u16 val) 
{
	return (val << 8) | (val >> 8);
}

static inline u32 swap_u32(u32 val)
{
	val = ((val << 8) & 0xff00ff00) | ((val >> 8) & 0xff00ff); 
	return (val << 16) | (val >> 16);
}

static u16 ip_checksum(void *d, int c)
{
	u32 sum = 0xffff;
	u16 *p = d;

	while (c > 1) {
		sum += swap_u16(ntohs(*p++));
		c -= 2;
	}

	if (c)
		sum += swap_u16(*((u8 *)p) << 8);

	while (sum > 0xffff)
		sum = (sum & 0xffff) + (sum >> 16);

	return ~sum;
}

static u16 ones_add(u16 a, u16 b)
{
	u32 sum = (u16)~a + (u16)~b;

	return ~((sum & 0xffff) + (sum >> 16));
}

static u16 ip6_checksum(struct ip6 *ip6, u32 data_len, u8 proto)
{
	u32 sum = 0;
	u16 *p;
	int i;

	for (i = 0, p = ip6->src.s6_addr16; i < 16; ++i)
		sum += swap_u16(ntohs(*p++));
	sum += swap_u32(data_len) >> 16;
	sum += swap_u32(data_len) & 0xffff;
	sum += swap_u16(proto);

	while (sum > 0xffff)
		sum = (sum & 0xffff) + (sum >> 16);

	return ~sum;
}

static u16 convert_cksum(struct ip6 *ip6, struct ip4 *ip4)
{
	u32 sum = 0;
	u16 *p;
	int i;

	sum += ~ip4->src.s_addr >> 16;
	sum += ~ip4->src.s_addr & 0xffff;
	sum += ~ip4->dest.s_addr >> 16;
	sum += ~ip4->dest.s_addr & 0xffff;

	for (i = 0, p = ip6->src.s6_addr16; i < 16; ++i)
		sum += *p++;

	while (sum > 0xffff)
		sum = (sum & 0xffff) + (sum >> 16);

	return sum;
}

static u16 select_ip4_ipid(void)
{
	static DEFINE_SPINLOCK(ipid_lock);
	static u32 offset = 0;
	u32 ipid;
	
	spin_lock_bh(&ipid_lock);
	ipid = gcfg.rand[0] + offset++;
	spin_unlock_bh(&ipid_lock);
	return htons(ipid & 0xffff);
}

static void host_send_icmp4(u8 tos, struct in_addr *src,
		struct in_addr *dest, struct icmp *icmp,
		u8 *data, int data_len, struct net_device *dev)
{
	struct {
		struct ip4 ip4;
		struct icmp icmp;
	} __attribute__ ((__packed__)) header;
	struct sk_buff *skb;

	header.ip4.ver_ihl = 0x45;
	header.ip4.tos = tos;
	header.ip4.length = htons(sizeof(header.ip4) + sizeof(header.icmp) +
				data_len);
	header.ip4.ident = select_ip4_ipid();
	header.ip4.flags_offset = 0;
	header.ip4.ttl = 64;
	header.ip4.proto = 1;
	header.ip4.cksum = 0;
	header.ip4.src = *src;
	header.ip4.dest = *dest;
	header.ip4.cksum = htons(swap_u16(ip_checksum(&header.ip4, sizeof(header.ip4))));
	header.icmp = *icmp;
	header.icmp.cksum = 0;
	header.icmp.cksum = htons(swap_u16(ones_add(ip_checksum(data, data_len),
			ip_checksum(&header.icmp, sizeof(header.icmp)))));

	skb = netdev_alloc_skb(dev, sizeof(header) + data_len);
	if (!skb) {
		dev->stats.rx_dropped++;
		return;
	}
	memcpy(skb_put(skb, sizeof(header)), &header, sizeof(header));
	memcpy(skb_put(skb, data_len), data, data_len);
	skb->protocol = htons(ETH_P_IP);

	dev->stats.rx_bytes += skb->len;
	dev->stats.rx_packets++;
	netif_rx(skb);
}

static void host_send_icmp4_error(u8 type, u8 code, u32 word,
		struct pkt *orig)
{
	struct icmp icmp;
	int orig_len;

	/* Don't send ICMP errors in response to ICMP messages other than
	   echo request */
	if (orig->data_proto == 1 && orig->icmp->type != 8)
		return;

	orig_len = orig->header_len + orig->data_len;
	if (orig_len > 576 - sizeof(struct ip4) - sizeof(struct icmp))
		orig_len = 576 - sizeof(struct ip4) - sizeof(struct icmp);
	icmp.type = type;
	icmp.code = code;
	icmp.word = htonl(word);
	host_send_icmp4(0, &gcfg.local_addr4, &orig->ip4->src, &icmp,
			(u8 *)orig->ip4, orig_len, orig->dev);
}

static void host_handle_icmp4(struct pkt *p)
{
	p->data += sizeof(struct icmp);
	p->data_len -= sizeof(struct icmp);

	switch (p->icmp->type) {
	case 8:
		p->icmp->type = 0;
		host_send_icmp4(p->ip4->tos, &p->ip4->dest, &p->ip4->src,
				p->icmp, p->data, p->data_len, p->dev);
		break;
	}
}

static void xlate_header_4to6(struct pkt *p, struct ip6 *ip6,
		int payload_length)
{
	ip6->ver_tc_fl = htonl((0x6 << 28) | (p->ip4->tos << 20));
	ip6->payload_length = htons(payload_length);
	ip6->next_header = p->data_proto == 1 ? 58 : p->data_proto;
	ip6->hop_limit = p->ip4->ttl;
}

static int xlate_payload_4to6(struct pkt *p, struct ip6 *ip6)
{
	u16 *tck;
	u16 cksum;

	if (p->ip4->flags_offset & htons(IP4_F_MASK))
		return 0;

	switch (p->data_proto) {
	case 1:
		cksum = ip6_checksum(ip6, ntohs(p->ip4->length) -
						p->header_len, 58);
		cksum = ones_add(swap_u16(ntohs(p->icmp->cksum)), cksum);
		if (p->icmp->type == 8) {
			p->icmp->type = 128;
			p->icmp->cksum = htons(swap_u16(ones_add(cksum, ~(128 - 8))));
		} else {
			p->icmp->type = 129;
			p->icmp->cksum = htons(swap_u16(ones_add(cksum, ~(129 - 0))));
		}
		return 0;
	case 17:
		if (p->data_len < 8)
			return -1;
		tck = (u16 *)(p->data + 6);
		if (!*tck)
			return -1; /* drop UDP packets with no checksum */
		break;
	case 6:
		if (p->data_len < 20)
			return -1;
		tck = (u16 *)(p->data + 16);
		break;
	default:
		return 0;
	}
	*tck = ones_add(*tck, ~convert_cksum(ip6, p->ip4));
	return 0;
}

static void xlate_4to6_data(struct pkt *p)
{
	struct {
		struct ip6 ip6;
		struct ip6_frag ip6_frag;
	} __attribute__ ((__packed__)) header;
	struct sk_buff *skb = p->skb, *new_skb;
	int no_frag_hdr = 0;
	u16 off = ntohs(p->ip4->flags_offset);
	int frag_size;

	frag_size = gcfg.ipv6_offlink_mtu;
	if (frag_size > gcfg.mtu)
		frag_size = gcfg.mtu;
	frag_size -= sizeof(struct ip6);

	if (map_ip4_to_ip6(&header.ip6.dest, &p->ip4->dest)) {
		host_send_icmp4_error(3, 1, 0, p);
		goto drop_skb;
	}

	if (map_ip4_to_ip6(&header.ip6.src, &p->ip4->src)) {
		host_send_icmp4_error(3, 10, 0, p);
		goto drop_skb;
	}

	/* We do not respect the DF flag for IP4 packets that are already
	   fragmented, because the IP6 fragmentation header takes an extra
	   eight bytes, which we don't have space for because the IP4 source
	   thinks the MTU is only 20 bytes smaller than the actual MTU on
	   the IP6 side.  (E.g. if the IP6 MTU is 1496, the IP4 source thinks
	   the path MTU is 1476, which means it sends fragments with 1456
	   bytes of fragmented payload.  Translating this to IP6 requires
	   40 bytes of IP6 header + 8 bytes of fragmentation header +
	   1456 bytes of payload == 1504 bytes.) */
	if ((off & (IP4_F_MASK | IP4_F_MF)) == 0) {
		if (off & IP4_F_DF) {
			if (gcfg.mtu - MTU_ADJ < p->header_len + p->data_len) {
				host_send_icmp4_error(3, 4,
						gcfg.mtu - MTU_ADJ, p);
				goto drop_skb;
			}
			no_frag_hdr = 1;
		} else if (gcfg.lazy_frag_hdr && p->data_len <= frag_size) {
			no_frag_hdr = 1;
		}
	}

	xlate_header_4to6(p, &header.ip6, p->data_len);
	--header.ip6.hop_limit;

	if (xlate_payload_4to6(p, &header.ip6) < 0)
		goto drop_skb;

	//if (src)
	//	src->flags |= CACHE_F_SEEN_4TO6;
	//if (dest)
	//	dest->flags |= CACHE_F_SEEN_4TO6;

	if (no_frag_hdr) {
		size_t push_len = (skb->data - (p->data - sizeof(header.ip6)));

		if (skb_headroom(skb) < push_len) {
			struct sk_buff *new_skb = skb_realloc_headroom(skb, push_len);
			if (!new_skb) {
				p->dev->stats.rx_dropped++;
				goto drop_skb;
			}
			kfree_skb(skb);
			skb = new_skb;
		}

		skb_push(skb, push_len);
		skb_reset_network_header(skb);
		memcpy(ipv6_hdr(skb), &header.ip6, sizeof(header.ip6));
		skb->protocol = htons(ETH_P_IPV6);
		skb->dev = p->dev;

		p->dev->stats.rx_bytes += skb->len;
		p->dev->stats.rx_packets++;
		netif_rx(skb);
	} else {
		header.ip6_frag.next_header = header.ip6.next_header;
		header.ip6_frag.reserved = 0;
		header.ip6_frag.ident = htonl(ntohs(p->ip4->ident));

		header.ip6.next_header = 44;

		off = (off & IP4_F_MASK) * 8;
		frag_size = (frag_size - sizeof(header.ip6_frag)) & ~7;

		while (p->data_len > 0) {
			if (p->data_len < frag_size)
				frag_size = p->data_len;

			header.ip6.payload_length =
				htons(sizeof(struct ip6_frag) + frag_size);
			header.ip6_frag.offset_flags = htons(off);

			p->data += frag_size;
			p->data_len -= frag_size;
			off += frag_size;

			if (p->data_len || (p->ip4->flags_offset &
							htons(IP4_F_MF)))
				header.ip6_frag.offset_flags |= htons(IP6_F_MF);

			new_skb = netdev_alloc_skb(p->dev, sizeof(header) + frag_size);
			if (!new_skb) {
				p->dev->stats.rx_dropped++;
				break;
			}
			memcpy(skb_put(new_skb, sizeof(header)), &header, sizeof(header));
			memcpy(skb_put(new_skb, frag_size), p->data, frag_size);
			new_skb->protocol = htons(ETH_P_IPV6);

			p->dev->stats.rx_bytes += new_skb->len;
			p->dev->stats.rx_packets++;
			netif_rx(new_skb);
		}

		kfree_skb(skb);
	}

	return;

drop_skb:
	kfree_skb(skb);
}

static int parse_ip4(struct pkt *p)
{
	p->ip4 = (struct ip4 *)(p->data);

	if (p->data_len < sizeof(struct ip4))
		return -1;

	p->header_len = (p->ip4->ver_ihl & 0x0f) * 4;

	if ((p->ip4->ver_ihl >> 4) != 4 || p->header_len < sizeof(struct ip4) ||
			p->data_len < p->header_len ||
			ntohs(p->ip4->length) < p->header_len ||
			validate_ip4_addr(&p->ip4->src) ||
			validate_ip4_addr(&p->ip4->dest))
		return -1;

	if (p->data_len > ntohs(p->ip4->length))
		p->data_len = ntohs(p->ip4->length);

	p->data += p->header_len;
	p->data_len -= p->header_len;
	p->data_proto = p->ip4->proto;

	if (p->data_proto == 1) {
		if (p->ip4->flags_offset & htons(IP4_F_MASK | IP4_F_MF))
			return -1; /* fragmented ICMP is unsupported */
		if (p->data_len < sizeof(struct icmp))
			return -1;
		p->icmp = (struct icmp *)(p->data);
	} else {
		if ((p->ip4->flags_offset & htons(IP4_F_MF)) &&
				(p->data_len & 0x7))
			return -1;

		if ((u32)((ntohs(p->ip4->flags_offset) & IP4_F_MASK) * 8) +
				p->data_len > 65535)
			return -1;
	}

	return 0;
}

/* Estimates the most likely MTU of the link that the datagram in question was
 * too large to fit through, using the algorithm from RFC 1191. */
static unsigned int est_mtu(unsigned int too_big)
{
	static const unsigned int table[] = {
		65535, 32000, 17914, 8166, 4352, 2002, 1492, 1006, 508, 296, 0
	};
	int i;

	for (i = 0; table[i]; ++i)
		if (too_big > table[i])
			return table[i];
	return 68;
}

static void xlate_4to6_icmp_error(struct pkt *p)
{
	struct {
		struct ip6 ip6;
		struct icmp icmp;
		struct ip6 ip6_em;
	} __attribute__ ((__packed__)) header;
	struct sk_buff *skb;
	struct pkt p_em;
	u32 mtu;
	u16 em_len;
	int allow_fake_source = 0;
	//struct cache_entry *orig_dest = NULL;

	memset(&p_em, 0, sizeof(p_em));
	p_em.data = p->data + sizeof(struct icmp);
	p_em.data_len = p->data_len - sizeof(struct icmp);

	if (p->icmp->type == 3 || p->icmp->type == 11 || p->icmp->type == 12) {
		em_len = (ntohl(p->icmp->word) >> 14) & 0x3fc;
		if (em_len) {
			if (p_em.data_len < em_len)
				return;
			p_em.data_len = em_len;
		}
	}

	if (parse_ip4(&p_em) < 0)
		return;

	if (p_em.data_proto == 1 && p_em.icmp->type != 8)
		return;

	if (sizeof(struct ip6) * 2 + sizeof(struct icmp) + p_em.data_len > 1280)
		p_em.data_len = 1280 - sizeof(struct ip6) * 2 -
						sizeof(struct icmp);

	if (map_ip4_to_ip6(&header.ip6_em.src, &p_em.ip4->src) ||
		map_ip4_to_ip6(&header.ip6_em.dest, &p_em.ip4->dest))
		return;

	xlate_header_4to6(&p_em, &header.ip6_em,
				ntohs(p_em.ip4->length) - p_em.header_len);

	switch (p->icmp->type) {
	case 3: /* Destination Unreachable */
		header.icmp.type = 1; /* Destination Unreachable */
		header.icmp.word = 0;
		switch (p->icmp->code) {
		case 0: /* Network Unreachable */
		case 1: /* Host Unreachable */
		case 5: /* Source Route Failed */
		case 6:
		case 7:
		case 8:
		case 11:
		case 12:
			header.icmp.code = 0; /* No route to destination */
			allow_fake_source = 1;
			break;
		case 2: /* Protocol Unreachable */
			header.icmp.type = 4;
			header.icmp.code = 1;
			header.icmp.word = htonl(6);
			break;
		case 3: /* Port Unreachable */
			header.icmp.code = 4; /* Port Unreachable */
			break;
		case 4: /* Fragmentation needed and DF set */
			header.icmp.type = 2;
			header.icmp.code = 0;
			mtu = ntohl(p->icmp->word) & 0xffff;
			if (mtu < 68)
				mtu = est_mtu(ntohs(p_em.ip4->length));
			mtu += MTU_ADJ;
			if (mtu > gcfg.mtu)
				mtu = gcfg.mtu;
			//if (mtu < 1280 && gcfg.allow_ident_gen && orig_dest) {
			//	orig_dest->flags |= CACHE_F_GEN_IDENT;
			//	mtu = 1280;
			//}
			header.icmp.word = htonl(mtu);
			allow_fake_source = 1;
			break;
		case 9:
		case 10:
		case 13:
		case 15:
			header.icmp.code = 1; /* Administratively prohibited */
			break;
		default:
			return;
		}
		break;
	case 11: /* Time Exceeded */
		header.icmp.type = 3; /* Time Exceeded */
		header.icmp.code = p->icmp->code;
		header.icmp.word = 0;
		break;
	case 12: /* Parameter Problem */
		if (p->icmp->code != 0 && p->icmp->code != 2)
			return;
		header.icmp.type = 4;
		header.icmp.code = 0;
		/* XXX do this and remove return */
		return;
	default:
		return;
	}

	if (xlate_payload_4to6(&p_em, &header.ip6_em) < 0)
		return;

	if (map_ip4_to_ip6(&header.ip6.src, &p->ip4->src)) {
		if (allow_fake_source)
			header.ip6.src = gcfg.local_addr6;
		else
			return;
	}

	if (map_ip4_to_ip6(&header.ip6.dest, &p->ip4->dest))
		return;

	xlate_header_4to6(p, &header.ip6,
		sizeof(header.icmp) + sizeof(header.ip6_em) + p_em.data_len);
	--header.ip6.hop_limit;

	header.icmp.cksum = 0;
	header.icmp.cksum = htons(swap_u16(ones_add(ip6_checksum(&header.ip6,
					ntohs(header.ip6.payload_length), 58),
			ones_add(ip_checksum(&header.icmp,
						sizeof(header.icmp) +
						sizeof(header.ip6_em)),
				ip_checksum(p_em.data, p_em.data_len)))));

	skb = netdev_alloc_skb(p->dev, sizeof(header) + p_em.data_len);
	if (!skb) {
		p->dev->stats.rx_dropped++;
		kfree_skb(skb);
		return;
	}
	memcpy(skb_put(skb, sizeof(header)), &header, sizeof(header));
	memcpy(skb_put(skb, p_em.data_len), p_em.data, p_em.data_len);
	skb->protocol = htons(ETH_P_IPV6);

	p->dev->stats.rx_bytes += skb->len;
	p->dev->stats.rx_packets++;
	netif_rx(skb);
}

void handle_ip4(struct pkt *p)
{
	if (parse_ip4(p) < 0 || p->ip4->ttl == 0 ||
		ip_checksum(p->ip4, p->header_len) ||
		p->header_len + p->data_len != ntohs(p->ip4->length)) {
		p->dev->stats.tx_dropped++;
		kfree_skb(p->skb);
		return;
	}

	if (p->icmp && ip_checksum(p->data, p->data_len)) {
		p->dev->stats.tx_dropped++;
		kfree_skb(p->skb);
		return;
	}

	p->dev->stats.tx_bytes += p->skb->len;
	p->dev->stats.tx_packets++;

	if (p->ip4->dest.s_addr == gcfg.local_addr4.s_addr) {
		if (p->data_proto == 1)
			host_handle_icmp4(p);
		else
			host_send_icmp4_error(3, 2, 0, p);
		kfree_skb(p->skb);
	} else {
		if (p->ip4->ttl == 1) {
			host_send_icmp4_error(11, 0, 0, p);
			kfree_skb(p->skb);
			return;
		}
		if (p->data_proto != 1 || p->icmp->type == 8 ||
				p->icmp->type == 0)
			xlate_4to6_data(p);
		else
			xlate_4to6_icmp_error(p);
	}
}

static void host_send_icmp6(u8 tc, struct in6_addr *src,
		struct in6_addr *dest, struct icmp *icmp,
		u8 *data, int data_len, struct net_device *dev)
{
	struct {
		struct ip6 ip6;
		struct icmp icmp;
	} __attribute__ ((__packed__)) header;
	struct sk_buff *skb;

	header.ip6.ver_tc_fl = htonl((0x6 << 28) | (tc << 20));
	header.ip6.payload_length = htons(sizeof(header.icmp) + data_len);
	header.ip6.next_header = 58;
	header.ip6.hop_limit = 64;
	header.ip6.src = *src;
	header.ip6.dest = *dest;
	header.icmp = *icmp;
	header.icmp.cksum = 0;
	header.icmp.cksum = htons(swap_u16(ones_add(ip_checksum(data, data_len),
			ip_checksum(&header.icmp, sizeof(header.icmp)))));
	header.icmp.cksum = htons(swap_u16(ones_add(swap_u16(ntohs(header.icmp.cksum)),
			ip6_checksum(&header.ip6,
					data_len + sizeof(header.icmp), 58))));

	skb = netdev_alloc_skb(dev, sizeof(header) + data_len);
	if (!skb) {
		dev->stats.rx_dropped++;
		return;
	}
	memcpy(skb_put(skb, sizeof(header)), &header, sizeof(header));
	memcpy(skb_put(skb, data_len), data, data_len);
	skb->protocol = htons(ETH_P_IPV6);
	
	dev->stats.rx_bytes += skb->len;
	dev->stats.rx_packets++;
	netif_rx(skb);
}

static void host_send_icmp6_error(u8 type, u8 code, u32 word,
				struct pkt *orig)
{
	struct icmp icmp;
	int orig_len;

	/* Don't send ICMP errors in response to ICMP messages other than
	   echo request */
	if (orig->data_proto == 58 && orig->icmp->type != 128)
		return;

	orig_len = sizeof(struct ip6) + orig->header_len + orig->data_len;
	if (orig_len > 1280 - sizeof(struct ip6) - sizeof(struct icmp))
		orig_len = 1280 - sizeof(struct ip6) - sizeof(struct icmp);
	icmp.type = type;
	icmp.code = code;
	icmp.word = htonl(word);
	host_send_icmp6(0, &gcfg.local_addr6, &orig->ip6->src, &icmp,
			(u8 *)orig->ip6, orig_len, orig->dev);
}

static void host_handle_icmp6(struct pkt *p)
{
	p->data += sizeof(struct icmp);
	p->data_len -= sizeof(struct icmp);

	switch (p->icmp->type) {
	case 128:
		p->icmp->type = 129;
		host_send_icmp6((ntohl(p->ip6->ver_tc_fl) >> 20) & 0xff,
				&p->ip6->dest, &p->ip6->src,
				p->icmp, p->data, p->data_len, p->dev);
		break;
	}
}

static void xlate_header_6to4(struct pkt *p, struct ip4 *ip4,
		int payload_length)
{
	ip4->ver_ihl = 0x45;
	ip4->tos = (ntohl(p->ip6->ver_tc_fl) >> 20) & 0xff;
	ip4->length = htons(sizeof(struct ip4) + payload_length);
	if (p->ip6_frag) {
		ip4->ident = htons(ntohl(p->ip6_frag->ident) & 0xffff);
		ip4->flags_offset =
			htons(ntohs(p->ip6_frag->offset_flags) >> 3);
		if (p->ip6_frag->offset_flags & htons(IP6_F_MF))
			ip4->flags_offset |= htons(IP4_F_MF);
	} /* else if (dest && (dest->flags & CACHE_F_GEN_IDENT) &&
			p->header_len + payload_length <= 1280) {
		ip4->ident = htons(dest->ip4_ident++);
		ip4->flags_offset = 0;
		if (dest->ip4_ident == 0)
			dest->ip4_ident++;
	} */ else {
		ip4->ident = select_ip4_ipid();
		ip4->flags_offset = htons(IP4_F_DF);
	}
	ip4->ttl = p->ip6->hop_limit;
	ip4->proto = p->data_proto == 58 ? 1 : p->data_proto;
	ip4->cksum = 0;
}

static int xlate_payload_6to4(struct pkt *p, struct ip4 *ip4)
{
	u16 *tck;
	u16 cksum;

	if (p->ip6_frag && (p->ip6_frag->offset_flags & ntohs(IP6_F_MASK)))
		return 0;

	switch (p->data_proto) {
	case 58:
		cksum = ~ip6_checksum(p->ip6, ntohs(p->ip6->payload_length) -
							p->header_len, 58);
		cksum = ones_add(swap_u16(ntohs(p->icmp->cksum)), cksum);
		if (p->icmp->type == 128) {
			p->icmp->type = 8;
			p->icmp->cksum = htons(swap_u16(ones_add(cksum, 128 - 8)));
		} else {
			p->icmp->type = 0;
			p->icmp->cksum = htons(swap_u16(ones_add(cksum, 129 - 0)));
		}
		return 0;
	case 17:
		if (p->data_len < 8)
			return -1;
		tck = (u16 *)(p->data + 6);
		if (!*tck)
			return -1; /* drop UDP packets with no checksum */
		break;
	case 6:
		if (p->data_len < 20)
			return -1;
		tck = (u16 *)(p->data + 16);
		break;
	default:
		return 0;
	}
	*tck = ones_add(*tck, convert_cksum(p->ip6, ip4));
	return 0;
}

static void xlate_6to4_data(struct pkt *p)
{
	struct {
		struct ip4 ip4;
	} __attribute__ ((__packed__)) header;
	struct sk_buff *skb = p->skb;

	if (map_ip6_to_ip4(&header.ip4.dest, &p->ip6->dest, 0)) {
		host_send_icmp6_error(1, 0, 0, p);
		kfree_skb(skb);
		return;
	}

	if (map_ip6_to_ip4(&header.ip4.src, &p->ip6->src, 1)) {
		host_send_icmp6_error(1, 5, 0, p);
		kfree_skb(skb);
		return;
	}

	if (sizeof(struct ip6) + p->header_len + p->data_len > gcfg.mtu) {
		host_send_icmp6_error(2, 0, gcfg.mtu, p);
		kfree_skb(skb);
		return;
	}

	xlate_header_6to4(p, &header.ip4, p->data_len);
	--header.ip4.ttl;

	if (xlate_payload_6to4(p, &header.ip4) < 0) {
		kfree_skb(skb);
		return;
	}

	header.ip4.cksum = htons(swap_u16(ip_checksum(&header.ip4, sizeof(header.ip4))));

	skb_pull(skb, (unsigned)(p->data - sizeof(header) - skb->data));
	skb->protocol = htons(ETH_P_IP);
	skb_reset_network_header(skb);
	memcpy(ip_hdr(skb), &header, sizeof(header));
	skb->dev = p->dev;

	p->dev->stats.rx_bytes += skb->len;
	p->dev->stats.rx_packets++;
	netif_rx(skb);
}

static int parse_ip6(struct pkt *p)
{
	int hdr_len;

	p->ip6 = (struct ip6 *)(p->data);

	if (p->data_len < sizeof(struct ip6) ||
			(ntohl(p->ip6->ver_tc_fl) >> 28) != 6 ||
			validate_ip6_addr(&p->ip6->src) ||
			validate_ip6_addr(&p->ip6->dest))
		return -1;

	p->data_proto = p->ip6->next_header;
	p->data += sizeof(struct ip6);
	p->data_len -= sizeof(struct ip6);

	if (p->data_len > ntohs(p->ip6->payload_length))
		p->data_len = ntohs(p->ip6->payload_length);

	while (p->data_proto == 0 || p->data_proto == 43 ||
			p->data_proto == 60) {
		if (p->data_len < 2)
			return -1;
		hdr_len = (p->data[1] + 1) * 8;
		if (p->data_len < hdr_len)
			return -1;
		p->data_proto = p->data[0];
		p->data += hdr_len;
		p->data_len -= hdr_len;
		p->header_len += hdr_len;
	}

	if (p->data_proto == 44) {
		if (p->ip6_frag || p->data_len < sizeof(struct ip6_frag))
			return -1;
		p->ip6_frag = (struct ip6_frag *)p->data;
		p->data_proto = p->ip6_frag->next_header;
		p->data += sizeof(struct ip6_frag);
		p->data_len -= sizeof(struct ip6_frag);
		p->header_len += sizeof(struct ip6_frag);

		if ((p->ip6_frag->offset_flags & htons(IP6_F_MF)) &&
			(p->data_len & 0x7))
			return -1;

		if ((u32)(ntohs(p->ip6_frag->offset_flags) & IP6_F_MASK) +
			p->data_len > 65535)
			return -1;
	}

	if (p->data_proto == 58) {
		if (p->ip6_frag && (p->ip6_frag->offset_flags &
			htons(IP6_F_MASK | IP6_F_MF)))
			return -1; /* fragmented ICMP is unsupported */
		if (p->data_len < sizeof(struct icmp))
			return -1;
		p->icmp = (struct icmp *)(p->data);
	}

	return 0;
}

static void xlate_6to4_icmp_error(struct pkt *p)
{
	struct {
		struct ip4 ip4;
		struct icmp icmp;
		struct ip4 ip4_em;
	} __attribute__ ((__packed__)) header;
	struct sk_buff *skb;
	struct pkt p_em;
	u32 mtu;
	u16 em_len;
	int allow_fake_source = 0;

	memset(&p_em, 0, sizeof(p_em));
	p_em.data = p->data + sizeof(struct icmp);
	p_em.data_len = p->data_len - sizeof(struct icmp);

	if (p->icmp->type == 1 || p->icmp->type == 3) {
		em_len = (ntohl(p->icmp->word) >> 21) & 0x7f8;
		if (em_len) {
			if (p_em.data_len < em_len)
				return;
			p_em.data_len = em_len;
		}
	}

	if (parse_ip6(&p_em) < 0)
		return;

	if (p_em.data_proto == 58 && p_em.icmp->type != 128)
		return;

	if (sizeof(struct ip4) * 2 + sizeof(struct icmp) + p_em.data_len > 576)
		p_em.data_len = 576 - sizeof(struct ip4) * 2 -
						sizeof(struct icmp);

	switch (p->icmp->type) {
	case 1: /* Destination Unreachable */
		header.icmp.type = 3; /* Destination Unreachable */
		header.icmp.word = 0;
		switch (p->icmp->code) {
		case 0: /* No route to destination */
		case 2: /* Beyond scope of source address */
			header.icmp.code = 1; /* Host Unreachable */
			allow_fake_source = 1;
			break;
		case 1: /* Administratively prohibited */
			header.icmp.code = 10; /* Administratively prohibited */
			break;
		case 4: /* Port Unreachable */
			header.icmp.code = 3; /* Port Unreachable */
			break;
		default:
			return;
		}
		break;
	case 2: /* Packet Too Big */
		header.icmp.type = 3; /* Destination Unreachable */
		header.icmp.code = 4; /* Fragmentation needed */
		mtu = ntohl(p->icmp->word);
		if (mtu < 68) {
			printk(KERN_WARNING "tayga: no mtu in Packet Too Big message\n");
			return;
		}
		if (mtu > gcfg.mtu)
			mtu = gcfg.mtu;
		mtu -= MTU_ADJ;
		header.icmp.word = htonl(mtu);
		allow_fake_source = 1;
		break;
	case 3: /* Time Exceeded */
		header.icmp.type = 11; /* Time Exceeded */
		header.icmp.code = p->icmp->code;
		header.icmp.word = 0;
		break;
	case 4: /* Parameter Problem */
		if (p->icmp->code == 1) {
			header.icmp.type = 3; /* Destination Unreachable */
			header.icmp.code = 2; /* Protocol Unreachable */
			header.icmp.word = 0;
			break;
		} else if (p->icmp->code != 0) {
			return;
		}
		header.icmp.type = 12; /* Parameter Problem */
		header.icmp.code = 0;
		/* XXX do this and remove return */
		return;
	default:
		return;
	}

	if (map_ip6_to_ip4(&header.ip4_em.src, &p_em.ip6->src, 0) ||
		map_ip6_to_ip4(&header.ip4_em.dest,&p_em.ip6->dest, 1) ||
			xlate_payload_6to4(&p_em, &header.ip4_em) < 0)
		return;

	xlate_header_6to4(&p_em, &header.ip4_em,
		ntohs(p_em.ip6->payload_length) - p_em.header_len);

	header.ip4_em.cksum =
		htons(swap_u16(ip_checksum(&header.ip4_em, sizeof(header.ip4_em))));

	if (map_ip6_to_ip4(&header.ip4.src, &p->ip6->src, 0)) {
		if (allow_fake_source)
			header.ip4.src = gcfg.local_addr4;
		else
			return;
	}

	if (map_ip6_to_ip4(&header.ip4.dest, &p->ip6->dest, 0))
		return;

	xlate_header_6to4(p, &header.ip4, sizeof(header.icmp) +
				sizeof(header.ip4_em) + p_em.data_len);
	--header.ip4.ttl;

	header.ip4.cksum = htons(swap_u16(ip_checksum(&header.ip4, sizeof(header.ip4))));

	header.icmp.cksum = 0;
	header.icmp.cksum = htons(swap_u16(ones_add(ip_checksum(&header.icmp,
							sizeof(header.icmp) +
							sizeof(header.ip4_em)),
				ip_checksum(p_em.data, p_em.data_len))));

	skb = netdev_alloc_skb(p->dev, sizeof(header) + p_em.data_len);
	if (!skb) {
		p->dev->stats.rx_dropped++;
		return;
	}
	memcpy(skb_put(skb, sizeof(header)), &header, sizeof(header));
	memcpy(skb_put(skb, p_em.data_len), p_em.data, p_em.data_len);
	skb->protocol = htons(ETH_P_IP);

	p->dev->stats.rx_bytes += skb->len;
	p->dev->stats.rx_packets++;
	netif_rx(skb);
}

void handle_ip6(struct pkt *p)
{
	if (parse_ip6(p) < 0 || p->ip6->hop_limit == 0 ||
		p->header_len + p->data_len != ntohs(p->ip6->payload_length)) {
		p->dev->stats.tx_dropped++;
		kfree_skb(p->skb);
		return;
	}

	if (p->icmp && ones_add(ip_checksum(p->data, p->data_len),
				ip6_checksum(p->ip6, p->data_len, 58))) {
		p->dev->stats.tx_dropped++;
		kfree_skb(p->skb);
		return;
	}

	p->dev->stats.tx_bytes += p->skb->len;
	p->dev->stats.tx_packets++;

	if (IN6_ARE_ADDR_EQUAL(&p->ip6->dest, &gcfg.local_addr6)) {
		if (p->data_proto == 58)
			host_handle_icmp6(p);
		else
			host_send_icmp6_error(4, 1, 6, p);
		kfree_skb(p->skb);
	} else {
		if (p->ip6->hop_limit == 1) {
			host_send_icmp6_error(3, 0, 0, p);
			kfree_skb(p->skb);
			return;
		}

		if (p->data_proto != 58 || p->icmp->type == 128 ||
				p->icmp->type == 129)
			xlate_6to4_data(p);
		else
			xlate_6to4_icmp_error(p);
	}
}
