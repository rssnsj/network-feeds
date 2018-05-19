update:
	./china-routes.sh > ../files/etc/ipset/china
	./gfwlist.sh > ../files/etc/gfwlist/china-banned

clean:
	rm -f apnic.txt china.apnic china.ipip china.merged gfwlist.txt ipip.txt
	$(MAKE) clean -C ipv4-merger
	$(MAKE) clean -C netmask

