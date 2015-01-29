/*
 *  addrmap.c -- address mapping routines
 *
 *  Copyright (C) 2014 Jianying Liu <rssnsj@gmail.com>
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
#include <linux/kernel.h>
#include <linux/inet.h>
#include <linux/types.h>
#include <asm/param.h>
#include <asm/byteorder.h>
#include <linux/netdevice.h>
#include <linux/kthread.h>
#include <linux/sched.h>
#include "tayga.h"

#define ADDRMAP_HASH_BITS  14

struct addrmap_bucket {
	struct list_head chain;
	spinlock_t lock;
};

struct addrmap_table {
	struct addrmap_bucket base4[1 << ADDRMAP_HASH_BITS];
	struct addrmap_bucket base6[1 << ADDRMAP_HASH_BITS];
	size_t hash_size;
	struct list_head idle_queue;
	spinlock_t idle_lock;
	/* Number of unassigned IPv4 addresses in divided sections */
	size_t *free_count;
	size_t free_count_rows;
};

struct addrmap {
	struct list_head list6;
	struct list_head list4;
	struct list_head idle_list;
	struct in_addr addr4;
	struct in6_addr addr6;
	struct addrmap_bucket *bucket6;
	struct addrmap_bucket *bucket4;
	unsigned long last_use;
	struct rcu_head rcu;
};

static struct addrmap_table g_addrmap_tbl;

static inline u32 hash_ip4(const struct in_addr *addr4)
{
	return (u32)(addr4->s_addr * gcfg.rand[0]);
}

static inline u32 hash_ip6(const struct in6_addr *addr6)
{
	u32 h;

	h = ((u32)addr6->s6_addr16[0] + gcfg.rand[0]) *
		((u32)addr6->s6_addr16[1] + gcfg.rand[1]);
	h ^= ((u32)addr6->s6_addr16[2] + gcfg.rand[2]) *
		((u32)addr6->s6_addr16[3] + gcfg.rand[3]);
	h ^= ((u32)addr6->s6_addr16[4] + gcfg.rand[4]) *
		((u32)addr6->s6_addr16[5] + gcfg.rand[5]);
	h ^= ((u32)addr6->s6_addr16[6] + gcfg.rand[6]) *
		((u32)addr6->s6_addr16[7] + gcfg.rand[7]);
	return h;
}


static inline void consume_dynamic_ip(
		const struct in_addr *addr4)
{
	u32 base = ntohl(addr4->s_addr) - ntohl(gcfg.dynamic_pool.s_addr);
	int row = base / g_addrmap_tbl.free_count_rows;
	g_addrmap_tbl.free_count[row]--;
}

static inline void release_dynamic_ip(
		const struct in_addr *addr4)
{
	u32 base = ntohl(addr4->s_addr) - ntohl(gcfg.dynamic_pool.s_addr);
	int row = base / g_addrmap_tbl.free_count_rows;
	g_addrmap_tbl.free_count[row]++;
}

static struct addrmap *alloc_addrmap(const struct in6_addr *addr6,
	struct in_addr *addr4)
{
	struct addrmap *map;

	if (!(map = kmalloc(sizeof(struct addrmap), GFP_ATOMIC)))
		return NULL;
	init_list_entry(&map->list4);
	init_list_entry(&map->list6);
	init_list_entry(&map->idle_list);
	map->addr6 = *addr6;
	map->addr4 = *addr4;
	map->last_use = jiffies;
	INIT_RCU_HEAD(&map->rcu);	
	return map;
}

static void __free_addrmap_rcu(struct rcu_head *rcu)
{
	struct addrmap *map = container_of(rcu, struct addrmap, rcu);
	kfree(map);
}

static void free_addrmap_rcu(struct addrmap *map)
{
	/*
	 * NOTICE: Caller must ensure 'map' was already removed
	 *  from two hash tables and the idle_queue.
	 */
	char s_addr4[20];

	release_dynamic_ip(&map->addr4);
	call_rcu(&map->rcu, __free_addrmap_rcu);

	printk("tayga: Recycled address %s\n",
			simple_inet_ntoa(&map->addr4, s_addr4));
}

static void free_addrmap(struct addrmap *map)
{
	release_dynamic_ip(&map->addr4);
	kfree(map);
}

static void touch_addrmap(struct addrmap *map)
{
	struct addrmap_table *tbl = &g_addrmap_tbl;

	/* Update its idle_list order with minimum interval: 5s */
	if (jiffies - map->last_use < HZ * 5)
		return;

	map->last_use = jiffies;
	spin_lock_bh(&tbl->idle_lock);
	/* Might be removed from idle_queue after got from hash table. */
	if (!list_entry_orphan(&map->idle_list)) {
		list_del_rcu(&map->idle_list);
		list_add_tail_rcu(&map->idle_list, &tbl->idle_queue);
	}
	spin_unlock_bh(&tbl->idle_lock);
}

static bool is_ip4_assigned(const struct in_addr *addr4)
{
	struct addrmap_bucket *bucket4 = &g_addrmap_tbl.base4[
		hash_ip4(addr4) & (g_addrmap_tbl.hash_size - 1)];
	struct addrmap *map;
	
	list_for_each_entry_rcu (map, &bucket4->chain, list4) {
		if (addr4->s_addr == map->addr4.s_addr)
			return true;
	}
	return false;
}

int append_to_prefix(struct in6_addr *addr6, const struct in_addr *addr4,
		const struct in6_addr *prefix, int prefix_len)
{
	switch (prefix_len) {
	case 32:
		addr6->s6_addr32[0] = prefix->s6_addr32[0];
		addr6->s6_addr32[1] = addr4->s_addr;
		addr6->s6_addr32[2] = 0;
		addr6->s6_addr32[3] = 0;
		return 0;
	case 40:
		addr6->s6_addr32[0] = prefix->s6_addr32[0];
#ifdef __BIG_ENDIAN
		addr6->s6_addr32[1] = prefix->s6_addr32[1] |
					(addr4->s_addr >> 8);
		addr6->s6_addr32[2] = (addr4->s_addr << 16) & 0x00ff0000;
#endif
#ifdef __LITTLE_ENDIAN
		addr6->s6_addr32[1] = prefix->s6_addr32[1] |
					(addr4->s_addr << 8);
		addr6->s6_addr32[2] = (addr4->s_addr >> 16) & 0x0000ff00;
#endif
		addr6->s6_addr32[3] = 0;
		return 0;
	case 48:
		addr6->s6_addr32[0] = prefix->s6_addr32[0];
#ifdef __BIG_ENDIAN
		addr6->s6_addr32[1] = prefix->s6_addr32[1] |
					(addr4->s_addr >> 16);
		addr6->s6_addr32[2] = (addr4->s_addr << 8) & 0x00ffff00;
#endif
#ifdef __LITTLE_ENDIAN
		addr6->s6_addr32[1] = prefix->s6_addr32[1] |
					(addr4->s_addr << 16);
		addr6->s6_addr32[2] = (addr4->s_addr >> 8) & 0x00ffff00;
#endif
		addr6->s6_addr32[3] = 0;
		return 0;
	case 56:
		addr6->s6_addr32[0] = prefix->s6_addr32[0];
#ifdef __BIG_ENDIAN
		addr6->s6_addr32[1] = prefix->s6_addr32[1] |
					(addr4->s_addr >> 24);
		addr6->s6_addr32[2] = addr4->s_addr & 0x00ffffff;
#endif
#ifdef __LITTLE_ENDIAN
		addr6->s6_addr32[1] = prefix->s6_addr32[1] |
					(addr4->s_addr << 24);
		addr6->s6_addr32[2] = addr4->s_addr & 0xffffff00;
#endif
		addr6->s6_addr32[3] = 0;
		return 0;
	case 64:
		addr6->s6_addr32[0] = prefix->s6_addr32[0];
		addr6->s6_addr32[1] = prefix->s6_addr32[1];
#ifdef __BIG_ENDIAN
		addr6->s6_addr32[2] = addr4->s_addr >> 8;
		addr6->s6_addr32[3] = addr4->s_addr << 24;
#endif
#ifdef __LITTLE_ENDIAN
		addr6->s6_addr32[2] = addr4->s_addr << 8;
		addr6->s6_addr32[3] = addr4->s_addr >> 24;
#endif
		return 0;
	case 96:
		if (prefix->s6_addr32[0] == WKPF &&
				is_private_ip4_addr(addr4))
			return -1;
		addr6->s6_addr32[0] = prefix->s6_addr32[0];
		addr6->s6_addr32[1] = prefix->s6_addr32[1];
		addr6->s6_addr32[2] = prefix->s6_addr32[2];
		addr6->s6_addr32[3] = addr4->s_addr;
		return 0;
	default:
		return -1;
	}
}

static int extract_from_prefix(struct in_addr *addr4,
		const struct in6_addr *addr6, int prefix_len)
{
	switch (prefix_len) {
	case 32:
		if (addr6->s6_addr32[2] || addr6->s6_addr32[3])
			return -1;
		addr4->s_addr = addr6->s6_addr32[1];
		break;
	case 40:
		if (addr6->s6_addr32[2] & htonl(0xff00ffff) ||
				addr6->s6_addr32[3])
			return -1;
#ifdef __BIG_ENDIAN
		addr4->s_addr = (addr6->s6_addr32[1] << 8) | addr6->s6_addr[9];
#endif
#ifdef __LITTLE_ENDIAN
		addr4->s_addr = (addr6->s6_addr32[1] >> 8) |
				(addr6->s6_addr32[2] << 16);
#endif
		break;
	case 48:
		if (addr6->s6_addr32[2] & htonl(0xff0000ff) ||
				addr6->s6_addr32[3])
			return -1;
#ifdef __BIG_ENDIAN
		addr4->s_addr = (addr6->s6_addr16[3] << 16) |
				(addr6->s6_addr32[2] >> 8);
#endif
#ifdef __LITTLE_ENDIAN
		addr4->s_addr = addr6->s6_addr16[3] |
				(addr6->s6_addr32[2] << 8);
#endif
		break;
	case 56:
		if (addr6->s6_addr[8] || addr6->s6_addr32[3])
			return -1;
#ifdef __BIG_ENDIAN
		addr4->s_addr = (addr6->s6_addr[7] << 24) |
				addr6->s6_addr32[2];
#endif
#ifdef __LITTLE_ENDIAN
		addr4->s_addr = addr6->s6_addr[7] |
				addr6->s6_addr32[2];
#endif
		break;
	case 64:
		if (addr6->s6_addr[8] ||
				addr6->s6_addr32[3] & htonl(0x00ffffff))
			return -1;
#ifdef __BIG_ENDIAN
		addr4->s_addr = (addr6->s6_addr32[2] << 8) |
				addr6->s6_addr[12];
#endif
#ifdef __LITTLE_ENDIAN
		addr4->s_addr = (addr6->s6_addr32[2] >> 8) |
				(addr6->s6_addr32[3] << 24);
#endif
		break;
	case 96:
		addr4->s_addr = addr6->s6_addr32[3];
		break;
	default:
		return -1;
	}
	return validate_ip4_addr(addr4);
}


int __map_ip4_to_ip6(struct in6_addr *addr6, const struct in_addr *addr4)
{
	struct addrmap_bucket *bucket4;
	struct addrmap *map;

	if (!IN4_IS_IN_NET(addr4, &gcfg.dynamic_pool, &gcfg.dynamic_mask))
		return append_to_prefix(addr6, addr4, &gcfg.prefix, gcfg.prefix_len);

	bucket4 = &g_addrmap_tbl.base4[hash_ip4(addr4) &
			(g_addrmap_tbl.hash_size - 1)];
	list_for_each_entry_rcu (map, &bucket4->chain, list4) {
		if (addr4->s_addr == map->addr4.s_addr) {
			*addr6 = map->addr6;
			touch_addrmap(map);
			return 0;
		}
	}

	return -1;
}

int __map_ip6_to_ip4(struct in_addr *addr4,
	const struct in6_addr *addr6, int dyn_alloc)
{
	struct addrmap *map;
	u32 base, max;
	struct addrmap_bucket *bucket6, *bucket4;
	struct in_addr assigned_ip4 = { 0 };
	int i, row, col, tot_cols;
	char s_addr4[20], s_addr6[40];

	/* NAT64 address conversion */
	if (IN6_IS_IN_NET(addr6, &gcfg.prefix, &gcfg.prefix_mask)) {
		if (extract_from_prefix(addr4, addr6, gcfg.prefix_len) < 0)
			return -1;
		return 0;
	}

	if (!dyn_alloc)
		return -1;

	/* Search in dynamic pool hash table */
	bucket6 = &g_addrmap_tbl.base6[hash_ip6(addr6) &
		(g_addrmap_tbl.hash_size - 1)];
	list_for_each_entry_rcu (map, &bucket6->chain, list6) {
		if (IN6_ARE_ADDR_EQUAL(addr6, &map->addr6)) {
			*addr4 = map->addr4;
			touch_addrmap(map);
			return 0;
		}
	}

	/* Not cached, create it */
	spin_lock_bh(&bucket6->lock);
	
	/* Search again to ensure the entry does not exist */
	list_for_each_entry (map, &bucket6->chain, list6) {
		if (IN6_ARE_ADDR_EQUAL(addr6, &map->addr6)) {
			spin_unlock_bh(&bucket6->lock);
			*addr4 = map->addr4;
			return 0;
		}
	}

	/* Assign IPv4 address from pool for IPv6 source address */
	base = 0;
	max = (1 << (32 - gcfg.dynamic_pfxlen)) - 1;
	for (i = 0; i < 4; i++) {
		base += ntohl(addr6->s6_addr32[i]);
		while (base & ~max) {
			base = (base & max) +
				(base >> (32 - gcfg.dynamic_pfxlen));
		}
	}
	tot_cols = (1 << (32 - gcfg.dynamic_pfxlen)) / g_addrmap_tbl.free_count_rows;
	row = base / g_addrmap_tbl.free_count_rows;
	col = base % g_addrmap_tbl.free_count_rows;
	for (i = 0; i < g_addrmap_tbl.free_count_rows; i++) {
		if (g_addrmap_tbl.free_count[row] > 0)
			break;
		row = (row + 1) & (g_addrmap_tbl.free_count_rows - 1);
	}
	for (i = 0; i < tot_cols; i++) {
		struct in_addr __assigned;
		__assigned.s_addr = htonl(ntohl(gcfg.dynamic_pool.s_addr) +
			(u32)tot_cols * row + col);
		if (!is_ip4_assigned(&__assigned)) {
			assigned_ip4 = __assigned;
			break;
		}
		col = (col + 1) & (tot_cols - 1);
	}
	if (assigned_ip4.s_addr == 0) {
		/* No free address */
		/* NOTICE: We can free address of the oldest map and use it */
		printk(KERN_WARNING "tayga: No free IPv4 address in pool.\n");
		return -1;
	}

	/* Allocate new entry and add to hash tables */
	if (!(map = alloc_addrmap(addr6, &assigned_ip4))) {
		spin_unlock_bh(&bucket6->lock);
		return -1;
	}

	/* Consume the allocated IP address */
	consume_dynamic_ip(&assigned_ip4);

	bucket4 = &g_addrmap_tbl.base4[hash_ip4(&assigned_ip4) &
		(g_addrmap_tbl.hash_size - 1)];
	map->bucket6 = bucket6;
	map->bucket4 = bucket4;
	list_add_rcu(&map->list6, &bucket6->chain);
	list_add_rcu(&map->list4, &bucket4->chain);
	//touch_addrmap(map);

	spin_lock_bh(&g_addrmap_tbl.idle_lock);
	list_add_rcu(&map->idle_list, &g_addrmap_tbl.idle_queue);
	spin_unlock_bh(&g_addrmap_tbl.idle_lock);

	spin_unlock_bh(&bucket6->lock);

	*addr4 = assigned_ip4;

	printk(KERN_INFO "tayga: New address mapping: %s to %s\n",
			simple_inet6_ntoa(addr6, s_addr6),
			simple_inet_ntoa(addr4, s_addr4));

	return 0;
}

static int recycle_kthread(void *data)
{
	struct addrmap_table *tbl = data;
	struct addrmap_bucket *bucket4, *bucket6;
	struct addrmap *map;

	set_current_state(TASK_RUNNING);
	while (!kthread_should_stop()) {
		if (!list_empty(&tbl->idle_queue)) {
			spin_lock_bh(&tbl->idle_lock);
			while (!list_empty(&tbl->idle_queue)) {
				map = list_first_entry(&tbl->idle_queue,
						struct addrmap, idle_list);

				if (jiffies - map->last_use <= HZ * gcfg.dynamic_pool_timeo)
					break;

				bucket6 = map->bucket6;
				bucket4 = map->bucket4;

				/*
				 * NOTICE: __trylock__ MUST be used instead of __lock__,
				 *  otherwise it may stuck while racing the two locks!
				 */
				if (!spin_trylock_bh(&bucket6->lock)) {
					spin_unlock_bh(&tbl->idle_lock);
					/* ----------------------- */
					goto skip;
				}
				if (!spin_trylock_bh(&bucket4->lock)) {
					spin_unlock_bh(&bucket6->lock);
					spin_unlock_bh(&tbl->idle_lock);
					/* ----------------------- */
					goto skip;
				}
				
				/* NOTICE: Now we get 3 locks, safe to operate */
				list_del(&map->idle_list);
				spin_unlock_bh(&tbl->idle_lock);
				/* ----------------------- */
				list_del_rcu(&map->list6);
				list_del_rcu(&map->list4);
				spin_unlock_bh(&bucket4->lock);
				spin_unlock_bh(&bucket6->lock);
				
				free_addrmap_rcu(map);
skip:
				cond_resched();
				/* ----------------------- */
				spin_lock_bh(&tbl->idle_lock);
			}
			spin_unlock_bh(&tbl->idle_lock);
		}

		set_current_state(TASK_INTERRUPTIBLE);
		schedule_timeout(HZ * 5);
		set_current_state(TASK_RUNNING);
	}
	set_current_state(TASK_RUNNING);

	return 0;
}

static struct task_struct *g_recycle_task = NULL;

int init_addrmap(void)
{
	int rv = 0, i;
	size_t __row_bits, __col_bits;

	g_addrmap_tbl.hash_size = 1 << ADDRMAP_HASH_BITS;

	/* Hash able */
	for (i = 0; i < g_addrmap_tbl.hash_size; i++) {
		INIT_LIST_HEAD(&g_addrmap_tbl.base4[i].chain);
		spin_lock_init(&g_addrmap_tbl.base4[i].lock);
		INIT_LIST_HEAD(&g_addrmap_tbl.base6[i].chain);
		spin_lock_init(&g_addrmap_tbl.base6[i].lock);
	}
	INIT_LIST_HEAD(&g_addrmap_tbl.idle_queue);
	spin_lock_init(&g_addrmap_tbl.idle_lock);

	/* Free address count of sectioned pool space */
	__col_bits = (32 - gcfg.dynamic_pfxlen) / 2;
	__row_bits = (32 - gcfg.dynamic_pfxlen) - __col_bits;
	g_addrmap_tbl.free_count_rows = 1 << __row_bits;
	g_addrmap_tbl.free_count = kmalloc(
			sizeof(size_t) * g_addrmap_tbl.free_count_rows, GFP_KERNEL);
	if (!g_addrmap_tbl.free_count) {
		rv = -ENOMEM;
		goto err3;
	}
	for (i = 0; i < g_addrmap_tbl.free_count_rows; i++)
		g_addrmap_tbl.free_count[i] = 1 << __col_bits;

	/* Start the recycling thread */
	g_recycle_task = kthread_create(recycle_kthread, &g_addrmap_tbl, "ktayga");
	if (g_recycle_task)
		wake_up_process(g_recycle_task);

	return 0;
err3:
	return rv;
}

void fini_addrmap(void)
{
	struct addrmap *map, *__nmap;
	int i;

	if (g_recycle_task)
		kthread_stop(g_recycle_task);

	for (i = 0; i < g_addrmap_tbl.hash_size; i++) {
		list_for_each_entry_safe (map, __nmap,
			&g_addrmap_tbl.base6[i].chain, list6) {
			list_del(&map->list6);
			list_del(&map->list4);
			list_del(&map->idle_list);
			free_addrmap(map);
		}
	}
	kfree(g_addrmap_tbl.free_count);
}

