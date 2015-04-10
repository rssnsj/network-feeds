#include <linux/kernel.h>
#include <linux/version.h>
#include <linux/module.h>
#include <linux/types.h>
#include <linux/netdevice.h>
#include <linux/skbuff.h>
#include <linux/etherdevice.h>
#include <linux/if_ether.h>
#include <linux/if_vlan.h>
#include <net/rtnetlink.h>
#include <net/sock.h>

static char param_vlans[128] = "";
module_param_string(vlans, param_vlans, sizeof(param_vlans), 0644);
MODULE_PARM_DESC(vlans, "Definition of all VLANs");

static int base_proto_id = 0x7077;
module_param_named(proto, base_proto_id, int, 0644);
MODULE_PARM_DESC(proto, "Ethernet protocol number (not recommended to change)");

static int vlan_dev_mtu = 0;
module_param_named(mtu, vlan_dev_mtu, int, 0644);
MODULE_PARM_DESC(mtu, "Override VLAN interface MTU size");

struct yavlan_info {
	unsigned short vid;
	struct net_device *phy_dev;
	struct net_device *vlan_dev;
	bool disabled_packip;
	unsigned char peer_hwaddr[ETH_ALEN];
	char phy_ifname[IFNAMSIZ];
	char vlan_ifname[IFNAMSIZ];
};

#define PACKIP_V4V6_PROTO_DIFF  0x1000
#define YAVLAN_LIST_SIZE  24
static struct yavlan_info *yavlan_list[YAVLAN_LIST_SIZE];
static int yavlan_list_count = 0;

static inline struct yavlan_info *yavlan_get_by_phydev_vid(
		struct net_device *phy_dev, unsigned short vid)
{
	int i;
	for (i = 0; i < yavlan_list_count; i++) {
		struct yavlan_info *vi = yavlan_list[i];
		if (!vi)
			continue;
		if (vi->phy_dev == phy_dev && vi->vid == vid)
			return vi;
	}
	return NULL;
}

static inline struct yavlan_info *yavlan_get_by_phyname_vid(
		const char *phy_ifname, unsigned short vid)
{
	int i;
	for (i = 0; i < yavlan_list_count; i++) {
		struct yavlan_info *vi = yavlan_list[i];
		if (!vi)
			continue;
		if (vi->vid == vid && strcmp(vi->phy_ifname, phy_ifname) == 0)
			return vi;
	}
	return NULL;
}


static int yavlan_base_rcv(struct sk_buff *skb, struct net_device *dev,
		struct packet_type *pt, struct net_device *orig_dev)
{
	struct sk_buff *__skb;
	struct vlan_ethhdr veh;
	unsigned short vid, proto;
	struct yavlan_info *vi;

	/* Ignore non-Ethernet packets */
	if (!vlan_eth_hdr(skb))
		goto out;

	/* Make a copy since data will be modified. */
	if (!(__skb = skb_copy(skb, GFP_ATOMIC)))
		goto out;
	kfree_skb(skb);
	skb = __skb;

	veh = *vlan_eth_hdr(skb);

	vid = ntohs(veh.h_vlan_TCI) & VLAN_VID_MASK;
	proto = veh.h_vlan_encapsulated_proto;

	if (!(vi = yavlan_get_by_phydev_vid(dev, vid)))
		goto out;

	if (proto != 0) {
		/* Adjust MAC header pointer and overwrite VLAN tag. */
		skb_push(skb, ETH_HLEN - VLAN_HLEN);
		skb_reset_mac_header(skb);

		if (unlikely(!pskb_may_pull(skb, ETH_HLEN)))
			goto out;
		memcpy(eth_hdr(skb)->h_dest, veh.h_dest, ETH_ALEN);
		memcpy(eth_hdr(skb)->h_source, veh.h_source, ETH_ALEN);
		eth_hdr(skb)->h_proto = proto;

		/* Move back to real network header after stripping VLAN tag. */
		skb_pull_rcsum(skb, ETH_HLEN);
		skb_reset_network_header(skb);
		skb_reset_transport_header(skb);
	} else {
		if (unlikely(!pskb_may_pull(skb, VLAN_HLEN + ETH_HLEN)))
			goto out;
		skb_pull(skb, VLAN_HLEN);
		skb_reset_mac_header(skb);

		skb_pull_rcsum(skb, ETH_HLEN);
		skb_reset_network_header(skb);
		skb_reset_transport_header(skb);

		proto = eth_hdr(skb)->h_proto;
	}

	skb->protocol = proto;
	skb->dev = vi->vlan_dev;
	skb->ip_summed = CHECKSUM_NONE;
	vi->vlan_dev->stats.rx_bytes += skb->len;
	vi->vlan_dev->stats.rx_packets++;
	netif_rx(skb);

	return 0;

out:
	kfree_skb(skb);
	return 0;
}

static int yavlan_ext_rcv(struct sk_buff *skb, struct net_device *dev,
		struct packet_type *pt, struct net_device *orig_dev)
{
	unsigned short fake_proto, vid = 0;
	struct yavlan_info *vi;
	__be16 real_proto = 0;

	/* Ignore non-Ethernet packets */
	if (!vlan_eth_hdr(skb))
		goto out;

	fake_proto = ntohs(eth_hdr(skb)->h_proto);

	if (fake_proto >= base_proto_id) {
		vid = fake_proto - base_proto_id;
		real_proto = htons(ETH_P_IP);
	} else {
		vid = fake_proto - (base_proto_id - PACKIP_V4V6_PROTO_DIFF);
		real_proto = htons(ETH_P_IPV6);
	}

	if (!(vi = yavlan_get_by_phydev_vid(dev, vid)))
		goto out;

	eth_hdr(skb)->h_proto = real_proto;
	skb->dev = vi->vlan_dev;
	skb->protocol = real_proto;
	skb->ip_summed = CHECKSUM_NONE;
	if (likely(netif_rx(skb) == NET_RX_SUCCESS)) {
		vi->vlan_dev->stats.rx_bytes += skb->len;
		vi->vlan_dev->stats.rx_packets++;
	}

	return 0;

out:
	kfree_skb(skb);
	return 0;
}

/* =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-= */

struct yavlan_netdev_priv {
	struct yavlan_info *vi;
};

#define vlan_netdev_to_vi(dev) (((struct yavlan_netdev_priv *)netdev_priv(dev))->vi)

static struct sk_buff *__headroom_and_unshare(struct sk_buff *skb, unsigned headroom)
{
	if (skb_headroom(skb) < headroom) {
		struct sk_buff *__skb = skb_realloc_headroom(skb, headroom);
		kfree_skb(skb);
		skb = __skb;
	} else {
		skb = skb_unshare(skb, GFP_ATOMIC);
	}

	if (!skb)
		return NULL;

	skb_orphan(skb);
	skb_dst_drop(skb);
	nf_reset(skb);
	skb_reset_mac_header(skb);

	return skb;
}

static int yavlan_start_xmit(struct sk_buff *skb, struct net_device *dev)
{
	struct yavlan_info *vi = vlan_netdev_to_vi(dev);

	if (!is_zero_ether_addr(vi->peer_hwaddr)) {
		/* Constant unicast peer address mode. */
		struct ethhdr *__eh;

		if (!(skb = __headroom_and_unshare(skb, VLAN_ETH_HLEN)))
			goto out;

		__eh = eth_hdr(skb);
		skb_push(skb, VLAN_ETH_HLEN);
		skb_reset_mac_header(skb);

		/* Fill the outer VLAN header. */
		memcpy(vlan_eth_hdr(skb)->h_dest, vi->peer_hwaddr, ETH_ALEN);
		memcpy(vlan_eth_hdr(skb)->h_source, vi->phy_dev->dev_addr, ETH_ALEN);
		vlan_eth_hdr(skb)->h_vlan_proto = htons(base_proto_id);
		vlan_eth_hdr(skb)->h_vlan_TCI = htons(vi->vid);
		/* NOTICE: Set it 0 here to let peer receive it in the correct mode. */
		vlan_eth_hdr(skb)->h_vlan_encapsulated_proto = 0;
	} else if (!vi->disabled_packip && eth_hdr(skb)->h_proto == __constant_htons(ETH_P_IP)) {
		/* IPv4 packing mode. */
		if (!(skb = __headroom_and_unshare(skb, 0)))
			goto out;
		eth_hdr(skb)->h_proto = htons(base_proto_id + vi->vid);
	} else if (!vi->disabled_packip && eth_hdr(skb)->h_proto == __constant_htons(ETH_P_IPV6)) {
		/* IPv6 packing mode. */
		if (!(skb = __headroom_and_unshare(skb, 0)))
			goto out;
		eth_hdr(skb)->h_proto = htons(base_proto_id - PACKIP_V4V6_PROTO_DIFF + vi->vid);
	} else {
		/* Regular VLAN mode with custom ethernet protocol. */
		struct ethhdr eh;

		if (!(skb = __headroom_and_unshare(skb, VLAN_HLEN)))
			goto out;

		eh = *eth_hdr(skb);
		skb_push(skb, VLAN_HLEN);
		skb_reset_mac_header(skb);

		/* Fill the VLAN-tagged Ethernet header. */
		memcpy(vlan_eth_hdr(skb)->h_dest, eh.h_dest, ETH_ALEN);
		memcpy(vlan_eth_hdr(skb)->h_source, eh.h_source, ETH_ALEN);
		vlan_eth_hdr(skb)->h_vlan_proto = htons(base_proto_id);
		vlan_eth_hdr(skb)->h_vlan_TCI = htons(vi->vid);
		vlan_eth_hdr(skb)->h_vlan_encapsulated_proto = eh.h_proto;
	}

	skb->dev = vi->phy_dev;
	dev_queue_xmit(skb);

	dev->stats.tx_bytes += skb->len;
	dev->stats.tx_packets++;
	return NETDEV_TX_OK;

out:
	return NETDEV_TX_OK;
}

static int yavlan_start(struct net_device *dev)
{
	netif_tx_start_all_queues(dev);
	return 0;
}

static int yavlan_stop(struct net_device *dev)
{
	netif_tx_stop_all_queues(dev);
	return 0;
}

static const struct net_device_ops yavlan_netdev_ops = {
	.ndo_open       = yavlan_start,
	.ndo_stop       = yavlan_stop,
	.ndo_start_xmit = yavlan_start_xmit,
};

static void yavlan_netdev_setup(struct net_device *dev)
{
	ether_setup(dev);
	dev->netdev_ops = &yavlan_netdev_ops;
}

static int netdev_attach_yavlan(struct net_device *phy_dev, struct yavlan_info *vi)
{
	int err = -1;
	struct net_device *vlan_dev = NULL;

	dev_hold(phy_dev);
	dev_set_promiscuity(phy_dev, 1);

	if (!(vlan_dev = alloc_netdev(sizeof(struct yavlan_netdev_priv), vi->vlan_ifname,
#if LINUX_VERSION_CODE >= KERNEL_VERSION(3, 17, 0)
		NET_NAME_UNKNOWN,
#endif
		yavlan_netdev_setup))) {
		printk(KERN_ERR "YaVLAN: alloc_netdev() failed.\n");
		err = -ENOMEM;
		goto out;
	}
	vlan_netdev_to_vi(vlan_dev) = vi;
	if (vlan_dev_mtu) {
		vlan_dev->mtu = vlan_dev_mtu;
	} else {
		vlan_dev->mtu = phy_dev->mtu;
	}
	memcpy(vlan_dev->dev_addr, phy_dev->dev_addr, ETH_ALEN);

	if ((err = register_netdevice(vlan_dev)) < 0)
		goto out;

	netif_carrier_on(vlan_dev);

	vi->phy_dev = phy_dev;
	vi->vlan_dev = vlan_dev;
	/* FIXME: RCU synchronizing. */

	printk(KERN_INFO "YaVLAN: %u@%s hooked\n", vi->vid, vi->phy_ifname);
	return 0;

out:
	if (vlan_dev)
		free_netdev(vlan_dev);
	dev_set_promiscuity(phy_dev, -1);
	dev_put(phy_dev);
	return err;
}

static int netdev_detach_yavlan(struct net_device *phy_dev, struct yavlan_info *vi)
{
	struct net_device *vlan_dev = vi->vlan_dev;

	vi->vlan_dev = NULL;
	vi->phy_dev = NULL;
	synchronize_rcu();

	if (vlan_dev) {
		unregister_netdevice(vlan_dev);
		//free_netdev(vlan_dev);
	}

	dev_set_promiscuity(phy_dev, -1);
	dev_put(phy_dev);

	printk(KERN_INFO "YaVLAN: %u@%s unhooked\n", vi->vid, vi->phy_ifname);
	return 0;
}

/* =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-= */

static int hooked_dev_event(struct notifier_block *unused,
	unsigned long event, void *ptr)
{
#if LINUX_VERSION_CODE >= KERNEL_VERSION(3, 11, 0)
	struct net_device *dev = netdev_notifier_info_to_dev(ptr);
#else
	struct net_device *dev = ptr;
#endif
	int i;

	for (i = 0; i < yavlan_list_count; i++) {
		struct yavlan_info *vi = yavlan_list[i];

		if (!vi)
			continue;
		if (event == NETDEV_REGISTER) {
			if (strcmp(vi->phy_ifname, dev->name) != 0)
				continue;
		} else if (vi->phy_dev != dev) {
			continue;
		}

		switch (event) {
		case NETDEV_REGISTER:
			/* Physical interface appears, hook it. */
			netdev_attach_yavlan(dev, yavlan_list[i]);
			break;
		case NETDEV_UNREGISTER:
			/* Physical interface is being removed, unhook from it. */
			netdev_detach_yavlan(dev, vi);
			break;
		case NETDEV_CHANGEADDR:
			memcpy(vi->vlan_dev->dev_addr, dev->dev_addr, ETH_ALEN);
			break;
		case NETDEV_CHANGEMTU:
			if (vi->vlan_dev->mtu > dev->mtu)
				dev_set_mtu(vi->vlan_dev, dev->mtu);
			break;
		}
	}

	return NOTIFY_DONE;
}

static struct notifier_block hooked_dev_notifier = {
	.notifier_call = hooked_dev_event,
};

static void __try_release_vlan_defs(void)
{
	int i;

	for (i = 0; i < yavlan_list_count; i++) {
		if (yavlan_list[i]->phy_dev)
			netdev_detach_yavlan(yavlan_list[i]->phy_dev, yavlan_list[i]);
		kfree(yavlan_list[i]);
		yavlan_list[i] = NULL;
	}
	yavlan_list_count = 0;
}

static int generate_vlan_defs_by_param(const char *vlan_defs)
{
	int err = -EINVAL;
	char *cp, *__vlans = NULL;
	size_t vlans_len;

	vlans_len = strlen(vlan_defs);
	if (vlans_len == 0) {
		printk(KERN_WARNING "YaVLAN: No VLAN definition specified\n");
		goto out;
	}

	/* Parse parameter 'vlans': 10@eth1@eth1-10,11@eth1,12@eth0,... */
	if (!(__vlans = kmalloc(vlans_len + 1, GFP_KERNEL))) {
		err = -ENOMEM;
		goto out;
	}
	memcpy(__vlans, vlan_defs, vlans_len + 1);

	cp = __vlans;
	do {
		char *cp_vid = NULL, *cp_pname = NULL, *cp_vname = NULL, *cp_peera = NULL;
		unsigned vid = 0;
		struct yavlan_info *vi;

		/* @@@ VLAN id. */
		cp_vid = cp;
		if ((cp = strchr(cp, ','))) {
			*(cp++) = '\0';
		}
		/* @@@ Physical interface name. */
		if (!(cp_pname = strchr(cp_vid, '@'))) {
			printk(KERN_WARNING "YaVLAN: Invalid VLAN description: '%s'\n", cp_vid);
			goto out;
		}
		*(cp_pname++) = '\0';
		/* @@@ Custom VLAN interface name. Empty name will be ignored. */
		if (cp_pname && (cp_vname = strchr(cp_pname, '@'))) {
			*(cp_vname++) = '\0';
		}
		/* @@@ Peer MAC address. */
		if (cp_vname && (cp_peera = strchr(cp_vname, '@'))) {
			*(cp_peera++) = '\0';
		}

		/* %%% Check VLAN id. */
		if (sscanf(cp_vid, "%u", &vid) != 1) {
			printk(KERN_WARNING "YaVLAN: Invalid VLAN ID: '%s'\n", cp_vid);
			goto out;
		}
		if (vid == 0 || vid >= VLAN_N_VID) {
			printk(KERN_WARNING "YaVLAN: Invalid VLAN ID: '%u'\n", vid);
			goto out;
		}

		/* %%% Check physical interface name, with duplication check. */
		if (yavlan_get_by_phyname_vid(cp_pname, (unsigned short)vid)) {
			printk(KERN_WARNING "YaVLAN: Duplicate VLAN definition: %u@%s\n",
					vid, cp_pname);
			goto out;
		}

		/* Add a VLAN description. */
		if (!(vi = kmalloc(sizeof(struct yavlan_info), GFP_KERNEL))) {
			printk(KERN_WARNING "YaVLAN: kmalloc() error\n");
			err = -ENOMEM;
			goto out;
		}
		memset(vi, 0x0, sizeof(*vi));
		vi->vid = (unsigned short)vid;
		strncpy(vi->phy_ifname, cp_pname, IFNAMSIZ);

		/* %%% Check custom VLAN interface name and apply. */
		if (cp_vname && strlen(cp_vname) > 0) {
			strncpy(vi->vlan_ifname, cp_vname, IFNAMSIZ);
		} else {
			snprintf(vi->vlan_ifname, IFNAMSIZ, "%s-%u", vi->phy_ifname, vi->vid);
		}

		/* %%% Check peer address and apply. */
		vi->disabled_packip = false;  /* enabled by default */
		memset(vi->peer_hwaddr, 0x0, ETH_ALEN);  /* no full encapsulation by default */
		if (cp_peera && strlen(cp_peera) > 0) {
			memset(vi->peer_hwaddr, 0x0, ETH_ALEN);
			if (strcmp(cp_peera, "N") == 0) {
				vi->disabled_packip = true;
			} else if (strcmp(cp_peera, "P") == 0) {
				vi->disabled_packip = false;
			} else if (sscanf(cp_peera, "%2hhx:%2hhx:%2hhx:%2hhx:%2hhx:%2hhx",
				&vi->peer_hwaddr[0], &vi->peer_hwaddr[1], &vi->peer_hwaddr[2],
				&vi->peer_hwaddr[3], &vi->peer_hwaddr[4], &vi->peer_hwaddr[5]) == 6 &&
				!is_zero_ether_addr(vi->peer_hwaddr)) {
				/* No extra check. */
			} else {
				printk(KERN_WARNING "YaVLAN: Invalid mode indicator or MAC address: %s\n", cp_peera);
				goto out;
			}
		}
	
		if (yavlan_list_count >= YAVLAN_LIST_SIZE) {
			printk(KERN_WARNING "YaVLAN: VLAN definition list is full\n");
			kfree(vi);
			break;
		}
		yavlan_list[yavlan_list_count++] = vi;
	} while (cp);

	kfree(__vlans);
	return 0;

out:
	if (__vlans)
		kfree(__vlans);
	__try_release_vlan_defs();
	return err;
}

static struct packet_type yavlan_base_ptype;
static struct packet_type yavlan_ext_ptype[YAVLAN_LIST_SIZE];
static size_t yavlan_ext_ptype_count = 0;

static inline bool __yavlan_ext_ptype_exists(unsigned short proto_id)
{
	int j;
	for (j = 0; j < yavlan_ext_ptype_count; j++) {
		if (proto_id == ntohs(yavlan_ext_ptype[j].type))
			return true;
	}
	return false;
}

int __init yavlan_init(void)
{
	int err = -EINVAL, rc, i;

	/* Check parameter 'proto', expecting a valid Ethernet protocol. */
	if (base_proto_id < 0x100) {
		printk(KERN_WARNING "YaVLAN: Invalid Ethernet protocol '0x%04x'\n", base_proto_id);
		goto out;
	}
	/* Check parameter 'mtu'. */
	if (vlan_dev_mtu) {
		if (vlan_dev_mtu < 1000 || vlan_dev_mtu > 8192) {
			printk(KERN_WARNING "YaVLAN: Illegal MTU size: %d\n", vlan_dev_mtu);
			goto out;
		}
	}

	if ((rc = generate_vlan_defs_by_param(param_vlans)) < 0) {
		err = rc;
		goto out;
	}

	/* This calls the notifier callback in which the hook is added. */
	register_netdevice_notifier(&hooked_dev_notifier);

	/* Add packet hook for all customized Ethernet protocols. */
	yavlan_base_ptype.type = htons(base_proto_id);
	yavlan_base_ptype.func = yavlan_base_rcv;
	yavlan_base_ptype.dev = NULL;
	dev_add_pack(&yavlan_base_ptype);

	for (i = 0; i < yavlan_list_count; i++) {
		unsigned short proto_id = base_proto_id + yavlan_list[i]->vid;
		struct packet_type *__pt = NULL;

		/* To avoid duplicate hooking for a single protocol type. */
		if (__yavlan_ext_ptype_exists(proto_id))
			continue;
		if (yavlan_ext_ptype_count >= YAVLAN_LIST_SIZE) {
			printk(KERN_WARNING "YaVLAN: Too many VLAN definitions, ignored more.\n");
			break;
		}
		__pt = &yavlan_ext_ptype[yavlan_ext_ptype_count++];
		__pt->type = htons(proto_id);
		__pt->func = yavlan_ext_rcv;
		__pt->dev = NULL;
		dev_add_pack(__pt);
	}

	for (i = 0; i < yavlan_list_count; i++) {
		unsigned short proto_id = base_proto_id - PACKIP_V4V6_PROTO_DIFF +
				yavlan_list[i]->vid;
		struct packet_type *__pt = NULL;

		if (__yavlan_ext_ptype_exists(proto_id))
			continue;
		if (yavlan_ext_ptype_count >= YAVLAN_LIST_SIZE) {
			printk(KERN_WARNING "YaVLAN: Too many VLAN definitions, ignored more.\n");
			break;
		}
		__pt = &yavlan_ext_ptype[yavlan_ext_ptype_count++];
		__pt->type = htons(proto_id);
		__pt->func = yavlan_ext_rcv;
		__pt->dev = NULL;
		dev_add_pack(__pt);
	}

	printk(KERN_INFO "YaVLAN - Yet another VLAN implementation\n");
	return 0;

out:
	__try_release_vlan_defs();
	return err;
}

void __exit yavlan_exit(void)
{
	int i;

	for (i = 0; i < yavlan_ext_ptype_count; i++) {
		struct packet_type *__pt = &yavlan_ext_ptype[i];
		if (__pt->func == NULL)
			continue;
		dev_remove_pack(__pt);
	}
	yavlan_ext_ptype_count = 0;

	dev_remove_pack(&yavlan_base_ptype);
	unregister_netdevice_notifier(&hooked_dev_notifier);

	__try_release_vlan_defs();
}

module_init(yavlan_init);
module_exit(yavlan_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Jianying Liu");
MODULE_DESCRIPTION("YaVLAN - Yet another VLAN implementation");
MODULE_VERSION("0.1.1");

