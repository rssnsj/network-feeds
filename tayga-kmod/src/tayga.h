/*
 *  tayga.h -- main header file
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

#include <linux/in.h>
#include <linux/in6.h>
#include <linux/list.h>
#include <linux/netdevice.h>

#ifndef IN6_ARE_ADDR_EQUAL
#define IN6_ARE_ADDR_EQUAL(a,b)  (__extension__  \
	({ __const struct in6_addr *__a = (__const struct in6_addr *) (a); \
		__const struct in6_addr *__b = (__const struct in6_addr *) (b); \
		__a->s6_addr32[0] == __b->s6_addr32[0]  \
		&& __a->s6_addr32[1] == __b->s6_addr32[1]  \
		&& __a->s6_addr32[2] == __b->s6_addr32[2]  \
		&& __a->s6_addr32[3] == __b->s6_addr32[3]; }))
#endif

/* Configuration knobs */

/* Number of seconds of silence before a map ages out of the cache */
#define CACHE_MAX_AGE		(HZ * 120)

/* Number of seconds between cache ageing passes */
#define CACHE_CHECK_INTERVAL	(HZ * 5)

/* Number of seconds between dynamic pool ageing passes */
#define POOL_CHECK_INTERVAL	(HZ * 5)

/* Valid token delimiters in config file and dynamic map file */
#define DELIM		" \t\r\n"


/* Protocol structures */

struct ip4 {
	u8 ver_ihl; /* 7-4: ver==4, 3-0: IHL */
	u8 tos;
	u16 length;
	u16 ident;
	u16 flags_offset; /* 15-13: flags, 12-0: frag offset */
	u8 ttl;
	u8 proto;
	u16 cksum;
	struct in_addr src;
	struct in_addr dest;
} __attribute__ ((__packed__));

#define IP4_F_DF	0x4000
#define IP4_F_MF	0x2000
#define IP4_F_MASK	0x1fff

struct ip6 {
	u32 ver_tc_fl; /* 31-28: ver==6, 27-20: traf cl, 19-0: flow lbl */
	u16 payload_length;
	u8 next_header;
	u8 hop_limit;
	struct in6_addr src;
	struct in6_addr dest;
} __attribute__ ((__packed__));

struct ip6_frag {
	u8 next_header;
	u8 reserved;
	u16 offset_flags; /* 15-3: frag offset, 2-0: flags */
	u32 ident;
} __attribute__ ((__packed__));

#define IP6_F_MF	0x0001
#define IP6_F_MASK	0xfff8

struct icmp {
	u8 type;
	u8 code;
	u16 cksum;
	u32 word;
} __attribute__ ((__packed__));

#define	WKPF	(htonl(0x0064ff9b))

/* Adjusting the MTU by 20 does not leave room for the IP6 fragmentation
   header, for fragments with the DF bit set.  Follow up with BEHAVE on this.

   (See http://www.ietf.org/mail-archive/web/behave/current/msg08499.html)
 */
#define MTU_ADJ		20


/* TAYGA data definitions */

struct pkt {
	struct net_device *dev;
	struct sk_buff *skb;
	struct ip4 *ip4;
	struct ip6 *ip6;
	struct ip6_frag *ip6_frag;
	struct icmp *icmp;
	u8 data_proto;
	u8 *data;
	u32 data_len;
	u32 header_len; /* inc IP hdr for v4 but excl IP hdr for v6 */
};

//#define CACHE_F_SEEN_4TO6  (1<<0)
//#define CACHE_F_SEEN_6TO4  (1<<1)
//#define CACHE_F_GEN_IDENT  (1<<2)
//#define CACHE_F_REP_AGEOUT  (1<<3)

struct config {
	/* NAT64 parameters, corresponding to /etc/tayga.conf */
	struct in6_addr prefix;
	struct in6_addr prefix_mask;
	int prefix_len;
	struct in_addr dynamic_pool;
	struct in_addr dynamic_mask;
	int dynamic_pfxlen;
	struct in_addr local_addr4;
	struct in6_addr local_addr6;

	unsigned long dynamic_pool_timeo;

	//struct list_head map4_list;
	//struct list_head map6_list;
	int dyn_min_lease;
	int dyn_max_lease;
	int max_commit_delay;
	//struct dynamic_pool *dynamic_pool;
	int hash_bits;
	//int cache_size;
	int allow_ident_gen;
	int ipv6_offlink_mtu;
	int lazy_frag_hdr;

	u16 mtu;

	u32 rand[8];

	unsigned long last_dynamic_maint;
	unsigned long last_map_write;
	int map_write_pending;
};


/* Macros and static functions */

#define IN6_IS_IN_NET(addr,net,mask) \
	((net)->s6_addr32[0] == ((addr)->s6_addr32[0] & \
					(mask)->s6_addr32[0]) && \
	 (net)->s6_addr32[1] == ((addr)->s6_addr32[1] & \
		 			(mask)->s6_addr32[1]) && \
	 (net)->s6_addr32[2] == ((addr)->s6_addr32[2] & \
		 			(mask)->s6_addr32[2]) && \
	 (net)->s6_addr32[3] == ((addr)->s6_addr32[3] & \
		 			(mask)->s6_addr32[3]))

#define IN4_IS_IN_NET(addr,net,mask) \
	((net)->s_addr == ((addr)->s_addr & (mask)->s_addr))


/* TAYGA function prototypes */

/* addrmap.c */
int validate_ip4_addr(const struct in_addr *a);
int validate_ip6_addr(const struct in6_addr *a);
int is_private_ip4_addr(const struct in_addr *a);
int calc_ip4_mask(struct in_addr *mask, const struct in_addr *addr, int len);
int calc_ip6_mask(struct in6_addr *mask, const struct in6_addr *addr, int len);

int __map_ip4_to_ip6(struct in6_addr *addr6, const struct in_addr *addr4);
int __map_ip6_to_ip4(struct in_addr *addr4, 	const struct in6_addr *addr6, int dyn_alloc);

static inline int map_ip4_to_ip6(struct in6_addr *addr6, const struct in_addr *addr4)
{
	int rc;
	rcu_read_lock();
	rc = __map_ip4_to_ip6(addr6, addr4);
	rcu_read_unlock();
	return rc;
}
static inline int map_ip6_to_ip4(struct in_addr *addr4, const struct in6_addr *addr6,
	int dyn_alloc)
{
	int rc;
	rcu_read_lock();
	rc = __map_ip6_to_ip4(addr4, addr6, dyn_alloc);
	rcu_read_unlock();
	return rc;
}

int init_addrmap(void);
void fini_addrmap(void);


/* conffile.c */
extern struct config gcfg;
int check_params(void);

/* nat64.c */
void handle_ip4(struct pkt *p);
void handle_ip6(struct pkt *p);

/* utilities */
static inline void init_list_entry(struct list_head *entry)
{
	entry->next = LIST_POISON1;
	entry->prev = LIST_POISON2;
}
static inline int list_entry_orphan(struct list_head *entry)
{
	return entry->next == LIST_POISON1;
}

#define INIT_RCU_HEAD(p)  ((void)0)

static inline char *simple_inet6_ntoa(const struct in6_addr *a, char *s)
{
	sprintf(s, "%x:%x:%x:%x:%x:%x:%x:%x",
			ntohs(a->s6_addr16[0]), ntohs(a->s6_addr16[1]), 
			ntohs(a->s6_addr16[2]), ntohs(a->s6_addr16[3]), 
			ntohs(a->s6_addr16[4]), ntohs(a->s6_addr16[5]), 
			ntohs(a->s6_addr16[6]), ntohs(a->s6_addr16[7]));
	return s;
}

static inline char *simple_inet_ntoa(const struct in_addr *a, char *s)
{
	unsigned char *ap = (unsigned char *)&a->s_addr;
	sprintf(s, "%u.%u.%u.%u", ap[0], ap[1], ap[2], ap[3]);
	return s;
}


