update:
	./china-routes.sh > ../files/etc/ipset/china
	./gfwlist.sh > ../files/etc/gfwlist/china-banned

commit: update
	@if [ "`git diff --name-status -- ../files | wc -l`" -gt 0 ]; then \
		git commit .. -m "Update data - $(shell date +%Y/%m/%d)"; \
	else \
		echo "No change to commit."; \
	fi

clean:
	rm -f apnic.txt china.apnic china.ipip china.merged gfwlist.txt ipip.txt
	$(MAKE) clean -C ipv4-merger
	$(MAKE) clean -C netmask

