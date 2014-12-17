#include <linux/kernel.h>
#include <linux/version.h>
#include <linux/module.h>
#include <linux/types.h>
#include <linux/netdevice.h>
#include <linux/skbuff.h>
#include <linux/etherdevice.h>
#include <linux/if_ether.h>
#include <net/rtnetlink.h>

#if LINUX_VERSION_CODE < KERNEL_VERSION(3, 14, 0)
	#define ether_addr_equal(a, b) (!compare_ether_addr((a), (b)))
#endif

static struct net_device *dev1 = NULL;
static struct net_device *dev2 = NULL;
static int mac_swap_factor = 0;
static bool packet_processor_hooked = false;

static char param_dev1[IFNAMSIZ] = "";
module_param_string(dev1, param_dev1, sizeof(param_dev1), 0644);
MODULE_PARM_DESC(dev1, "Device 1");

static char param_dev2[IFNAMSIZ] = "";
module_param_string(dev2, param_dev2, sizeof(param_dev2), 0644);
MODULE_PARM_DESC(dev2, "Device 2");

module_param_named(ms, mac_swap_factor, int, 0644);
MODULE_PARM_DESC(ms, "MAC swapping factor");

static int pppoe_bridge_rcv(struct sk_buff *skb, struct net_device *dev,
		struct packet_type *pt, struct net_device *orig_dev)
{
	struct ethhdr *mh = eth_hdr(skb);
	struct net_device *to = NULL;
	struct sk_buff *nskb;
	int md = 0;

	/* Ignore non-ethernet packets */
	if (!mh)
		goto out;

	/* Ignore packets sent to this host */
	if (ether_addr_equal(mh->h_dest, dev->dev_addr))
		goto out;

	/* Sent out through the other interface */
	if (dev == dev1) {
		to = dev2;
		md = mac_swap_factor;
	} else if (dev == dev2) {
		to = dev1;
		md = -mac_swap_factor;
	} else {
		goto out;
	}

	if (md) {
		nskb = skb_copy(skb, GFP_ATOMIC);
	} else {
		nskb = skb_clone(skb, GFP_ATOMIC);
	}
	if (!nskb)
		goto out;
	kfree_skb(skb);
	skb = nskb;
	mh = eth_hdr(skb);

	if (md) {
		if (!is_multicast_ether_addr(mh->h_dest))
			mh->h_dest[2] += md;
		if (!is_multicast_ether_addr(mh->h_source))
			mh->h_source[2] += md;
	}

	nf_reset(skb);
	skb_push(skb, skb->data - skb_mac_header(skb));
	skb->dev = to;
	dev_queue_xmit(skb);

	return 0;

out:
	kfree_skb(skb);
	return 0;
}

static struct packet_type pppoe_bridge_ptypes[] = {
	{
		.type = __constant_htons(ETH_P_PPP_DISC),
		.func = pppoe_bridge_rcv,
		.dev  = NULL,
	}, {
		.type = __constant_htons(ETH_P_PPP_SES),
		.func = pppoe_bridge_rcv,
		.dev  = NULL,
	},
};

static void hook_packet_processor(void)
{
	if (packet_processor_hooked)
		return;

	dev_add_pack(&pppoe_bridge_ptypes[0]);
	dev_add_pack(&pppoe_bridge_ptypes[1]);

	dev_set_promiscuity(dev1, 1);
	dev_set_promiscuity(dev2, 1);

	packet_processor_hooked = true;

	printk(KERN_INFO "pppoe_bridge: Packet processor hooked to %s, %s.\n",
			dev1->name, dev2->name);
}

static void unhook_packet_processor(void)
{
	if (!packet_processor_hooked)
		return;

	packet_processor_hooked = false;

	dev_set_promiscuity(dev1, -1);
	dev_set_promiscuity(dev2, -1);

	dev_remove_pack(&pppoe_bridge_ptypes[0]);
	dev_remove_pack(&pppoe_bridge_ptypes[1]);

	printk(KERN_INFO "pppoe_bridge: Packet processor unhooked from %s, %s.\n",
			dev1->name, dev2->name);
}

static int hooked_dev_event(struct notifier_block *unused,
	unsigned long event, void *ptr)
{
#if LINUX_VERSION_CODE >= KERNEL_VERSION(3, 11, 0)
	struct net_device *dev = netdev_notifier_info_to_dev(ptr);
#else
	struct net_device *dev = ptr;
#endif

	switch (event) {
	case NETDEV_REGISTER:
		if (dev1 && dev2)
			return NOTIFY_DONE;
		if (strcmp(dev->name, param_dev1) == 0) {
			dev_hold(dev);
			dev1 = dev;
		} else if (strcmp(dev->name, param_dev2) == 0) {
			dev_hold(dev);
			dev2 = dev;
		} else {
			return NOTIFY_DONE;
		}
		if (dev1 && dev2)
			hook_packet_processor();
		return NOTIFY_DONE;
	case NETDEV_UNREGISTER:
		if (dev == dev1) {
			unhook_packet_processor();
			dev1 = NULL;
			dev_put(dev);
		} else if (dev == dev2) {
			unhook_packet_processor();
			dev2 = NULL;
			dev_put(dev);
		}
		return NOTIFY_DONE;
	}

	return NOTIFY_DONE;
}

static struct notifier_block hooked_dev_notifier = {
	.notifier_call = hooked_dev_event,
};

int __init pppoe_bridge_init(void)
{
	if (strlen(param_dev1) == 0 || strlen(param_dev2) == 0) {
		printk(KERN_WARNING "pppoe_bridge: Insufficient parameters.\n");
		goto out;
	}
	if (strcmp(param_dev1, param_dev2) == 0) {
		printk(KERN_WARNING "pppoe_bridge: Interfaces cannot be the same.\n");
		goto out;
	}

	/* This calls the notifier callback in which the hook is added. */
	register_netdevice_notifier(&hooked_dev_notifier);

	printk(KERN_INFO "PPPoE bridging module loaded.\n");
	return 0;
out:
	return -EINVAL;
}

void __exit pppoe_bridge_exit(void)
{
	unregister_netdevice_notifier(&hooked_dev_notifier);
}

module_init(pppoe_bridge_init);
module_exit(pppoe_bridge_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Jianying Liu");
MODULE_DESCRIPTION("PPPoE bridging module");
MODULE_VERSION("0.0.1");

