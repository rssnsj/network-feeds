update:
	./china-routes.sh > china
	./china-routes6.sh > china6
	./gfwlist.sh > china-banned
	md5sum china china6 china-banned > MD5SUMS
	mv -f china ../files/etc/ipset/china
	mv -f china6 ../files/etc/ipset/china6
	mv -f china-banned ../files/etc/gfwlist/china-banned

commit: update
	@if [ -n "`git diff --name-status -- ../files/etc MD5SUMS`" ]; then \
		git commit .. -m "Update data - $(shell date +%Y/%m/%d)"; \
	else \
		echo "No change to commit."; \
	fi

clean:
	rm -f apnic.txt china.apnic china.ipip china.merged gfwlist.txt ipip.txt
	$(MAKE) clean -C ipv4-merger
	$(MAKE) clean -C netmask

